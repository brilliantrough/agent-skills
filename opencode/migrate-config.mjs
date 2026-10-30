#!/usr/bin/env bun
// deprecated: config-v2-native；用户确认迁移期结束后删除迁移入口。
// bun migrate-config.mjs [--apply] opencode.json [opencode.jsonc]；默认预览，不启动宿主。
import { normalize } from "@opencode/core/config/normalize";
import { parse } from "jsonc-parser/lib/esm/main.js";
import { copyFileSync, chmodSync, existsSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";

const retired = new Set([
  "command", "reference", "snapshot", "plugin", "autoshare", "autoupdate",
  "disabled_providers", "enabled_providers", "small_model", "mode", "agent",
  "provider", "permission", "tools", "attachment", "logLevel", "server", "subagent_depth", "layout",
]);

export function convert(input) {
  const result = normalize(input);
  const blocked = result.diagnostics.filter(d => d.kind === "invalid" || d.kind === "conflict");
  if (result.type !== "normalized" || blocked.length) {
    throw new Error(`配置冲突或无效，保留原文件：${blocked.map(d => d.path.join(".")).join(", ")}`);
  }
  // 保留不属于宿主 schema 的顶层扩展字段；不展开 {env:…} / {file:…}。
  const config = { ...input, ...result.encoded };
  for (const key of retired) delete config[key];
  return { config, diagnostics: result.diagnostics };
}

function load(path) {
  const text = readFileSync(path, "utf8");
  const errors = [];
  const config = parse(text, errors, { allowTrailingComma: true });
  if (errors.length) throw new Error(`${path}: JSONC 解析失败，保留原文件`);
  return { text, config };
}

function main(args) {
  const apply = args.includes("--apply");
  const paths = args.filter(a => a !== "--apply");
  if (!paths.length || paths.some(p => p.startsWith("--"))) {
    throw new Error("用法: migrate-config.mjs [--apply] opencode.json [opencode.jsonc]");
  }
  const pending = [];
  for (const path of [...new Set(paths.filter(p => existsSync(p)).map(p => realpathSync(p)))]) {
    const before = load(path);
    const { config, diagnostics } = convert(before.config);
    for (const d of diagnostics) console.error(`config: ${path}: ${d.path.join(".")}: ${d.kind} (${d.message})`);
    if (isDeepStrictEqual(before.config, config)) continue;
    pending.push({ path, before: before.text, config });
  }
  for (const { path, before, config } of pending) {
    console.log(`migrate: ${path} → V2 原生配置${apply ? "" : "（预览，未写入）"}`);
    if (!apply) continue;
    if (readFileSync(path, "utf8") !== before) throw new Error(`${path}: 文件已被修改，请重跑`);
    const staging = mkdtempSync(join(dirname(path), ".opencode-config-"));
    const backup = `${path}.bak-v2-${Date.now()}`;
    try {
      copyFileSync(path, backup);
      chmodSync(backup, 0o600);
      const temp = join(staging, "config.json");
      writeFileSync(temp, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
      renameSync(temp, path);
    } finally {
      rmSync(staging, { recursive: true, force: true });
    }
    console.log(`backup: ${backup}`);
  }
  if (!pending.length) console.log("unchanged: 已是 V2 原生配置");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(`ERROR: ${error.message}`); process.exitCode = 1; }
}
