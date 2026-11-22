// node tests/dsh-subagent-host.mjs；真实 DSH 宿主加载与委派验收（项目特化 Verification 子代理）。
//
// 覆盖：仓库 deploy.mjs／bundle／模板部署到临时 root → headless 真实启动 → 主 Agent 工具表含
// verification_review 且 agent_preset.enum 只含 verification-reviewer → 本地 dummy 驱动真实委派 →
// 子会话生成并 settled → 子 Agent 白名单、执行层拒绝 write、read 可用、bash 可写（只读仅提示词）→
// Linux 白名单负例（allow 里出现 pwsh 必须报 unknown global tool）。
//
// 只读引用注入的隔离运行时；写盘、dummy 服务、子进程全在本次 mkdtemp 内，结束即清理。
//   DSH_TEST_RUNTIME=/path/to/isolated-dsh-runtime node tests/dsh-subagent-host.mjs
// 不带该变量时输出 SKIP HOST 并以 0 退出；显式给了不可用的运行时报错退出 1。
import assert from "node:assert/strict";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { zstdDecompressSync } from "node:zlib";
import { cp, mkdir, mkdtemp, readdir, readFile, realpath, rm, stat, symlink, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import { createRequire } from "node:module";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DEPLOY = join(REPO, "dsh/deploy.mjs");
const TEMPLATE = join(REPO, "templates/dsh/cordis.patch.json");
const FIXTURES = join(REPO, "tests/fixtures/dsh");
const HOST = process.env.DSH_TEST_RUNTIME ? resolve(process.env.DSH_TEST_RUNTIME) : undefined;
const LIVE = resolve(process.env.HOME ?? "/nonexistent", ".local/share/agent-skills/dsh/runtime");
const RUNTIME_VERSION = "0.2.1-rc.2";
const CHILD_ALLOW = ["bash", "glob", "grep", "read", "read_image"];
const VERIFICATION = "verification-reviewer";

// 注入运行时必须是完整、可解析、且不是正式安装目录的一次性副本；缺包或断链会让 bundle 静默退回旧锚点。
function hostProblem() {
  if (HOST === undefined) return "未设置 DSH_TEST_RUNTIME（需一次性隔离 rc.2 runtime）";
  if (HOST === LIVE || (existsSync(HOST) && existsSync(LIVE) && realpathSync(HOST) === realpathSync(LIVE))) return `DSH_TEST_RUNTIME 指向正式安装目录：${HOST}`;
  const pkg = join(HOST, "node_modules/@deepseek-ai/dsh/package.json");
  if (!existsSync(pkg)) return `DSH_TEST_RUNTIME 不是完整运行时（缺 ${pkg}）`;
  const version = JSON.parse(readFileSync(pkg, "utf8")).version;
  if (version !== RUNTIME_VERSION) return `DSH_TEST_RUNTIME 版本应为 ${RUNTIME_VERSION}，实际 ${version}`;
  for (const name of ["dsh-agent-preset", "dsh-tool-subagent", "dsh-persona", "dsh-agent-preset-registry", "dsh-llm-deepseek", "typescript"]) {
    if (!existsSync(join(HOST, "node_modules/@deepseek-ai", name)) && !existsSync(join(HOST, "node_modules", name))) {
      return `DSH_TEST_RUNTIME 缺依赖 ${name}`;
    }
  }
  return undefined;
}

const exists = (path) => existsSync(path);

// 入口放在文件末尾：main 里引用的常量在模块体执行完前处于 TDZ。
async function entry() {
  const problem = hostProblem();
  // 显式给了不可用的运行时是配置错误，不能当成"没有宿主"而放过。
  if (problem && HOST !== undefined) {
    process.stdout.write(`ERROR ${problem}\n`);
    process.exit(1);
  }
  if (problem) {
    process.stdout.write(`SKIP HOST: ${problem}\nPASS: dsh-subagent-host 入口（HOST 场景未执行）\n`);
    process.exit(0);
  }
  try {
    await main();
  } catch (error) {
    process.stdout.write(`FAIL ${error?.message ?? error}\n`);
    process.exitCode = 1;
  }
}

// 只读复用注入运行时：除安装锚点、解析器和 typescript 外全部软链；自建 bundle/vendor 用相对链接，
// 部署换位后仍指向沙箱副本，不会解析回宿主。注入运行时自带的 bundle/vendor 链接必须跳过，
// 否则会指向它的 bundle 而不是本次部署结果。断链要早失败：那正是"静默解析回别的锚点"的来源。
// copies 用作用域限定的相对路径（如 "@deepseek-ai/dsh"），裸名会误配同名的别家包。
async function linkModules(source, target, copies, skip = new Set(), prefix = "") {
  await mkdir(target, { recursive: true });
  for (const name of await readdir(source)) {
    if (name.startsWith(".")) continue;
    const from = join(source, name), to = join(target, name), key = prefix ? `${prefix}/${name}` : name;
    if (skip.has(key)) continue;
    if (copies.has(key)) await cp(from, to, { recursive: true, dereference: true });
    else if (name.startsWith("@")) await linkModules(from, to, copies, skip, key);
    else {
      // stat 跟随链接：断链抛 ENOENT，正好用来拒绝半坏的运行时。
      try { await stat(from); }
      catch { throw new Error(`注入运行时含断链 ${from}，不是可用的隔离运行时`); }
      await symlink(from, to);
    }
  }
}

// 本地 dummy Anthropic SSE（不发真实模型请求）。按请求状态推进：主 Agent 首轮委派；
// 子 Agent 依次尝试 write（应被拒）→ read（应成功）→ bash（在临时工作目录可写）→ 收尾。
function startDummy(files, rewriteMode = false) {
  const log = [];
  const send = (res, event) => res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      const payload = JSON.parse(body);
      const names = (payload.tools ?? []).map((tool) => tool.name);
      const results = (payload.messages ?? [])
        .flatMap((message) => (Array.isArray(message.content) ? message.content : []))
        .filter((block) => block.type === "tool_result");
      // 父 Agent 一定有 verification_review；子 Agent 的工具表是白名单子集，永远没有它。
      // 用这一点区分父子，不依赖白名单内容本身（否则白名单被改宽时会把子请求误判成父请求）。
      const isChild = names.length > 0 && !names.includes("verification_review");
      log.push({
        names, isChild, tools: payload.tools ?? [], results: results.length,
        messages: rewriteMode ? payload.messages : undefined, rewriteMode,
        // 执行层结论：write 必须报错，read／bash 必须成功。
        outcomes: results.map((block) => ({
          error: block.is_error === true,
          text: (typeof block.content === "string" ? block.content : JSON.stringify(block.content)).slice(0, 300),
        })),
      });

      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
      send(res, { type: "message_start", message: { id: `m${log.length}`, type: "message", role: "assistant", model: payload.model ?? "dummy", content: [], stop_reason: null, stop_sequence: null, usage: { input_tokens: 1, output_tokens: 0 } } });
      const finish = (reason) => {
        send(res, { type: "message_delta", delta: { stop_reason: reason, stop_sequence: null }, usage: { output_tokens: 1 } });
        send(res, { type: "message_stop" });
        res.end();
      };
      const call = (name, input) => {
        send(res, { type: "content_block_start", index: 0, content_block: { type: "tool_use", id: `toolu_${log.length}`, name, input: {} } });
        send(res, { type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: JSON.stringify(input) } });
        send(res, { type: "content_block_stop", index: 0 });
        finish("tool_use");
      };
      if (rewriteMode && names.length > 0) {
        const mainRequests = log.filter((row) => row.rewriteMode && row.names.length > 0).length;
        if (mainRequests === 1) return call("read", { file_path: files.readable });
        if (mainRequests === 2) return call("context_rewrite", { ids: [1], note: "REWRITE-NOTE-7328" });
      } else if (!rewriteMode && isChild) {
        if (results.length === 0) return call("write", { file_path: files.forbidden, content: "x" });
        if (results.length === 1) return call("read", { file_path: files.readable });
        if (results.length === 2) return call("bash", { description: "子代理 bash 边界", command: "printf CHILD-BASH-RAN > bash-proof.txt && cat bash-proof.txt" });
      } else if (results.length === 0 && names.includes("verification_review")) {
        return call("verification_review", { description: "真实宿主验收", prompt: "复核本地 dummy" });
      }
      send(res, { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } });
      send(res, { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "ok" } });
      send(res, { type: "content_block_stop", index: 0 });
      finish("end_turn");
    });
  });
  return new Promise((ready) => server.listen(0, "127.0.0.1", () => ready({ server, log, port: server.address().port })));
}

// 真实子进程：超时即 SIGKILL，保证失败路径也不留进程。
function runNode(bin, args, env, cwd, timeout = 180000) {
  return new Promise((done) => {
    const child = spawn(process.execPath, [bin, ...args], { cwd, env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "", stderr = "";
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    const timer = setTimeout(() => child.kill("SIGKILL"), timeout);
    child.on("close", (status, signal) => {
      clearTimeout(timer);
      done({ status, signal, stdout, stderr });
    });
  });
}

// DSH 会话日志是分段追加的 zstd（每帧一条记录），单帧解压只能拿到第一帧。
const ZSTD_MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
function readZstdFrames(buffer) {
  const starts = [];
  for (let i = 0; i <= buffer.length - 4; i += 1) if (buffer.subarray(i, i + 4).equals(ZSTD_MAGIC)) starts.push(i);
  let text = "";
  for (const [index, start] of starts.entries()) {
    const frame = buffer.subarray(start, starts[index + 1] ?? buffer.length);
    try { text += zstdDecompressSync(frame).toString("utf8"); } catch { /* 尾部未写完的帧忽略 */ }
  }
  return text;
}

// 读两类落盘证据：pi2dsh 旁路 jsonl 与 DSH 原生会话（含子会话的 origin／agentPreset）。
async function readSessionText(dir) {
  const parts = [];
  const walk = async (path) => {
    for (const entry of await readdir(path, { withFileTypes: true }).catch(() => [])) {
      const next = join(path, entry.name);
      if (entry.isDirectory()) await walk(next);
      else if (entry.name.endsWith(".jsonl")) parts.push(await readFile(next, "utf8"));
      else if (entry.name.endsWith(".jsonl.zstd")) parts.push(readZstdFrames(await readFile(next)));
    }
  };
  await walk(dir);
  return parts;
}

function pass(name) {
  process.stdout.write(`PASS ${name}\n`);
}

async function main() {
  const started = Date.now();
  const sandbox = await mkdtemp(join(tmpdir(), "dsh-subagent-host-"));
  let dummy, rewriteDummy;
  try {
    const root = join(sandbox, "root"), runtime = join(root, "runtime");
    const env = { ...process.env };
    for (const key of Object.keys(env)) if (/NEWAPI|^DSH_|CLAUDE_MEM|^npm_config_/.test(key)) delete env[key];
    Object.assign(env, {
      HOME: join(sandbox, "home"), DSH_HOME: join(sandbox, "dsh"),
      // fixture 补丁引用的 4 个 provider 凭据；部署要求最终配置里引用可解析。
      CLAUDE_NEWAPI_API_KEY: "k-claude", CODEX_NEWAPI_API_KEY: "k-codex",
      ANTHROPIC_NEWAPI_API_KEY: "k-anthropic", GEMINI_NEWAPI_API_KEY: "k-gemini",
      CLAUDE_NEWAPI_BASE_URL: "https://claude.example/v1", CODEX_NEWAPI_BASE_URL: "https://codex.example/v1",
      ANTHROPIC_NEWAPI_BASE_URL: "https://anthropic.example/v1", GEMINI_NEWAPI_BASE_URL: "https://gemini.example/v1beta",
      // 部署判定依赖不变时不会跑 npm；这个不可达 registry 只防意外联网。
      npm_config_registry: "http://127.0.0.1:9/", npm_config_offline: "true",
    });
    await mkdir(env.HOME, { recursive: true });

    // 部署按"依赖不变"只读复用 node_modules，所以自建包链接必须在部署前就解析得到：
    // 预置与仓库同源的 bundle/vendor 副本，部署再整目录换成自己的暂存结果（内容同源，不会掩盖旧 bundle）。
    await mkdir(join(runtime, "bundle"), { recursive: true });
    await cp(join(REPO, "dsh"), join(runtime, "bundle/dsh"), { recursive: true,
      filter: (src) => !src.split("/").some((part) => part === "node_modules" || part === ".git") });
    await mkdir(join(runtime, "vendor"), { recursive: true });
    const magicContext = join(sandbox, "magic-context");
    await cp(join(FIXTURES, "magic-context"), magicContext, { recursive: true });
    await cp(magicContext, join(runtime, "vendor/magic-context"), { recursive: true });

    await linkModules(join(HOST, "node_modules"), join(runtime, "node_modules"),
      new Set(["@deepseek-ai/dsh", "@deepseek-ai/dsh-llm-deepseek", "typescript"]),
      new Set(["agent-skills-dsh", "dsh-plugin-magic-context"]));
    await symlink("../bundle/dsh", join(runtime, "node_modules/agent-skills-dsh"), "dir");
    await symlink("../vendor/magic-context", join(runtime, "node_modules/dsh-plugin-magic-context"), "dir");
    const manifest = JSON.parse(await readFile(join(REPO, "dsh/runtime.package.json"), "utf8"));
    manifest.dependencies.yaml = "2.8.1";
    manifest.dependencies["acp-kernel"] = "0.0.101";
    manifest.dependencies["agent-skills-dsh"] = "file:./bundle/dsh";
    await writeFile(join(runtime, "package.json"), JSON.stringify(manifest, null, 2) + "\n");
    // bundle 按安装锚点解析：锚点必须是沙箱自己的副本，否则会读到注入运行时里的旧 bundle。
    const anchor = await realpath(join(runtime, "node_modules/@deepseek-ai/dsh"));
    assert.ok(anchor.startsWith(await realpath(sandbox)), `安装锚点未落在沙箱内：${anchor}`);

    for (const profile of ["headless", "web", "tui"]) {
      const dir = join(env.DSH_HOME, "profiles", profile);
      await mkdir(dir, { recursive: true });
      await writeFile(join(dir, "package.json"), JSON.stringify({ private: true }, null, 2) + "\n");
      await writeFile(join(dir, "cordis.patch.yml"), await readFile(join(FIXTURES, "profile-patch.yml"), "utf8"));
    }
    await mkdir(join(env.HOME, ".pi/agent"), { recursive: true });
    await writeFile(join(env.HOME, ".pi/agent/models.json"), JSON.stringify({ providers: {} }));
    await writeFile(join(env.HOME, ".pi/agent/auth.json"), JSON.stringify({}));

    const deployed = spawnSync(process.execPath,
      [DEPLOY, "--root", root, "--source", REPO, "--template", TEMPLATE, "--magicContext", magicContext],
      { env, cwd: sandbox, encoding: "utf8", timeout: 300000 });
    assert.equal(deployed.status, 0, `部署失败：${deployed.stdout}${deployed.stderr}`);
    assert.ok(exists(join(runtime, "bundle/dsh/verification-policy.mjs")), "bundle 缺 verification-policy.mjs");
    const hostBin = join(runtime, "node_modules/@deepseek-ai/dsh/lib/bin.js");
    // 合成配置里没有条目，说明解析到了别的 bundle（旧锚点），后续断言会失去意义。
    const dumped = spawnSync(process.execPath, [hostBin, "--profile", "headless", "--dump-config"],
      { env, cwd: sandbox, encoding: "utf8", timeout: 60000 });
    assert.equal(dumped.status, 0, dumped.stderr);
    assert.match(dumped.stdout, /^- id: agent-skills-verification-reviewer$/m, "合成配置缺 verification preset");
    assert.match(dumped.stdout, /^- id: tool-verification-review$/m, "合成配置缺 verification_review 工具");
    pass("deploy 到临时 root，合成配置含 verification preset／工具");

    const work = join(sandbox, "work");
    await mkdir(work, { recursive: true });
    const files = { forbidden: join(work, "should-not-exist.txt"), readable: join(work, "readable.txt") };
    await writeFile(files.readable, "READ-MARKER-OK\n");
    dummy = await startDummy(files);

    const overlay = join(sandbox, "overlay.yml");
    // 覆盖层只接 dummy 模型和凭据，工具定义（尤其 toolName）原样取自本次部署写进 profile patch 的条目。
    // 测试不补写工具名：生产把它改名后 dummy 就收不到 verification_review，下面断言自然失败。
    const deployRequire = createRequire(join(runtime, "package.json"));
    const includeFile = deployRequire.resolve("@deepseek-ai/cordis-plugin-include");
    const patchYaml = createRequire(includeFile)("js-yaml");
    const { entryListSchema } = await import(pathToFileURL(includeFile).href);
    const deployedPatch = patchYaml.load(await readFile(join(env.DSH_HOME, "profiles/headless/cordis.patch.yml"), "utf8"), { schema: entryListSchema });
    const toolRow = deployedPatch.filter((row) => row?.id === "tool-verification-review").at(-1);
    assert.ok(toolRow?.config, "部署后的 profile patch 缺 tool-verification-review");
    await writeFile(overlay, JSON.stringify([
      { id: "llm-deepseek", config: { baseURL: `http://127.0.0.1:${dummy.port}`, apiKeyEnv: "ANTHROPIC_NEWAPI_API_KEY" } },
      // 子代理也走同一条本地 dummy：审查模型本身不是本测试的验收对象。
      { id: "tool-verification-review", config: { ...toolRow.config, agentOptions: { provider: "deepseek-official", model: "deepseek-flash" } } },
    ]) + "\n");

    const first = await runNode(hostBin, ["--profile", "headless", "--patch", overlay, "--json", "复核"], env, work);
    assert.equal(first.status, 0, `headless 失败：${first.stdout}\n${first.stderr}`);

    const parent = dummy.log.find((row) => !row.isChild && row.results === 0);
    assert.ok(parent, "未捕获主 Agent 首轮请求");
    const tool = parent.tools.find((row) => row.name === "verification_review");
    assert.ok(tool, `主 Agent 工具表缺 verification_review：${parent.names.join(",")}`);
    assert.deepEqual(tool.input_schema.properties.agent_preset.enum, [VERIFICATION],
      "agent_preset.enum 应只含 verification-reviewer（说明 preset 已在 registry 注册）");
    assert.deepEqual(tool.input_schema.required, ["description", "prompt"]);
    assert.ok(parent.names.includes("context_rewrite"), `主 Agent 工具表缺 context_rewrite：${parent.names.join(",")}`);
    assert.ok(!parent.names.includes("context_output_read"), "已退役的 context_output_read 仍在父 Agent 工具表");
    pass("近期纠错保留，context_output_read 已从真实宿主工具表退役");
    pass("headless 真实启动：主 Agent 工具表含 verification_review，preset 已注册");

    const child = dummy.log.filter((row) => row.isChild);
    assert.ok(child.length >= 4, `子会话请求数不足：${child.length}`);
    assert.deepEqual([...child[0].names].sort(), [...CHILD_ALLOW].sort(),
      `子 Agent 工具应只有 ${CHILD_ALLOW.join("/")}`);
    for (const banned of ["subagent", "subagent_fork", "verification_review", "consolidation_review", "edit", "write"]) {
      assert.ok(!child[0].names.includes(banned), `子 Agent 不应有 ${banned}`);
    }
    pass("子 Agent 仅有 read/read_image/glob/grep/bash，不能再委派");

    // 子会话与 settled 通知都在 DSH 原生会话日志里（子会话带 origin:subagent + agentPreset）。
    const sessions = (await readSessionText(env.DSH_HOME)).join("\n");
    assert.match(sessions, /"origin":"subagent"/, "未生成子会话");
    assert.match(sessions, /"agentPreset":"verification-reviewer"/, "子会话未绑定 verification-reviewer preset");
    assert.match(sessions, /"delegationDepth":1/, "子会话委派深度应为 1");
    assert.match(sessions, /复核本地 dummy/, "子会话缺委派 prompt");
    assert.match(sessions, /subagent-settled/, "父会话未收到 subagent-settled");
    pass("真实调用 verification_review：子会话生成并 settled 回父会话");

    assert.ok(!exists(files.forbidden), `子代理的 write 竟然落盘：${files.forbidden}`);
    // 执行层的直接证据：write 报错、read 读回内容、bash 有输出。
    const outcomes = child.flatMap((row) => row.outcomes);
    const failedWrite = outcomes.find((row) => row.error && /write/.test(row.text));
    assert.ok(failedWrite, `子代理 write 未被执行层拒绝：${JSON.stringify(outcomes)}`);
    assert.match(failedWrite.text, /unknown tool/);
    assert.ok(outcomes.some((row) => !row.error && /READ-MARKER-OK/.test(row.text)), "子代理 read 未成功读回内容");
    assert.ok(outcomes.some((row) => !row.error && /CHILD-BASH-RAN/.test(row.text)), "子代理 bash 未成功执行");
    const proof = join(work, "bash-proof.txt");
    assert.ok(exists(proof), "子代理 bash 未在工作目录写入");
    assert.equal((await readFile(proof, "utf8")).trim(), "CHILD-BASH-RAN");
    pass("write 被真实执行层拒绝；read 成功；bash 可写（只读是提示词约束，不是沙箱）");

    rewriteDummy = await startDummy(files, true);
    const rewriteOverlay = join(sandbox, "rewrite-overlay.json");
    await writeFile(rewriteOverlay, JSON.stringify([
      { id: "llm-deepseek", config: { baseURL: `http://127.0.0.1:${rewriteDummy.port}`, apiKeyEnv: "ANTHROPIC_NEWAPI_API_KEY" } },
    ]) + "\n");
    const rewriteRun = await runNode(hostBin, ["--profile", "headless", "--patch", rewriteOverlay, "--json", "验证近期改写"], env, work);
    assert.equal(rewriteRun.status, 0, `近期改写 headless 失败：${rewriteRun.stdout}\n${rewriteRun.stderr}`);
    assert.ok(rewriteDummy.log.length >= 3, `近期改写请求数不足：${rewriteDummy.log.length}`);
    const rewriteRequests = rewriteDummy.log.filter((row) => row.names.length > 0);
    assert.ok(rewriteRequests.length >= 3, `近期改写主请求数不足：${rewriteRequests.length}`);
    const withRead = JSON.stringify(rewriteRequests[1].messages);
    const afterRewrite = JSON.stringify(rewriteRequests[2].messages);
    assert.ok(withRead.includes("[context_op id=1"), `原 Read 结果缺 context_op marker：${withRead.slice(-800)}`);
    assert.ok(withRead.includes("READ-MARKER-OK"), "原 Read 内容未进入下一次请求");
    assert.ok(!afterRewrite.includes("READ-MARKER-OK"), "context_rewrite 后原 Read 内容仍发送给模型");
    assert.ok(afterRewrite.includes("REWRITE-NOTE-7328"), "context_rewrite 后未保留纠正 note");
    pass("read marker → context_rewrite：下一请求撤下原调用并保留纠正记录");

    if (process.platform === "win32") {
      process.stdout.write("SKIP 平台白名单负例：win32 上 pwsh 是合法工具\n");
    } else {
      // 负例：把另一平台 shell 写进 allow，宿主必须报未知工具而不能静默放过。
      await writeFile(join(runtime, "bundle/dsh/verification-policy.mjs"), [
        'export const name = "verification-reviewer-policy";',
        'export const inject = ["tools"];',
        "export function apply(ctx) {",
        '  ctx.tools.restrict({ allow: ["read", "read_image", "glob", "grep", "bash", "pwsh"] });',
        "}",
        "",
      ].join("\n"));
      const childRunsBefore = dummy.log.filter((row) => row.isChild).length;
      const second = await runNode(hostBin, ["--profile", "headless", "--patch", overlay, "--json", "复核"], env, work);
      const output = `${second.stdout}\n${second.stderr}`;
      // JSON 事件里的引号是转义的，所以只匹配稳定的前缀 + 工具名。
      assert.match(output, /unknown global tool[^;]*pwsh/, `加入 pwsh 后宿主应报未知工具：${output.slice(-800)}`);
      // 只有 preset 真的没启动，才不会出现新的子会话请求。
      assert.equal(dummy.log.filter((row) => row.isChild).length, childRunsBefore, "白名单非法时子代理不应启动");
      pass("Linux 白名单负例：allow 含 pwsh 被宿主拒绝");
    }

    process.stdout.write(`PASS dsh-subagent-host：真实宿主加载与委派（${((Date.now() - started) / 1000).toFixed(1)}s）\n`);
  } finally {
    dummy?.server.close();
    rewriteDummy?.server.close();
    await rm(sandbox, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await entry();
