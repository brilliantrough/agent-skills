#!/usr/bin/env node
// 验证固定源码、实际 tar 资产和三条运行路径；不调用模型，不写共享 context.db。
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { execFile, execFileSync, spawn } from "node:child_process";
import { promisify } from "node:util";

const REPO = process.argv[2];
if (!REPO) {
  console.error("用法: node verify.mjs <上游源码目录>");
  process.exit(2);
}
const PREFIX = "ctxm_";
const TOOLS = ["execute", "batch", "index", "search", "resume", "stats", "doctor", "upgrade", "purge"].map((name) => PREFIX + name).sort();
const SELF_REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DIST = join(SELF_REPO, "context-mode", "dist");
const checks = [];
const check = (name, ok, detail = "") => checks.push({ name, ok, detail });
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const [major, minor] = process.versions.node.split(".").map(Number);
check("验证运行时为 Node >=24.15", major > 24 || major === 24 && minor >= 15, process.version);

const dispatch = readFileSync(join(REPO, "src/core/hooks/dispatch.ts"), "utf8");
const decide = readFileSync(join(REPO, "src/core/policy/decide.ts"), "utf8");
const fetchSource = readFileSync(join(REPO, "src/core/sandbox/fetch.ts"), "utf8");
const dbSource = readFileSync(join(REPO, "src/core/store/db.ts"), "utf8");
const instructions = readFileSync(join(REPO, "src/prompt/instructions.md"), "utf8");
check("主宿主只有 context-output 一个自动外置 owner", dispatch.includes('MAGIC_CONTEXT_PI_SUBAGENT !== "1") return ALLOW'));
check("主宿主不叠加上游路由拦截", decide.includes('MAGIC_CONTEXT_PI_SUBAGENT !== "1") return ALLOW') && decide.indexOf('MAGIC_CONTEXT_PI_SUBAGENT !== "1") return ALLOW') > decide.indexOf("if (hit !== null) return deny"));
check("显式代理与 origin SSRF 检查采用上游 #1403", fetchSource.includes("D-1403-PROXY-NOT-TARGET-1") && fetchSource.includes("await checkProxiedTarget(current, signal)"));
check("Bun 原子建库发布前显式 checkpoint", dbSource.includes('raw.exec("PRAGMA wal_checkpoint(TRUNCATE)")'));
check("系统提示写清 Bash、原生 Code Mode 与 snapshot", instructions.includes("native Bash") && instructions.includes("native Code Mode") && instructions.includes("context_output_read"));

for (const rel of ["server.mjs", "pi/index.js", "opencode/plugin.js"]) {
  const body = readFileSync(join(REPO, "release-out", rel), "utf8");
  check(`${rel} 无旧 ctx_ 前缀和 v1 API`, !/\bctx_[a-z_]/.test(body) && !/\bctxm_(execute_file|batch_execute|fetch_and_index)\b/.test(body));
}

const piTar = join(DIST, "pi-context-mode-vendor.tar.gz");
const ocTar = join(DIST, "opencode-context-mode-vendor.tar.gz");
check("两个发布资产存在", existsSync(piTar) && existsSync(ocTar));
try {
  execFileSync(process.execPath, [join(SELF_REPO, "context-mode/release.mjs"), REPO, "--check"], { stdio: "pipe" });
  check("发布资产与当前构建一致", true);
} catch (error) {
  check("发布资产与当前构建一致", false, String(error.stdout ?? error.message));
}

const tempBase = "/tmp/opencode";
mkdirSync(tempBase, { recursive: true });
const root = mkdtempSync(join(tempBase, "context-mode-v2-verify-"));
const piRoot = join(root, "pi"), ocRoot = join(root, "opencode");
mkdirSync(piRoot); mkdirSync(ocRoot);
try {
  execFileSync("tar", ["-xzf", piTar, "-C", piRoot]);
  execFileSync("tar", ["-xzf", ocTar, "-C", ocRoot]);
  check("两个 tar 均可解包", true);
} catch (error) {
  check("两个 tar 均可解包", false, error.message);
}
const pkg = JSON.parse(readFileSync(join(piRoot, "package.json"), "utf8"));
check("包声明 Pi/OpenCode 入口和 Node >=24.15", pkg.pi?.extensions?.[0] === "./pi/index.js" && pkg.exports?.["./server"] === "./opencode/plugin.js" && pkg.engines?.node === ">=24.15.0");
const skills = readdirSync(join(piRoot, "skills"), { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
check("包只带主指南、doctor、stats 三个 skills", same(skills, ["context-mode", "ctx-doctor", "ctx-stats"]), skills.join(" "));
check("DSH 所需 server 与许可证在包内", existsSync(join(piRoot, "server.mjs")) && existsSync(join(piRoot, "LICENSE")));
const mainSkill = readFileSync(join(piRoot, "skills/context-mode/SKILL.md"), "utf8");
check("主指南无旧 references 链接", !mainSkill.includes("references/") && mainSkill.includes("ctxm_batch") && mainSkill.includes("原生 Code Mode"));
const tarFiles = (tar) => execFileSync("tar", ["-tzf", tar]).toString().trim().split("\n").sort();
check("两个资产文件布局一致", same(tarFiles(piTar), tarFiles(ocTar)));

const dataDir = join(root, "data");
const home = join(root, "home");
mkdirSync(home);
const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: join(home, "config"), XDG_DATA_HOME: join(home, "data"), CONTEXT_MODE_DATA_DIR: dataDir, NODE_PATH: "" };
delete env.MAGIC_CONTEXT_PI_SUBAGENT;
process.env.HOME = home;
process.env.CONTEXT_MODE_DATA_DIR = dataDir;
delete process.env.MAGIC_CONTEXT_PI_SUBAGENT;
const bigFile = join(root, "large-read.txt");
writeFileSync(bigFile, "r".repeat(20000));
const large = "x".repeat(20000);

// Pi：真实扩展工厂、工具执行、主宿主 tool_call/tool_result 行为。
try {
  const handlers = new Map(), tools = new Map();
  const pi = {
    on(name, handler) { handlers.set(name, handler); },
    registerTool(tool) { tools.set(tool.name, tool); },
    getSettings() { return {}; },
  };
  const mod = await import(pathToFileURL(join(piRoot, "pi/index.js")).href);
  mod.default(pi);
  const ctx = { cwd: SELF_REPO, sessionManager: { getSessionId: () => "verify-pi-v2" } };
  const sections = {};
  await handlers.get("before_agent_start")({ prompt: "verify", systemPrompt: "base", systemPromptOptions: { sections } }, ctx);
  check("Pi 注册 9 个 ctxm_* 工具", same([...tools.keys()].sort(), TOOLS), [...tools.keys()].join(" "));
  check("Pi 注入中立路由和单一 snapshot 说明", sections.context_mode?.includes("native Code Mode") && sections.context_mode?.includes("context_output_read"));
  const executed = await tools.get("ctxm_execute").execute("exec", { language: "javascript", code: "console.log('pi-ok')" }, new AbortController().signal);
  check("Pi ctxm_execute 真实执行", executed.content?.[0]?.text.trim() === "pi-ok", JSON.stringify(executed));
  const replaced = await handlers.get("tool_result")({ toolName: "bash", toolCallId: "large", input: { command: "produce-large-output" }, content: [{ type: "text", text: large }], isError: false }, ctx);
  check("Pi 大输出不由 context-mode 二次替换", replaced === undefined, JSON.stringify(replaced)?.slice(0, 300));
  const denied = await handlers.get("tool_call")({ toolName: "read", toolCallId: "read-large", input: { path: bigFile } }, ctx);
  check("Pi 大文件 Read 不被 context-mode 拦截", denied === undefined, JSON.stringify(denied));
  const webfetch = await handlers.get("tool_call")({ toolName: "webfetch", toolCallId: "webfetch", input: { url: "https://example.com" } }, ctx);
  check("Pi WebFetch 不被强制改道 ctxm", webfetch === undefined, JSON.stringify(webfetch));
  check("ctxm_upgrade 明确禁用", tools.get("ctxm_upgrade")?.description.includes("FORK: do not call"));
} catch (error) {
  check("Pi 扩展真实加载与行为", false, error.stack ?? error.message);
}

// OpenCode：在实际 Bun 运行时调用官方 setup(ctx)，不经过本仓旧转发层。
const ocProbe = join(root, "opencode-probe.mjs");
writeFileSync(ocProbe, `
const handlers = { tool: {}, session: {} }, tools = new Map();
const disposable = () => ({ dispose: async () => {} });
const ctx = {
  location: { directory: ${JSON.stringify(SELF_REPO)} },
  tool: {
    transform: async (cb) => { cb({ add: (tool) => tools.set(tool.name, tool) }); return disposable(); },
    hook: async (name, cb) => { handlers.tool[name] = cb; return disposable(); },
  },
  session: { hook: async (name, cb) => { handlers.session[name] = cb; return disposable(); } },
  permission: { assert: async () => {} },
  agent: { get: async () => ({ data: { mode: "main", permissions: [] } }) },
  event: { subscribe: async function* () {} },
};
try {
  const mod = await import(${JSON.stringify(pathToFileURL(join(ocRoot, "opencode/plugin.js")).href)});
  const dispose = await mod.setup(ctx);
  const exec = await tools.get("ctxm_execute").execute({ language: "javascript", code: "console.log('oc-ok')" }, { sessionID: "verify-oc-v2", id: "exec", signal: new AbortController().signal });
  const indexed = await tools.get("ctxm_index").execute({ path: "context-mode/guidance.md" }, { sessionID: "verify-oc-v2", id: "index", signal: new AbortController().signal });
  const searched = await tools.get("ctxm_search").execute({ queries: ["context_output_read"] }, { sessionID: "verify-oc-v2", id: "search", signal: new AbortController().signal });
  await handlers.tool["execute.before"]({ tool: "read", sessionID: "verify-oc-v2", id: "read-large", input: { path: ${JSON.stringify(bigFile)} }, agent: "main" });
  await handlers.tool["execute.before"]({ tool: "webfetch", sessionID: "verify-oc-v2", id: "webfetch", input: { url: "https://example.com" }, agent: "main" });
  const after = { tool: "bash", sessionID: "verify-oc-v2", id: "large", input: { command: "produce-large-output" }, agent: "main", status: "completed", result: { content: [{ type: "text", text: ${JSON.stringify(large)} }] } };
  await handlers.tool["execute.after"](after);
  const context = { sessionID: "verify-oc-v2", system: [{ type: "text", text: "base" }] };
  await handlers.session.context(context);
  console.log(JSON.stringify({
    names: [...tools.keys()].sort(), exec: exec.content,
    indexed: indexed.content, searched: searched.content,
    largeSame: after.result.content[0].text === ${JSON.stringify(large)},
    prompt: context.system.map((p) => p.text).join("\\n"),
    codemode: tools.get("ctxm_execute").options.codemode,
    pinned: tools.get("ctxm_execute").options.pinned,
  }));
  await dispose();
} catch (error) { console.error(error.stack ?? error.message); process.exit(1); }
`);
try {
  const bun = process.env.BUN_BIN ?? "bun";
  const { stdout, stderr } = await promisify(execFile)(bun, ["--no-install", ocProbe], { cwd: SELF_REPO, env, timeout: 120000 });
  const result = JSON.parse(stdout.trim().split("\n").at(-1));
  check("OpenCode/Bun 注册 9 个直接工具", same(result.names, TOOLS) && result.codemode === false && result.pinned === undefined, result.names.join(" "));
  check("OpenCode ctxm_execute 真实执行", result.exec?.trim() === "oc-ok", result.exec);
  check("OpenCode 索引真实建库", typeof result.indexed === "string" && !result.indexed.includes("disk I/O error"), result.indexed);
  check("OpenCode 检索真实读库", result.searched?.includes("context_output_read"), result.searched?.slice(0, 500));
  check("OpenCode journal 无静默写库失败", !stderr.includes("journal write failed") && !stderr.includes("store failed"), stderr.slice(0, 500));
  check("OpenCode 大输出、大读与 WebFetch 不被强制改道", result.largeSame === true);
  check("OpenCode 系统提示来自 v2 中立路由", result.prompt.includes("native Code Mode") && result.prompt.includes("context_output_read"));
} catch (error) {
  check("OpenCode/Bun 官方 setup(ctx) 真实加载", false, String(error.stderr ?? error.stdout ?? error.message).slice(-1500));
}

// DSH 共用 MCP server：stdio 初始化、工具表、执行、显式索引与检索。
if (existsSync(join(piRoot, "server.mjs"))) {
  const url = "https://raw.githubusercontent.com/mksglu/context-mode/v2.2.1/README.md";
  const child = spawn(process.execPath, [join(piRoot, "server.mjs"), "--agent", "opencode"], { cwd: SELF_REPO, env, stdio: ["pipe", "pipe", "pipe"] });
  let buffer = "", stderr = "";
  const waiters = new Map();
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.stdout.on("data", (chunk) => {
    buffer += chunk;
    let at;
    while ((at = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, at).trim(); buffer = buffer.slice(at + 1);
      if (!line) continue;
      try {
        const message = JSON.parse(line);
        if (message.id != null && waiters.has(message.id)) { waiters.get(message.id)(message); waiters.delete(message.id); }
      } catch { /* MCP 日志不是响应 */ }
    }
  });
  const rpc = (id, method, params) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => { if (waiters.delete(id)) reject(new Error(`${method} 超时`)); }, 30000);
    waiters.set(id, (message) => { clearTimeout(timer); resolve(message); });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
  try {
    await rpc(1, "initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "verify-fork", version: "2.0.0" } });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    const listed = await rpc(2, "tools/list", {});
    const tools = listed.result?.tools ?? [];
    check("MCP server 列出 9 个 ctxm_* 工具", same(tools.map((tool) => tool.name).sort(), TOOLS), tools.map((tool) => tool.name).join(" "));
    check("MCP 描述无旧工具名", tools.every((tool) => !/\bctx_[a-z_]/.test(tool.description ?? "")));
    const executed = await rpc(3, "tools/call", { name: "ctxm_execute", arguments: { language: "javascript", code: "console.log('mcp-ok')" } });
    const execText = executed.result?.content?.map((part) => part.text ?? "").join("\n") ?? "";
    check("MCP ctxm_execute 真实执行", execText.trim() === "mcp-ok", execText || JSON.stringify(executed));
    const indexed = await rpc(4, "tools/call", { name: "ctxm_index", arguments: { path: "context-mode/guidance.md" } });
    const indexText = indexed.result?.content?.map((part) => part.text ?? "").join("\n") ?? "";
    check("MCP 显式索引本地文件", !indexed.error && !indexed.result?.isError, indexText || JSON.stringify(indexed));
    const searched = await rpc(5, "tools/call", { name: "ctxm_search", arguments: { queries: ["context_output_read"] } });
    const searchText = searched.result?.content?.map((part) => part.text ?? "").join("\n") ?? "";
    check("MCP 检索已索引内容", !searched.error && !searched.result?.isError && searchText.includes("context_output_read"), searchText.slice(0, 600) || JSON.stringify(searched));
    const fetched = await rpc(6, "tools/call", { name: "ctxm_index", arguments: { url } });
    const fetchText = fetched.result?.content?.map((part) => part.text ?? "").join("\n") ?? "";
    check("MCP ctxm_index(url) 真实抓取", !fetched.error && !fetched.result?.isError, fetchText || JSON.stringify(fetched));
    const foundUrl = await rpc(7, "tools/call", { name: "ctxm_search", arguments: { queries: ["Folds old tool output"] } });
    const urlText = foundUrl.result?.content?.map((part) => part.text ?? "").join("\n") ?? "";
    check("MCP 检索 URL 正文", !foundUrl.error && !foundUrl.result?.isError && urlText.includes("Folds old tool output"), urlText.slice(0, 600) || JSON.stringify(foundUrl));
    const privateUrl = await rpc(8, "tools/call", { name: "ctxm_index", arguments: { url: "http://127.0.0.1/" } });
    const privateText = privateUrl.result?.content?.map((part) => part.text ?? "").join("\n") ?? "";
    check("本地代理存在时仍拒绝私网 URL", privateUrl.result?.isError === true && privateText.includes("Blocked private address 127.0.0.1"), privateText || JSON.stringify(privateUrl));
  } catch (error) {
    check("MCP stdio 运行路径", false, `${error.message}; stderr=${stderr.slice(-800)}`);
  } finally {
    await new Promise((resolve) => { child.once("exit", resolve); child.kill(); setTimeout(resolve, 3000).unref(); });
  }
}

rmSync(root, { recursive: true, force: true });
const failed = checks.filter((item) => !item.ok);
for (const item of checks) console.log(`${item.ok ? "✓" : "✗"} ${item.name}${item.ok || !item.detail ? "" : ` — ${item.detail}`}`);
if (failed.length) {
  console.error(`\n[fork-verify] ${failed.length}/${checks.length} 项失败`);
  process.exit(1);
}
console.log(`\n[fork-verify] ${checks.length} 项全过；未调用模型，未写共享 DB`);
