#!/usr/bin/env node
// 在官方自包含产物上统一改工具前缀，包含权限、journal、schema 与提示中的引用。
import { readFileSync, writeFileSync, statSync, readdirSync } from "node:fs";
import { join, extname } from "node:path";

const ROOT = process.argv[2];
const PREFIX = process.argv[3] ?? "ctxm_";
const TOOLS = ["execute", "batch", "index", "search", "resume", "stats", "doctor", "upgrade", "purge"];
if (!ROOT) {
  console.error("usage: rename-ctx-tools.mjs <release-out> [prefix]");
  process.exit(2);
}
const TEXT = new Set([".mjs", ".js", ".json", ".md", ".txt", ".yaml", ".yml"]);
const files = [];
function walk(path) {
  const stat = statSync(path);
  if (stat.isDirectory()) for (const name of readdirSync(path)) walk(join(path, name));
  else if (TEXT.has(extname(path))) files.push(path);
}
walk(ROOT);

let replacements = 0;
for (const file of files) {
  const before = readFileSync(file, "utf8");
  const after = before.replace(/\bctx_/g, PREFIX);
  if (after === before) continue;
  writeFileSync(file, after);
  replacements += (before.match(/\bctx_/g) ?? []).length;
}

const old = [], missing = [], removed = [];
for (const file of files) {
  const text = readFileSync(file, "utf8");
  if (/\bctx_[a-z_]/.test(text)) old.push(file);
  if (/\bctxm_(execute_file|batch_execute|fetch_and_index)\b/.test(text) && /(?:server\.mjs|pi\/index\.js|opencode\/plugin\.js)$/.test(file)) removed.push(file);
}
for (const entry of ["server.mjs", "pi/index.js", "opencode/plugin.js"]) {
  const text = readFileSync(join(ROOT, entry), "utf8");
  for (const tool of TOOLS) if (!text.includes(`"${PREFIX}${tool}"`)) missing.push(`${entry}:${PREFIX}${tool}`);
}
console.log(`renamed ${replacements} ctx_ tokens in ${files.length} shipped text files -> ${PREFIX}*`);
if (old.length || missing.length || removed.length) {
  for (const file of old) console.error(`旧 ctx_ 前缀残留: ${file}`);
  for (const name of missing) console.error(`工具注册缺失: ${name}`);
  for (const file of removed) console.error(`v1 API 残留: ${file}`);
  process.exit(1);
}
console.log("self-check OK: 9 tools, no old prefix, no removed v1 API");
