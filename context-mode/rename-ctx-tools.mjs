#!/usr/bin/env node
/**
 * rename-ctx-tools.mjs — 给 context-mode 的 11 个工具名加前缀（默认 ctxm_），避免与
 * pi-magic-context 的同名工具撞车（Pi 检测到跨扩展同名工具会拒绝启动）。
 * 注册名与所有引用它的文案（description、路由块、skill 正文）一起改，否则模型会拿到不存在的工具名。
 *
 * 用法: node rename-ctx-tools.mjs <context-mode 包根目录> [前缀]
 * 退出码: 0 成功 / 1 有旧名残留或双重前缀 / 2 出现未登记的新 ctx_* 令牌（需人工确认）
 */
import { readFileSync, writeFileSync, statSync, readdirSync } from "node:fs";
import { join, extname } from "node:path";

const ROOT = process.argv[2];
const PREFIX = process.argv[3] ?? "ctxm_";
if (!ROOT) {
  console.error("usage: rename-ctx-tools.mjs <package-root> [prefix]");
  process.exit(1);
}

const TOOLS = [
  "batch_execute", "execute", "execute_file", "fetch_and_index", "index",
  "insight", "purge", "search", "stats", "doctor", "upgrade",
];

// 只碰会被宿主加载/注入的产物。src/ tests/ configs/ 保持上游原样，方便对照源码。
const SHIP = ["server.bundle.mjs", "cli.bundle.mjs", "start.mjs", "build", "hooks", "skills"];
const TEXT = new Set([".mjs", ".js", ".cjs", ".json", ".md", ".ts", ".txt", ".yaml", ".yml", ""]);

// 非工具标识，不能改（已在上游产物里确认存在）
const NOT_TOOLS = new Set(["ctx_commands", "ctx_fetch", "ctx_search_v2"]);

// 精确白名单 + 词边界：`\b` 保证不会把 ctx_search_v2 当成 ctx_search 改掉
const RE = new RegExp(`\\bctx_(${TOOLS.join("|")})\\b`, "g");
const RE_ANY = /\bctx_[a-z][a-z_]*\b/g;

const files = [];
const walk = (p) => {
  const st = statSync(p);
  if (st.isDirectory()) return readdirSync(p).forEach((f) => walk(join(p, f)));
  if (TEXT.has(extname(p))) files.push(p);
};
SHIP.map((s) => join(ROOT, s)).filter((p) => statSync(p, { throwIfNoEntry: false })).forEach(walk);

const rel = (p) => p.slice(ROOT.length + 1);
let total = 0;
const touched = [];
for (const f of files) {
  const src = readFileSync(f, "utf8");
  const n = (src.match(RE) ?? []).length;
  if (!n) continue;
  writeFileSync(f, src.replace(RE, `${PREFIX}$1`));
  total += n;
  touched.push(`${rel(f)}: ${n}`);
}

// 自检
const bad = [];
const unknown = new Set();
for (const f of files) {
  const s = readFileSync(f, "utf8");
  for (const t of TOOLS) if (new RegExp(`\\bctx_${t}\\b`).test(s)) bad.push(`${rel(f)}: ctx_${t}`);
  if (s.includes(PREFIX + PREFIX)) bad.push(`${rel(f)}: 双重前缀 ${PREFIX}${PREFIX}`);
  for (const m of s.match(RE_ANY) ?? []) if (!NOT_TOOLS.has(m)) unknown.add(m);
}

console.log(`renamed ${total} occurrences in ${touched.length} files -> ${PREFIX}*`);
if (process.env.VERBOSE) console.log(touched.join("\n"));
if (bad.length) {
  console.error("FAIL 旧名残留/前缀异常\n" + bad.join("\n"));
  process.exit(1);
}
if (unknown.size) {
  console.error(`WARN 产物里出现未登记的新 ctx_* 令牌，人工确认后加进 TOOLS 或 NOT_TOOLS：\n  ${[...unknown].join(", ")}`);
  process.exit(2);
}
console.log("self-check OK: 0 residual old names, no double prefix, no unknown ctx_* token");
