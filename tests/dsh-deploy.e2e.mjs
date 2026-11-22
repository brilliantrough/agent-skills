// node tests/dsh-deploy.e2e.mjs；真实 dsh/deploy.mjs 入口，默认离线、隔离 HOME。
// 默认场景只要仓库与 Node；完整部署事务需要显式注入官方运行时：
//   DSH_TEST_RUNTIME=/path/to/isolated-dsh-runtime node tests/dsh-deploy.e2e.mjs
// 注入后只读使用该隔离运行时的 node_modules，并把测试会改写的包复制成本地副本；不得指向 live runtime。
import assert from "node:assert/strict";
import { chmod, cp, lstat, mkdir, mkdtemp, readFile, readdir, readlink, realpath, rm, symlink, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DEPLOY = join(REPO, "dsh/deploy.mjs");
const TEMPLATE = join(REPO, "templates/dsh/cordis.patch.json");
const FIXTURES = join(REPO, "tests/fixtures/dsh");
const HOST = process.env.DSH_TEST_RUNTIME ? resolve(process.env.DSH_TEST_RUNTIME) : undefined;
const PARSER = "node_modules/@deepseek-ai/dsh-llm-deepseek/lib/index.js";
const PARSER_ORIGINAL = 'if (started) return malformed("duplicate message_start");';
const PARSER_PATCHED = 'if (started) {\n\t\t\t\tif (blocks.size === 0 && reason === void 0) continue;\n\t\t\t\treturn malformed("duplicate message_start");\n\t\t\t}';
const KEYS = {
  CLAUDE_NEWAPI_API_KEY: "k-claude", CODEX_NEWAPI_API_KEY: "k-codex",
  ANTHROPIC_NEWAPI_API_KEY: "k-anthropic", GEMINI_NEWAPI_API_KEY: "k-gemini",
};
const URLS = {
  CLAUDE_NEWAPI_BASE_URL: "https://claude.example/v1", CODEX_NEWAPI_BASE_URL: "https://codex.example/v1",
  ANTHROPIC_NEWAPI_BASE_URL: "https://anthropic.example/v1", GEMINI_NEWAPI_BASE_URL: "https://gemini.example/v1beta",
};

let failed = 0, skipped = 0;
const cases = [];
const test = (name, fn) => cases.push([name, fn]);
const skip = (name, reason) => cases.push([name, undefined, reason]);

// 写入只落在各自 mkdtemp 里；HOME/DSH_HOME 都指向沙箱，环境里的网关变量一律清掉。
// 建沙箱本身失败也要清掉刚建的目录，调用方不必替它收拾。
async function sandbox() {
  const tmp = await mkdtemp(join(tmpdir(), "dsh-deploy-"));
  try {
    const env = { ...process.env };
    for (const key of Object.keys(env)) if (/NEWAPI|^DSH_|CLAUDE_MEM|^npm_config_/.test(key)) delete env[key];
    Object.assign(env, {
      HOME: join(tmp, "home"), DSH_HOME: join(tmp, "dsh"), DEEPSEEK_HOST: "deepseek.example",
      ...KEYS, ...URLS,
      // depsChanged 意外为真时让 npm 立刻失败，而不是偷偷联网。
      npm_config_registry: "http://127.0.0.1:9/", npm_config_offline: "true",
    });
    await mkdir(env.HOME, { recursive: true });
    await mkdir(join(env.DSH_HOME, "profiles"), { recursive: true });
    const run = (args) => spawnSync(process.execPath, [DEPLOY, ...args], { env, cwd: tmp, encoding: "utf8", timeout: 120000 });
    return { tmp, env, run };
  } catch (error) {
    await rm(tmp, { recursive: true, force: true });
    throw error;
  }
}

// profile 层 patch 留给部署合并，fixture 是用户已保存的旧 Gemini + !!js 形态。
async function seedProfiles(env, patch = join(FIXTURES, "profile-patch.yml")) {
  for (const profile of ["headless", "web", "tui"]) {
    const dir = join(env.DSH_HOME, "profiles", profile);
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, "package.json"), JSON.stringify({ private: true }, null, 2) + "\n");
    await writeFile(join(dir, "cordis.patch.yml"), await readFile(patch, "utf8"));
  }
}

// 目录树快照：内容、模式与链接目标都要一致才算没变化（端到端幂等与回滚的证据）。
async function snapshot(paths) {
  const rows = [];
  const walk = async (path) => {
    let stats;
    try { stats = await lstat(path); } catch { rows.push(`${path}\tabsent`); return; }
    if (stats.isSymbolicLink()) { rows.push(`${path}\tlink:${await readlink(path)}`); return; }
    if (stats.isDirectory()) {
      rows.push(`${path}\tdir:${(stats.mode & 0o777).toString(8)}`);
      for (const name of (await readdir(path)).sort()) await walk(join(path, name));
      return;
    }
    rows.push(`${path}\t${(stats.mode & 0o777).toString(8)}:${createHash("sha256").update(await readFile(path)).digest("hex")}`);
  };
  for (const path of paths) await walk(path);
  return rows.join("\n");
}

const digest = async (paths) => createHash("sha256").update(await snapshot(paths)).digest("hex");

// 事务残留的判据：暂存目录、runtime 换位目录、被中断的临时／交换名（都带数字时间戳后缀）。
// 不把 `.bak-` 算残留：成功写入会按设计保留备份；这些位置由快照逐字节比对覆盖。
const RESIDUE = /^\.deploy-|^runtime\.(bak|new|old|failed)-|\.(tmp|new|old|failed)-\d/;
async function residues(...roots) {
  const found = [];
  const walk = async (path) => {
    if (!(await lstat(path).catch(() => undefined))?.isDirectory()) return;
    for (const name of await readdir(path)) {
      if (name === "node_modules") continue;
      if (RESIDUE.test(name)) found.push(join(path, name));
      else await walk(join(path, name));
    }
  };
  for (const root of roots) await walk(root);
  return found;
}

// 官方运行时只读复用：顶层包逐个链接，会被改写的包复制成本地副本。
async function linkModules(source, target, copy = [], prefix = "") {
  await mkdir(target, { recursive: true });
  for (const name of await readdir(source)) {
    const from = join(source, name), to = join(target, name), path = prefix ? `${prefix}/${name}` : name;
    if (name.startsWith(".")) continue;
    if (copy.includes(path)) await cp(from, to, { recursive: true, dereference: true });
    else if (name.startsWith("@")) await linkModules(from, to, copy, path);
    else await symlink(from, to);
  }
}

const hostReady = () => HOST !== undefined && existsSync(join(HOST, "node_modules/@deepseek-ai/dsh/lib/bin.js"));

// 完整部署的沙箱：runtime 清单与 deploy 生成的一致，因此不会走 npm 安装。
// 创建中途失败也必须自己清掉沙箱（尤其是链接失败时留下的树），所以这里包 try/catch。
async function hostSandbox(source = HOST) {
  const box = await sandbox();
  try {
    const root = join(box.tmp, "root"), runtime = join(root, "runtime");
    await mkdir(runtime, { recursive: true });
    // 解析器包会被部署打补丁，必须用实体副本，不能链接或写穿官方运行时。
    await linkModules(join(source, "node_modules"), join(runtime, "node_modules"), ["@deepseek-ai/dsh-llm-deepseek"]);
    // 真实安装总带受管资产目录；预置它们，回滚快照才只反映本次写入。
    await mkdir(join(runtime, "vendor"), { recursive: true });
    const manifest = JSON.parse(await readFile(join(REPO, "dsh/runtime.package.json"), "utf8"));
    manifest.dependencies.yaml = "2.8.1";
    manifest.dependencies["acp-kernel"] = "0.0.101";
    manifest.dependencies["agent-skills-dsh"] = "file:./bundle/dsh";
    await writeFile(join(runtime, "package.json"), JSON.stringify(manifest, null, 2) + "\n");
    const magicContext = join(box.tmp, "magic-context");
    await cp(join(FIXTURES, "magic-context"), magicContext, { recursive: true });
    await seedProfiles(box.env);
    await mkdir(join(box.env.HOME, ".pi/agent"), { recursive: true });
    await writeFile(join(box.env.HOME, ".pi/agent/models.json"), JSON.stringify({ providers: {} }));
    await writeFile(join(box.env.HOME, ".pi/agent/auth.json"), JSON.stringify({}));
    const args = ["--root", root, "--source", REPO, "--template", TEMPLATE, "--magicContext", magicContext];
    return { ...box, root, runtime, magicContext, args, deploy: () => box.run(args) };
  } catch (error) {
    await rm(box.tmp, { recursive: true, force: true });
    throw error;
  }
}

const failedRun = (result) => result.status !== 0 && `${result.stdout}${result.stderr}`;

// 沙箱计数：只按顶层目录名，用来证明失败路径没留下 mkdtemp 目录。
const sandboxes = async () => (await readdir(tmpdir())).filter((name) => name.startsWith("dsh-deploy-")).length;

// ---- 纯合并：部署每次都要用到的私密值、表达式与模型预算规则 ----
test("merge：私密叶子保留、占位/null 回填、!!js 与模型预算随模板", async () => {
  const { merge } = await import(pathToFileURL(DEPLOY).href);
  const expr = { __jsExpr: "8192" };
  const merged = merge({
    apiKey: "sk-local",
    apiKeyEnv: "<YOUR_KEY>",
    baseURL: null,
    maxTokens: 4096,
    disabled: expr,
    stale: "local-only",
    models: [{ id: "shared", maxTokens: 4096, headers: { Authorization: "secret" } }, { id: "local-only" }],
    packages: ["npm:a"],
  }, {
    apiKey: "template-key",
    apiKeyEnv: "TEMPLATE_KEY",
    baseURL: "https://template.example/v1",
    maxTokens: 200000,
    disabled: true,
    models: [{ id: "shared", maxTokens: 200000, context: 5 }],
    newField: 1,
    packages: ["npm:b"],
  });
  assert.equal(merged.apiKey, "sk-local", "可用的本机敏感值必须保留");
  assert.equal(merged.apiKeyEnv, "TEMPLATE_KEY", "占位符不算已配置，应由模板补齐");
  assert.equal(merged.baseURL, "https://template.example/v1", "null 敏感叶不得挡住模板");
  assert.equal(merged.maxTokens, 200000, "数字 maxTokens 是模型预算，随模板");
  assert.deepEqual(merged.disabled, expr, "!!js 表达式是用户显式值，不能被模板替换");
  assert.equal(merged.stale, "local-only", "模板没有的键保留");
  assert.deepEqual(merged.models.map((m) => m.id), ["shared", "local-only"]);
  assert.equal(merged.models[0].maxTokens, 200000);
  assert.equal(merged.models[0].headers.Authorization, "secret");
  assert.deepEqual(merged.packages, ["npm:a", "npm:b"]);
});

// ---- 部署前置拒绝：不需要官方运行时，且必须零写入 ----
test("deploy：profile 已有独立 node_modules 时拒绝且不建 root", async () => {
  const box = await sandbox();
  try {
    await mkdir(join(box.env.DSH_HOME, "profiles/web/node_modules/left-pad"), { recursive: true });
    const result = box.run(["--root", join(box.tmp, "root"), "--source", REPO, "--template", TEMPLATE, "--magicContext", join(box.tmp, "mc")]);
    assert.match(String(failedRun(result)), /独立依赖目录/);
    assert.equal(existsSync(join(box.tmp, "root")), false, "拒绝发生在建目录之前");
  } finally { await rm(box.tmp, { recursive: true, force: true }); }
});

test("deploy：root/runtime 是符号链接时拒绝且外链目标零改动", async () => {
  const box = await sandbox();
  try {
    const outside = join(box.tmp, "outside");
    await mkdir(outside, { recursive: true });
    await writeFile(join(outside, "keep.txt"), "untouched\n");
    const root = join(box.tmp, "root");
    await mkdir(root, { recursive: true });
    await symlink(outside, join(root, "runtime"));
    const result = box.run(["--root", root, "--source", REPO, "--template", TEMPLATE, "--magicContext", join(box.tmp, "mc")]);
    assert.match(String(failedRun(result)), /符号链接/);
    assert.deepEqual(await readdir(outside), ["keep.txt"], "外链目标不得被写入");
    assert.deepEqual(await readdir(root), ["runtime"], "拒绝后不得留暂存目录");
  } finally { await rm(box.tmp, { recursive: true, force: true }); }
});

test("deploy：Magic Context 源码不完整时失败，不留启动器与暂存目录", async () => {
  const box = await sandbox();
  try {
    const source = join(box.tmp, "mc");
    await mkdir(source, { recursive: true });
    await writeFile(join(source, "index.js"), "export default {};\n");
    const root = join(box.tmp, "root");
    const result = box.run(["--root", root, "--source", REPO, "--template", TEMPLATE, "--magicContext", source]);
    assert.match(String(failedRun(result)), /缺少 Magic Context 源码包/);
    assert.deepEqual(await readdir(root), [], "root 里不得有启动器或半套 runtime");
    assert.equal(existsSync(join(box.env.DSH_HOME, ".credentials.yaml")), false, "失败不得写凭据");
  } finally { await rm(box.tmp, { recursive: true, force: true }); }

  // 建完整部署沙箱时中途失败（断链 runtime）也必须自己清干净。
  const before = await sandboxes();
  await assert.rejects(hostSandbox(join(tmpdir(), "dsh-missing-runtime-does-not-exist")));
  assert.equal(await sandboxes(), before, "创建失败后不得留下 dsh-deploy-* 目录");
});

test("deploy.mjs：缺少 --root 时以非零退出", async () => {
  const box = await sandbox();
  try {
    const result = box.run(["--source", REPO, "--template", TEMPLATE]);
    assert.match(String(failedRun(result)), /缺少 --root/);
  } finally { await rm(box.tmp, { recursive: true, force: true }); }
});

// ---- 需要官方运行时的完整部署 ----
if (HOST !== undefined && !hostReady()) {
  process.stdout.write(`ERROR DSH_TEST_RUNTIME 不是可用的 DSH 运行时（缺 node_modules/@deepseek-ai/dsh/lib/bin.js）：${HOST}\n`);
  failed += 1;
}
// 注入的运行时只是只读参照。这里核对三个关键文件的内容；若是链接，还核对链接文字与目标内容，
// 不扫描整棵依赖树：能发现部署改写共享 node_modules 的情形，但不是「全树未被写穿」的证明。
const HOST_FILES = [
  "node_modules/@deepseek-ai/dsh-llm-deepseek/lib/index.js",
  "node_modules/@deepseek-ai/dsh-llm-deepseek/package.json",
  "node_modules/@deepseek-ai/dsh/lib/bin.js",
];
const hostGuard = async () => {
  const rows = [];
  for (const file of HOST_FILES) {
    const path = join(HOST, file);
    const linked = (await lstat(path)).isSymbolicLink();
    const target = linked ? await realpath(path) : path;
    rows.push(`${file}\t${linked ? await readlink(path) : ""}\t${await snapshot([target])}`);
  }
  return createHash("sha256").update(rows.join("\n")).digest("hex");
};
const hostCase = (name, fn) => {
  if (!hostReady()) return skip(name, "需 DSH_TEST_RUNTIME 指向一次性隔离官方运行时");
  test(name, async () => {
    const guard = await hostGuard();
    let box, failure, written;
    try {
      box = await hostSandbox();
      await fn(box);
    } catch (error) {
      failure = error;
    } finally {
      // 场景失败或清理失败都不能跳过写穿核对。
      if (box) await rm(box.tmp, { recursive: true, force: true }).catch((error) => { failure ??= error; });
      await hostGuard().then((now) => { if (now !== guard) written = new Error("注入运行时的解析器／入口文件被改写"); },
        (error) => { written = new Error(`注入运行时核对失败：${error.message}`); });
    }
    if (failure && written) throw new Error(`${failure.message}；另外：${written.message}`);
    if (failure) throw failure;
    if (written) throw written;
  });
};

hostCase("deploy：三 profile 部署的事务结果与幂等", async (box) => {
  const watched = [join(box.root, "runtime"), join(box.root, "dsh"), join(box.env.DSH_HOME, ".credentials.yaml"), join(box.env.DSH_HOME, "profiles")];
  const legacySnapshot = join("bundle/context-rewrite/context-output", `${"a".repeat(64)}.txt`);
  const hiddenSnapshot = join("bundle/context-rewrite/.context-output", `${"b".repeat(64)}.txt`);
  for (const [relative, text] of [[legacySnapshot, "legacy-snapshot\n"], [hiddenSnapshot, "hidden-snapshot\n"]]) {
    const path = join(box.root, "runtime", relative);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, text, { mode: 0o600 });
  }
  await writeFile(join(box.root, "runtime/bundle/context-rewrite/output-store.mjs"), "legacy\n");
  const first = box.deploy();
  assert.equal(first.status, 0, `部署失败：${first.stderr}`);
  assert.match(first.stdout, /DSH 已配置/);
  const launcher = join(box.root, "dsh");
  assert.equal((await lstat(launcher)).mode & 0o777, 0o755, "启动器必须可执行");
  const credentials = join(box.env.DSH_HOME, ".credentials.yaml");
  assert.equal((await lstat(credentials)).mode & 0o777, 0o600, "凭据必须是 owner-only");
  const written = await readFile(credentials, "utf8");
  for (const [name, value] of Object.entries(KEYS)) assert.match(written, new RegExp(`${name}: ${value}`), `凭据缺 ${name}`);
  const headless = await readFile(join(box.env.DSH_HOME, "profiles/headless/cordis.patch.yml"), "utf8");
  assert.ok(!headless.includes("gemini-newapi"), "旧 Gemini 路由必须已迁移");
  assert.match(headless, /google:/);
  assert.ok(!/\n\s+api: google-generative-ai/.test(headless), "rc.2 的 google 路由不得带显式 api");
  assert.ok(headless.includes("local-legacy-model"), "旧自定义模型必须保留");
  assert.ok(headless.includes("process.env.DEEPSEEK_HOST"), "baseURL 表达式必须原样写盘");
  // 写盘结果必须能被宿主同一方言重新解析，表达式仍是表达式节点。
  const includeFile = createRequire(join(box.root, "runtime/package.json")).resolve("@deepseek-ai/cordis-plugin-include");
  const { entryListSchema } = await import(pathToFileURL(includeFile).href);
  const reloaded = createRequire(includeFile)("js-yaml").load(headless, { schema: entryListSchema });
  const claude = reloaded.find((row) => row.id === "llm-pi-ai").config.providers["claude-newapi"];
  assert.equal(claude.maxTokens.__jsExpr, "8192", "!!js 预算写盘后必须仍是表达式节点");
  assert.equal(claude.models.find((m) => m.id === "local-claude-model").maxTokens.__jsExpr, "4096", "自定义模型的 !!js 必须保留");
  for (const profile of ["headless", "web", "tui"]) {
    const dir = join(box.env.DSH_HOME, "profiles", profile);
    assert.equal(await readlink(join(dir, "node_modules")), join(box.root, "runtime/node_modules"), `${profile} node_modules 应指向受管 runtime`);
    assert.equal(await readFile(join(dir, "cordis.yml"), "utf8"), "[]\n");
    const bundles = JSON.parse(await readFile(join(dir, "package.json"), "utf8")).dsh.profile.bundles;
    for (const name of ["pi2dsh", "agent-skills-dsh", "dsh-plugin-magic-context"]) assert.ok(bundles.includes(name), `${profile} 缺 ${name}`);
  }
  assert.ok(existsSync(join(box.root, "runtime/bundle/dsh/pi/later.ts")), "bundle 资产未提交");
  assert.equal(await readFile(join(box.root, "runtime", legacySnapshot), "utf8"), "legacy-snapshot\n", "受管目录内的旧快照必须保留在原路径");
  assert.equal((await lstat(join(box.root, "runtime", legacySnapshot))).mode & 0o777, 0o600, "旧快照权限必须保留");
  assert.equal(await readFile(join(box.root, "runtime", hiddenSnapshot), "utf8"), "hidden-snapshot\n", "隐藏目录内的旧快照也必须保留");
  assert.equal((await lstat(join(box.root, "runtime", hiddenSnapshot))).mode & 0o777, 0o600, "隐藏快照权限必须保留");
  assert.ok(!existsSync(join(box.root, "runtime/bundle/context-rewrite/output-store.mjs")), "旧 output-store 必须退役");
  assert.ok((await readFile(join(box.root, "runtime", PARSER), "utf8")).includes(PARSER_PATCHED), "解析器补丁未落到自有副本");
  assert.deepEqual((await readdir(box.root)).filter((n) => n.startsWith(".deploy-")), [], "暂存目录必须清理");

  const before = await snapshot(watched);
  const second = box.deploy();
  assert.equal(second.status, 0, `第二次部署失败：${second.stderr}`);
  assert.ok(!second.stdout.includes("依赖已更新"), "未变化却重装了依赖");
  assert.equal(await snapshot(watched), before, "重复部署必须幂等");
});

hostCase("deploy：快照冲突在配置预置前拒绝且零残留", async (box) => {
  const relative = join("context-rewrite/context-output", `${"c".repeat(64)}.txt`);
  const previous = join(box.root, "runtime/bundle", relative);
  await mkdir(dirname(previous), { recursive: true });
  await writeFile(previous, "old-snapshot\n", { mode: 0o600 });
  const source = join(box.tmp, "conflict-source");
  for (const dir of ["dsh", "context-rewrite", "image-gen", "pi"]) {
    await cp(join(REPO, dir), join(source, dir), { recursive: true,
      filter: (path) => !path.split("/").some((part) => ["node_modules", ".git"].includes(part)) });
  }
  const incoming = join(source, relative);
  await mkdir(dirname(incoming), { recursive: true });
  await writeFile(incoming, "different-new-asset\n");
  const watched = [box.root, box.env.DSH_HOME];
  const before = await snapshot(watched);
  const result = box.run(box.args.map((value) => value === REPO ? source : value));
  assert.match(String(failedRun(result)), /历史快照与新资产冲突/);
  assert.equal(await readFile(previous, "utf8"), "old-snapshot\n");
  assert.equal(await snapshot(watched), before, "冲突拒绝不得留下配置备份、临时文件或受管资产变化");
  assert.deepEqual(await residues(box.root, box.env.DSH_HOME), [], "冲突拒绝不得留下事务残留");
});

hostCase("deploy：profile patch 是需改写的符号链接时拒绝且不写穿目标", async (box) => {
  const target = join(box.tmp, "patch-target.yml");
  await writeFile(target, (await readFile(join(FIXTURES, "profile-patch.yml"), "utf8")) + "- id: llm-pi-ai\n  config:\n    providers:\n      claude-newapi:\n        maxTokens: 2048\n");
  const link = join(box.env.DSH_HOME, "profiles/web/cordis.patch.yml");
  await rm(link);
  await symlink(target, link);
  const watched = [join(box.env.DSH_HOME, "profiles/headless"), target];
  const before = await snapshot(watched);
  const result = box.deploy();
  assert.match(String(failedRun(result)), /符号链接/);
  assert.equal(await snapshot(watched), before, "拒绝后不得写入任何配置");
  assert.equal(existsSync(join(box.root, "dsh")), false, "预检失败不得提交启动器");
});

hostCase("deploy：晚期失败整体回滚 runtime 与已预置配置", async (box) => {
  // 先成功部署一次：回滚必须撤销真实的已存在配置写入，而不是在第一次 commit 之前就抛错。
  const first = box.deploy();
  assert.equal(first.status, 0, `首次部署失败：${first.stderr}`);

  // 合法但会产生真实写入的两处修改：headless 追加一条本项目条目，web 换一个凭据引用。
  const headlessPatch = join(box.env.DSH_HOME, "profiles/headless/cordis.patch.yml");
  await writeFile(headlessPatch, (await readFile(headlessPatch, "utf8"))
    + "- id: local-rollback-probe\n  config:\n    marker: rollback\n");
  const webPatch = join(box.env.DSH_HOME, "profiles/web/cordis.patch.yml");
  await writeFile(webPatch, (await readFile(webPatch, "utf8"))
    .replace("apiKeyEnv: CLAUDE_NEWAPI_API_KEY", "apiKeyEnv: ROLLBACK_EXTRA_KEY"));
  box.env.ROLLBACK_EXTRA_KEY = "k-rollback-extra";

  const watched = [box.root, box.env.DSH_HOME];
  const before = await snapshot(watched);

  // 故障注入从当前源码生成：在第一项配置 commit 之后记录 committed 数再抛错，
  // 这样「至少一项已提交、随后被 undoWrite 撤销」有直接证据，而不是只在提交前失败。
  const mutated = join(box.tmp, "deploy-mutated.mjs");
  const marker = join(box.tmp, "committed.txt");
  const source = await readFile(DEPLOY, "utf8");
  const anchor = "        await commitWrite(prepared);\n        committed.push(prepared);";
  assert.equal(source.split(anchor).length, 2, "故障注入锚点缺失：部署提交段已变化");
  await writeFile(mutated, source.replace(anchor,
    "        await commitWrite(prepared);\n        committed.push(prepared);\n" +
    `        await writeFile(${JSON.stringify(marker)}, String(committed.length));\n` +
    "        throw new Error(\"injected late failure\");"));

  const result = spawnSync(process.execPath, [mutated, ...box.args], { env: box.env, cwd: box.tmp, encoding: "utf8", timeout: 120000 });
  assert.match(String(failedRun(result)), /injected late failure/);
  assert.ok(Number(await readFile(marker, "utf8")) >= 1, "故障注入必须发生在至少一项配置提交之后");
  assert.equal(await snapshot(watched), before, "回滚后 root 与 DSH_HOME 整树（含所有备份）必须与部署前一致");
  assert.deepEqual(await residues(box.root, box.env.DSH_HOME), [], "root 与 DSH_HOME 不得留下暂存／备份／换位残留");
});

hostCase("deploy：既有凭据权限过宽时拒绝，不留下宿主启动即失败的配置", async (box) => {
  const deployOnce = box.deploy();
  assert.equal(deployOnce.status, 0, `首次部署失败：${deployOnce.stderr}`);
  const credentials = join(box.env.DSH_HOME, ".credentials.yaml");
  await chmod(credentials, 0o644);
  const watched = [join(box.root, "runtime"), join(box.env.DSH_HOME, "profiles")];
  const before = await snapshot(watched);
  const result = box.deploy();
  assert.match(String(failedRun(result)), /权限过宽/);
  assert.equal((await lstat(credentials)).mode & 0o777, 0o644, "拒绝时不得改写凭据文件");
  assert.equal(await snapshot(watched), before, "拒绝时 runtime／profile 不得改动");
});

hostCase("deploy：解析器入口是包外符号链接时只改自有副本", async (box) => {
  const pkg = join(box.root, "runtime/node_modules/@deepseek-ai/dsh-llm-deepseek");
  const outside = join(box.tmp, "external-parser.js");
  const installed = await readFile(join(pkg, "lib/index.js"), "utf8");
  const clean = installed.includes(PARSER_PATCHED) ? installed.replace(PARSER_PATCHED, PARSER_ORIGINAL) : installed;
  assert.ok(clean.includes(PARSER_ORIGINAL), "运行时里的解析器既非已补丁也非原始形态，无法构造该场景");
  await writeFile(outside, clean);
  await rm(join(pkg, "lib/index.js"));
  await symlink(outside, join(pkg, "lib/index.js"));
  const result = box.deploy();
  assert.equal(result.status, 0, `部署失败：${result.stderr}`);
  assert.ok(!(await readFile(outside, "utf8")).includes(PARSER_PATCHED), "包外解析器副本被写穿");
  const installedAfter = join(box.root, "runtime", PARSER);
  assert.ok((await readFile(installedAfter, "utf8")).includes(PARSER_PATCHED), "自有副本未打补丁");
  assert.equal((await lstat(installedAfter)).isSymbolicLink(), false, "提交后仍是符号链接");
});

for (const [name, fn, reason] of cases) {
  if (reason) { skipped += 1; process.stdout.write(`SKIP ${name}: ${reason}\n`); continue; }
  try {
    await fn();
    process.stdout.write(`PASS ${name}\n`);
  } catch (error) {
    failed += 1;
    process.stdout.write(`FAIL ${name}: ${error?.message ?? error}\n`);
  }
}
const passed = cases.length - skipped - failed;
process.stdout.write(failed ? `FAIL ${failed} 项\n`
  : `PASS dsh-deploy.e2e：${passed} 项${skipped ? `；SKIP HOST ${skipped} 项（需 DSH_TEST_RUNTIME，未验证）` : ""}\n`);
process.exitCode = failed ? 1 : 0;
