#!/usr/bin/env node
// verify.mjs <上游 clone 目录> —— fork 体检：三层改动到底有没有落在树上（构建产物 + 运行期）。
// 任何一项失败就 exit 1 并打出 checklist，所以人和 agent 都能一眼知道该修哪一层。

import { readFileSync, existsSync, readdirSync, statSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";

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

// ── 运行期：真的拉起 MCP 子进程问一遍工具表 ────────────────────────────────
const bundlePath = join(REPO, "server.bundle.mjs");
if (!existsSync(bundlePath)) {
  check("server.bundle.mjs 存在", false, "还没构建？");
} else {
  const child = spawn(process.execPath, [bundlePath], {
    cwd: REPO,
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

// ── 结论 ────────────────────────────────────────────────────────────────────
const bad = checks.filter((c) => !c.ok);
for (const c of checks) console.log(`${c.ok ? "✓" : "✗"} ${c.name}${c.ok || !c.detail ? "" : ` — ${c.detail}`}`);
if (bad.length) {
  console.error(`\n[fork-verify] ${bad.length}/${checks.length} 项不合格。按顺序检查：源码补丁 → fork-patches.mjs → 构建 → 改名 → 重启 Pi。`);
  process.exit(1);
}
console.log(`\n[fork-verify] ${checks.length} 项全过。`);
