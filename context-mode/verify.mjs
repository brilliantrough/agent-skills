#!/usr/bin/env node
// verify.mjs <上游 clone 目录> —— fork 体检：三层改动 + 发布包是否都落在树上（静态 + 运行期）。
// 任一项失败 exit 1 并打出 checklist。本仓库根由脚本自身位置推出（本文件在 <repo>/context-mode/）。

import { readFileSync, existsSync, readdirSync, statSync, mkdtempSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { spawn, execFileSync } from "node:child_process";

const REPO = process.argv[2];
if (!REPO) {
  console.error("用法: node verify.mjs <上游 clone 目录>");
  process.exit(2);
}

const TOOLS = [
  "batch_execute", "execute", "execute_file", "fetch_and_index", "index",
  "insight", "purge", "search", "stats", "doctor", "upgrade",
];
const PREFIX = process.env.CONTEXT_MODE_PREFIX ?? "ctxm_";
const SELF_REPO = resolve(dirname(fileURLToPath(import.meta.url)), ".."); // 本仓库根
const checks = [];
const read = (p) => readFileSync(join(REPO, p), "utf8");
const check = (name, ok, detail = "") => checks.push({ name, ok, detail });

// ── 静态：源码层 ────────────────────────────────────────────────────────────
check("patch 0001（ctx_stats 计数）已落地", read("src/server.ts").includes("statsIncludingCurrentCall"), "src/server.ts 里找不到 statsIncludingCurrentCall");

const ext = read("build/adapters/pi/extension.js");
const bundle = read("server.bundle.mjs");
// 只看锚点附近那一段（我自己的注释里也会提旧文案，不能整文件匹配）
const at = ext.indexOf("context-mode active.");
const anchor = at < 0 ? "" : ext.slice(at, at + 800);
check("注入锚点已去掉 Upgrade 子句", anchor !== "" && !/Upgrade/.test(anchor), anchor === "" ? "扩展产物里找不到锚点" : `锚点里还有 Upgrade：${anchor.slice(-90)}`);
check("注入锚点用的是改名后的工具名", anchor.includes(`${PREFIX}batch_execute`) && anchor.includes("Read files / bulk processing"));
check("getUpgradeHint 指回 setup.sh", bundle.includes("context-mode/setup.sh"), "Pi 平台的升级提示还不是我们的脚本（旧版会返回 npm run build，那只重建不重改名）");

// ── 静态：产物层（改名） ────────────────────────────────────────────────────
const shipped = ["server.bundle.mjs", "cli.bundle.mjs", "start.mjs", "build", "hooks", "skills"];
const oldName = new RegExp(`\\bctx_(${TOOLS.join("|")})\\b`);
const ALLOW = new Set(["ctx_commands", "ctx_fetch", "ctx_search_v2"]); // 非工具标识（名字里带 ctx_ 但不是工具名）
let leftovers = 0;
const unknown = new Set();
const scanOne = (rel) => {
  const body = readFileSync(join(REPO, rel), "utf8");
  leftovers += (body.match(oldName) ?? []).length;
  for (const m of body.match(/\bctx_[a-z][a-z_]*\b/g) ?? []) if (!ALLOW.has(m)) unknown.add(m);
};
const walk = (p) => {
  const full = join(REPO, p);
  if (!existsSync(full)) return;
  if (!statSync(full).isDirectory()) {
    if (/\.(mjs|js|cjs|json|md|ts|txt|ya?ml)$/.test(p)) scanOne(p);
    return;
  }
  for (const e of readdirSync(full, { withFileTypes: true })) walk(`${p}/${e.name}`);
};
for (const s of shipped) walk(s);
check("产物里没有旧工具名", leftovers === 0, `还有 ${leftovers} 处 ctx_* 旧名（改名层没跑？）`);
check("没有未登记的新工具令牌", unknown.size === 0, `未处理：${[...unknown].join(" ")}（上游加了工具？去 fork-patches.mjs 的 DESC 和 rename-ctx-tools.mjs 的 TOOLS 各补一条，然后重启）`);

// ── 静态：skill 层 ──────────────────────────────────────────────────────────
const skills = existsSync(join(REPO, "skills"))
  ? readdirSync(join(REPO, "skills"), { withFileTypes: true }).filter((e) => e.isDirectory() && !e.name.startsWith(".")).map((e) => e.name)
  : [];
check("skills/ctx-upgrade 已剪掉", !skills.includes("ctx-upgrade"), "它会让模型去跑会抹掉改名的升级");
check("skill 数量为 7", skills.length === 7, `现在是 ${skills.length} 个：${skills.join(" ")}`);
const main = existsSync(join(REPO, "skills/context-mode/SKILL.md")) ? read("skills/context-mode/SKILL.md") : "";
check("主 skill 有 When NOT to Use 表", main.includes("## When NOT to Use"));
check(`主 skill 教了 ${PREFIX}batch_execute`, main.includes(`${PREFIX}batch_execute`), "它是注入锚点的第一优先级工具");

// ── 静态：发布包层（产物走 release：目标机装的就是这两个 tar 包，不是 clone） ──
const DIST = join(SELF_REPO, "context-mode", "dist");
const TARBALL = join(DIST, "pi-context-mode-vendor.tar.gz");
const OC_TARBALL = join(DIST, "opencode-context-mode-vendor.tar.gz");
check("发布包存在（pi + opencode 两个资产）", existsSync(TARBALL) && existsSync(OC_TARBALL), "还没打包？跑 bash context-mode/setup.sh");
try {
  execFileSync(process.execPath, [join(SELF_REPO, "context-mode/release.mjs"), REPO, "--check"], { stdio: "pipe" });
  check("发布包与本次构建一致（没过期）", true);
} catch (e) {
  const out = String(e.stdout ?? e.message ?? e).split("\n").filter(Boolean).slice(0, 4).join(" / ");
  check("发布包与本次构建一致（没过期）", false, out);
}

// 把 tar 包解到临时目录：验包内布局（这是目标机拿到的东西）
const unpacked = mkdtempSync(join(tmpdir(), "cm-release-"));
let unpackOk = false;
try {
  execFileSync("tar", ["-xzf", TARBALL, "-C", unpacked], { stdio: "pipe" });
  unpackOk = true;
} catch (e) {
  check("发布包能解开", false, String(e.message ?? e));
}
if (unpackOk) {
  let inner = null;
  try {
    inner = JSON.parse(readFileSync(join(unpacked, "package.json"), "utf8"));
  } catch {
    inner = null;
  }
  check(
    "包内 package.json 声明了 Pi 入口与 skills（Pi 靠它加载）",
    !!inner?.pi?.extensions?.length && !!inner?.pi?.skills?.length && existsSync(join(unpacked, inner.pi.extensions[0])),
    "入口路径不存在或没写 pi 字段",
  );
  const innerSkills = existsSync(join(unpacked, "skills"))
    ? readdirSync(join(unpacked, "skills"), { withFileTypes: true }).filter((e) => e.isDirectory() && !e.name.startsWith(".")).length
    : 0;
  check("包内有 7 个 skill", innerSkills === 7, `现在 ${innerSkills} 个`);
  check("包内有 LICENSE（Elastic-2.0 必须随产物分发）", existsSync(join(unpacked, "LICENSE")));
}

// ── 运行期：拉起包内那份 server.bundle.mjs（即 Pi 会在目标机上 spawn 的东西） ──
const bundlePath = join(unpacked, "server.bundle.mjs");
if (!unpackOk || !existsSync(bundlePath)) {
  check("包内 server.bundle.mjs 存在", false, "tar 包不完整？");
} else {
  const child = spawn(process.execPath, [bundlePath], {
    cwd: unpacked,
    env: { ...process.env, CONTEXT_MODE_DIR: mkdtempSync(join(tmpdir(), "cm-verify-")) },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let buf = "";
  const waiters = new Map();
  child.stdout.on("data", (d) => {
    buf += d;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      try {
        const msg = JSON.parse(line);
        if (msg.id != null && waiters.has(msg.id)) { waiters.get(msg.id)(msg); waiters.delete(msg.id); }
      } catch { /* 非 JSON 行忽略 */ }
    }
  });
  const rpc = (id, method, params) => new Promise((res, rej) => {
    waiters.set(id, res);
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    setTimeout(() => { if (waiters.delete(id)) rej(new Error(`${method} 超时`)); }, 20000);
  });
  try {
    await rpc(1, "initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "verify-fork", version: "1.0.0" } });
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);
    const res = await rpc(2, "tools/list", {});
    const tools = res.result?.tools ?? [];
    const names = tools.map((t) => t.name);
    const bytes = tools.reduce((a, t) => a + (t.description?.length ?? 0), 0);
    const want = TOOLS.map((t) => PREFIX + t).sort();
    check(`工具表 11 个 ${PREFIX}* 工具`, JSON.stringify([...names].sort()) === JSON.stringify(want), `实际：${names.join(" ")}`);
    check("描述合计 < 6KB（描述只做索引）", bytes > 0 && bytes < 6000, `实际 ${bytes}B`);
    const noPointer = tools.filter((t) => !/Full guidance: skill/.test(t.description ?? "")).map((t) => t.name);
    check("每个描述都指向 skill", noPointer.length === 0, `缺指针：${noPointer.join(" ")}`);
    check("upgrade 工具标了 FORK", /FORK: do not call/.test(tools.find((t) => t.name === `${PREFIX}upgrade`)?.description ?? ""));
  } catch (e) {
    check("MCP 子进程 tools/list", false, String(e.message ?? e));
  } finally {
    child.kill();
  }
}

// ── 运行期：OpenCode 包（解开 tar，在 bun 下加载插件并看它注册了什么工具） ──────
const ocUnpacked = mkdtempSync(join(tmpdir(), "cm-oc-"));
let ocOk = false;
try {
  execFileSync("tar", ["-xzf", OC_TARBALL, "-C", ocUnpacked], { stdio: "pipe" });
  ocOk = true;
} catch (e) {
  check("OpenCode 包能解开", false, String(e.message ?? e));
}
if (ocOk) {
  const ocSkills = existsSync(join(ocUnpacked, "skills"))
    ? readdirSync(join(ocUnpacked, "skills"), { withFileTypes: true }).filter((e) => e.isDirectory() && !e.name.startsWith(".")).length
    : 0;
  check("OpenCode 包内有 7 个 skill", ocSkills === 7, `现在 ${ocSkills} 个`);
  check("OpenCode 包内有 LICENSE", existsSync(join(ocUnpacked, "LICENSE")));
  check("OpenCode 包内有入口 shim（plugins/ 那一层靠它加载）", existsSync(join(ocUnpacked, "entry.js")));
  const ocHooks = [
    "hooks/core/routing.mjs", "hooks/core/tool-naming.mjs", "hooks/core/mcp-ready.mjs",
    "hooks/routing-block.mjs", "hooks/auto-injection.mjs", "hooks/security.bundle.mjs",
  ];
  const missHooks = ocHooks.filter((h) => !existsSync(join(ocUnpacked, h)));
  check("OpenCode 包的 hooks 闭包齐全（6 个）", missHooks.length === 0, `缺：${missHooks.join(" ")}`);
  // 真加载一次：这是目标机（OpenCode 跑在 Bun 上）会做的事
  const probe = [
    `const m = await import(${JSON.stringify(join(ocUnpacked, "build/adapters/opencode/plugin.js"))});`,
    `const hooks = await m.ContextModePlugin({ directory: ${JSON.stringify(ocUnpacked)}, client: { app: { log: async () => {} } } });`,
    `console.log(JSON.stringify({ hooks: Object.keys(hooks).sort(), tools: Object.keys(hooks.tool ?? {}).sort() }));`,
  ].join("\n");
  try {
    const out = execFileSync("bun", ["-e", probe], { cwd: ocUnpacked, stdio: ["pipe", "pipe", "pipe"], timeout: 120000 }).toString();
    const info = JSON.parse(out.trim().split("\n").pop());
    const want = TOOLS.map((t) => PREFIX + t).sort();
    check(`OpenCode 插件注册 11 个 ${PREFIX}* 工具`, JSON.stringify(info.tools) === JSON.stringify(want), `实际：${info.tools.join(" ")}`);
    check("OpenCode 插件返回了路由 hook", ["tool", "tool.execute.before", "chat.message"].every((k) => info.hooks.includes(k)), `实际：${info.hooks.join(" ")}`);
  } catch (e) {
    const tail = String(e.stdout ?? "").trim().split("\n").slice(-3).join(" / ") || String(e.message ?? e);
    check("OpenCode 插件能在 bun 下加载", false, tail);
  }
}

// ── 结论 ────────────────────────────────────────────────────────────────────
const bad = checks.filter((c) => !c.ok);
for (const c of checks) console.log(`${c.ok ? "✓" : "✗"} ${c.name}${c.ok || !c.detail ? "" : ` — ${c.detail}`}`);
if (bad.length) {
  console.error(`\n[fork-verify] ${bad.length}/${checks.length} 项不合格。按顺序检查：源码补丁 → fork-patches.mjs → 构建 → 改名 → 打包 → 重启 Pi。`);
  process.exit(1);
}
console.log(`\n[fork-verify] ${checks.length} 项全过。`);
