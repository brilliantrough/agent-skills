#!/usr/bin/env node
// fork-patches.mjs <上游 clone 目录> [--check] —— 第三层改动：锚定改写。
// 锚点用工具名 / 函数名 / skill 标题，不依赖行号：上游挪行不影响，锚点消失就 exit 1 并点名。
// 每步幂等；--check 只报不改。必须在 `bun run build` 之前跑（改的是 src/ 与 skills/ 源文件）。

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const REPO = process.argv[2];
const CHECK = process.argv.includes("--check");
if (!REPO) {
  console.error("用法: node fork-patches.mjs <上游 clone 目录> [--check]");
  process.exit(2);
}

let wrote = 0, skipped = 0, failed = 0;
const notes = [];

function edit(rel, name, fn) {
  const path = join(REPO, rel);
  if (!existsSync(path)) {
    failed++;
    console.error(`✗ ${name}: 找不到文件 ${rel}`);
    return;
  }
  const before = readFileSync(path, "utf8");
  let r;
  try {
    r = fn(before);
  } catch (e) {
    failed++;
    console.error(`✗ ${name}: ${e.message}`);
    return;
  }
  if (r.status === "fail") {
    failed++;
    console.error(`✗ ${name}: ${r.why}`);
    return;
  }
  if (r.status === "skip") {
    skipped++;
    console.log(`· ${name}: ${r.why}`);
    return;
  }
  if (!CHECK) writeFileSync(path, r.text);
  wrote++;
  console.log(`✓ ${name}: ${r.why}${CHECK ? "（--check：未写入）" : ""}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. 升级口径：上游四条升级口令在本机都是陷阱（照做会得到「上游 + 未改名」或
//    「ctx_* 与 ctxm_* 混杂」的构建，ctx_search 立刻和 magic-context 撞名）
// ─────────────────────────────────────────────────────────────────────────────
const HINT = 'if (name === "Pi") return "bash ~/Linewrite/skills/agent-skills/context-mode/setup.sh";';
const ANCHOR = [
  "parts.push(",
  '        "context-mode active. Choose by next action, not a tool hierarchy. " +',
  '        "Exact source or a complete edit unit → native Read/Grep; short output consumed directly → Bash. " +',
  '        "Large-data aggregation → ctx_execute/ctx_execute_file; multi-command indexed research → ctx_batch_execute. " +',
  '        "Already indexed and still missing information → ctx_search. Return paths, key evidence and values needed to act. " +',
  '        "Omit intent when code already prints the answer; above 5000 output bytes it returns search previews, not the full answer. " +',
  '        "Web → configured MCP tools; ctx_fetch_and_index only for repeated queries. Full guidance: skill context-mode; reuse it once loaded."',
  "      );",
].join("\n");

edit("src/adapters/pi/extension.ts", "upgrade-anchor", (s) => {
  const at = s.indexOf('"context-mode active.');
  if (at < 0) return { status: "fail", why: "找不到 context-mode active 路由提示" };
  const start = s.lastIndexOf("parts.push(", at);
  const m = /\n\s*\);/.exec(s.slice(at));
  if (start < 0 || !m) return { status: "fail", why: "定位不到 parts.push(...) 语句边界" };
  const end = at + m.index + m[0].length;
  if (s.slice(start, end) === ANCHOR) return { status: "skip", why: "已是按任务选择的路由" };
  return { status: "write", text: s.slice(0, start) + ANCHOR + s.slice(end), why: "Pi 路由按下一步所需信息选择" };
});

edit("src/server.ts", "upgrade-hint", (s) => {
  if (s.includes(HINT)) return { status: "skip", why: "已经是我们的版本" };
  const OLD = 'if (name === "Pi") return "npm run build";';
  if (!s.includes(OLD)) {
    return { status: "fail", why: "getUpgradeHint 里找不到上游那行 Pi 升级提示，上游换成别的路径了，需要人工决定（目标是让 Pi 平台指回 setup.sh）" };
  }
  return {
    status: "write",
    text: s.replace(OLD, `// 本机是 fork（纯上游 clone + 锚定改写，见 DEC-CTXMODE-FORK-001）。上游的 "npm run build"\n  // 只重建产物、不会重打改名补丁，照它做会得到 ctx_* 与 ctxm_* 混杂的构建（ctx_search\n  // 立即和 magic-context 撞名），所以这里指回我们的同步脚本。\n  ${HINT}`),
    why: "getUpgradeHint 指回 setup.sh",
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. 工具描述只做索引：深度在 skills/ 里（DEC-TOOLDESC-001）。按工具名定位，
//    上游改描述文案不影响我们；上游新增工具会被下面的未知工具检查揪出来。
// ─────────────────────────────────────────────────────────────────────────────
const DESC = {
  ctx_execute:
    "Run code to derive an answer from large data or noisy command output. ${bunNote} Languages: ${langList}. Print actionable evidence, not raw dumps; omit intent when code already prints the answer. For short output consumed verbatim, use native Bash. Full guidance: skill context-mode.",
  ctx_execute_file:
    "Derive an answer from one workspace file via FILE_CONTENT; print paths, relevant values and evidence. For exact source, complete logic or editing, use native Read. Omit intent when the printed result is already the answer. Outside-workspace paths are refused (#852). Full guidance: skill `context-mode`.",
  ctx_batch_execute:
    "Run commands, index their output and answer `queries` in one call for multi-command research. Short results consumed directly need no index. Default concurrency is 1; parallelize independent I/O, not shared-state or CPU-heavy work. Matches may be incomplete. Full guidance: skill `context-mode`.",
  ctx_index:
    "Store reusable content in the searchable knowledge base. Prefer `path` for local files/directories; `content` is for small inline text. One-shot analysis needs no persistent index, and already-visible output need not be indexed again. Full guidance: skill `ctx-index`.",
  ctx_search:
    "Retrieve missing information from indexed content or captured session memory. Batch related questions and scope with `source` when appropriate. Use existing context first; no match is not proof of absence, and indexed snippets are not current edit source. Full guidance: skill `ctx-search`.",
  ctx_fetch_and_index:
    "Fetch and index pages you will query repeatedly; use configured MCP search/scrape for one-off lookups. Returns previews, not full pages. Plain HTTP, no JS rendering. Cache: 24h; bypass with `ttl: 0` or `force`. Full guidance: skill `context-mode`.",
  ctx_stats:
    "Show context-consumption counters and estimated savings. Read-only. Check reported session/project/lifetime scope before attribution; byte savings do not measure task duration, model rounds or speedup. Full guidance: skill `ctx-stats`.",
  ctx_doctor:
    "Diagnose the context-mode installation server-side and return a plain-text [OK]/[FAIL]/[WARN] report. Full guidance: skill `ctx-doctor`.",
  ctx_upgrade:
    "FORK: do not call（本地 fork，勿调用）. This install renames its tools to ctxm_* in a post-build step so they cannot collide with pi-magic-context; the upstream upgrade reinstalls upstream and wipes that rename. Upgrade path here: `bash ~/Linewrite/skills/agent-skills/context-mode/setup.sh`. Full guidance: skill `context-mode`.",
  ctx_purge:
    "DESTRUCTIVE: permanently delete indexed content, cannot be undone. Requires `confirm: true` and exactly one scope — a `sessionId`, or scope project. It is not a way to free memory or improve performance; if the user says reset/clear/wipe without naming a scope, ask which one first. Full guidance: skill `ctx-purge`.",
  ctx_insight:
    "Open the hosted context-mode Insight dashboard in the default browser — a dashboard launcher, not a Q&A engine. Full guidance: skill `ctx-insight`.",
};

edit("src/server.ts", "brief-descriptions", (s) => {
  // 未知工具检查（上游新增工具时在这里 + 上面 DESC 里各补一条）
  const declared = [...s.matchAll(/^  "(ctx_[a-z_]+)",$/gm)].map((m) => m[1]);
  for (const t of declared) {
    if (!(t in DESC)) notes.push(`未登记的新工具 ${t}：请在 fork-patches.mjs 的 DESC 里补一句简短描述（深度写进 skill）`);
  }
  const L = s.split("\n");
  let out = L.slice();
  const report = [];
  for (const [tool, text] of Object.entries(DESC)) {
    const start = out.findIndex((l) => l.trim() === `"${tool}",`);
    if (start < 0) return { status: "fail", why: `src/server.ts 里找不到 "${tool}", 的注册块（上游把工具名改了？）` };
    let d = -1;
    for (let i = start; i < start + 60; i++) if (/^\s*description:/.test(out[i])) { d = i; break; }
    if (d < 0) return { status: "fail", why: `${tool}: 注册块里找不到 description:` };
    let e = -1;
    for (let i = d + 1; i < d + 90; i++) if (/^\s*inputSchema:/.test(out[i])) { e = i; break; }
    if (e < 0) return { status: "fail", why: `${tool}: description 之后找不到 inputSchema:` };
    const old = out.slice(d, e).join("\n");
    const value = tool === "ctx_execute" ? "`" + text + "`" : '"' + text + '"';
    const norm = (x) => x.replace(/\s+/g, " ").trim();
    const cur = norm(old.replace(/^\s*description:\s*/, "")).replace(/,$/, "");
    if (cur === norm(value)) {
      report.push([tool, old.length, text.length, true]);
      continue;
    }
    const indent = out[d].match(/^\s*/)[0];
    out.splice(d, e - d, `${indent}description:`, `${indent}  ${value},`);
    report.push([tool, old.length, text.length, false]);
  }
  const already = report.every((r) => r[3]);
  if (already) return { status: "skip", why: `11 个描述都已是简短版（合计 ${report.reduce((a, r) => a + r[2], 0)}B）` };
  const changedBytes = report.filter((r) => !r[3]).reduce((a, r) => a + r[1] - r[2], 0);
  if (CHECK) return { status: "write", text: out.join("\n"), why: `压缩 ${report.filter((r) => !r[3]).length} 个描述，省 ~${changedBytes}B` };
  return { status: "write", text: out.join("\n"), why: `压缩 ${report.filter((r) => !r[3]).length} 个描述（~${report.reduce((a, r) => a + r[1], 0)}B → ${report.reduce((a, r) => a + r[2], 0)}B）` };
});

// 3. 主 skill 与两宿主的提示词；不改变 hook 决策或工具执行逻辑。
const guidance = readFileSync(new URL("./guidance.md", import.meta.url), "utf8");
edit("skills/context-mode/SKILL.md", "skill-guidance", (s) => {
  s = s.replaceAll(process.env.CONTEXT_MODE_PREFIX ?? "ctxm_", "ctx_");
  if (!/^name: context-mode$/m.test(s)) return { status: "fail", why: "主 skill 的 name 锚点消失" };
  if (s === guidance) return { status: "skip", why: "主 skill 已同步" };
  return { status: "write", text: guidance, why: "主 skill 按信息需求选择，保留工具边界与按需参考" };
});

edit("src/server.ts", "parameter-guidance", (s) => {
  let count = 0;
  let out = s.replace(/(intent: z\s*\.string\(\)\s*\.optional\(\)\s*\.describe\()[\s\S]*?(\n\s*\))/g, (_m, start, end) => {
    count++;
    return start + "\n          " + JSON.stringify("Optional retrieval query, not a task note. If nonempty and program output exceeds 5000 bytes, returns indexed titles/previews, not the full answer. Usually omit when code already prints the needed result. Use literal output terms; no match is not proof of absence.") + end;
  });
  if (count !== 2) return { status: "fail", why: `intent 参数应有 2 处，找到 ${count}` };
  const batchAt = out.indexOf('  "ctx_batch_execute",');
  const schemaEnd = out.indexOf("      timeout:", batchAt);
  if (batchAt < 0 || schemaEnd < 0) return { status: "fail", why: "找不到 batch queries 描述边界" };
  const before = out.slice(batchAt, schemaEnd);
  const after = before.replace(/(queries: z\.preprocess\(coerceJsonArray, z[\s\S]*?\.min\(1\))[\s\S]*$/, (_m, start) => start + ")\n        .describe(" + JSON.stringify("Questions needed for the next decision, using terms present in command output. Batch independent questions; no fixed query count. Returns top matching sections, not guaranteed complete coverage. If insufficient, refine retrieval or read exact source before editing.") + "),\n");
  if (after === before && !before.includes("no fixed query count")) return { status: "fail", why: "找不到 batch queries 描述" };
  out = out.slice(0, batchAt) + after + out.slice(schemaEnd);
  out = out.replace("Optional working directory for shell commands. Non-shell languages still execute from their sandbox temp directory.", "Working directory for execution (all languages); defaults to the project root.");
  return out === s ? { status: "skip", why: "参数引导已同步" } : { status: "write", text: out, why: "澄清 intent、queries 与 cwd，不改 schema 行为" };
});

edit("hooks/routing-block.mjs", "shared-routing-guidance", (s) => {
  s = s.replaceAll(process.env.CONTEXT_MODE_PREFIX ?? "ctxm_", "ctx_");
  const start = s.indexOf("  <priority_instructions>");
  const end = s.indexOf("  <session_continuity>", start);
  if (start < 0 || end < 0) return { status: "fail", why: "共享路由块的标签锚点消失" };
  // 保留 deferred-tool bootstrap 的条件与工具名插值。
  const bootstrapStart = s.indexOf("${toolSearchBootstrap ?", start);
  const bootstrapEnd = s.indexOf("  <tool_selection", bootstrapStart);
  const bootstrap = bootstrapStart >= 0 && bootstrapEnd >= 0 ? s.slice(bootstrapStart, bootstrapEnd) : "";
  const routing = `  <priority_instructions>
    Choose by the information needed for the next action, not a fixed tool hierarchy. Reduce irrelevant bytes AND avoidable round trips without losing evidence or quality.
  </priority_instructions>
` + bootstrap + `  <tool_selection>
    - Exact source, complete logic/edit unit, or bounded output consumed directly: native Read/Grep/Bash. Keep the current unit available; do not summarize it first and guess edits.
    - Large-data aggregation: \${t("ctx_execute")} or \${t("ctx_execute_file")}. Print paths/IDs, key evidence, conditions and values needed to act, not just counts.
    - Multi-command indexed research: \${t("ctx_batch_execute")}(commands, queries). Group independent questions; parallelize only independent work with isolated state and sufficient resources.
    - Already indexed information still needed: \${t("ctx_search")}(queries, source). Use existing context first; resume does not require reloading every rule or plan.
    - Web: configured MCP search/scrape tools. \${t("ctx_fetch_and_index")} only when the page will be queried repeatedly.
  </tool_selection>
  <retrieval_contract>
    intent is an optional search query, not a task note. Above 5000 output bytes it yields titles/previews; omit it when code already prints the answer. No match is not proof of absence. If evidence is missing, refine extraction or read the exact unit instead of repeatedly searching vague terms.
  </retrieval_contract>
  <file_writing_policy>
    Use native Edit/Write for project changes. Subprocess execution is not a disposable host filesystem: writes outside its temporary script directory may persist. Read current exact source before editing; after a match failure, refresh the affected unit rather than guessing another patch.
  </file_writing_policy>
`;
  let out = s.slice(0, start) + routing + s.slice(end);
  out = out.replace('→ Call upgrade MCP tool, run returned shell command, display as checklist.', '→ This is a fork: do not call the upstream upgrade tool. Use the suite setup/update workflow.');
  out = out.replace('→ Call purge MCP tool with confirm: true. Warn: irreversible.', '→ Confirm the exact session/project scope and irreversible deletion with the user first; only then call purge with confirm: true.');
  out = out.replace('→ Call stats MCP tool, display full output verbatim.', '→ Call stats and preserve its scope labels. Byte savings are not task elapsed time or a speedup measurement.');
  const tips = {
    createReadGuidance: 'Need exact source or a complete logic/edit unit? Native Read is correct. Use ctx_execute_file only to derive an answer from bulk data; print evidence needed for the next step. Do not guess edits from previews.',
    createBashGuidance: 'Short output consumed directly or authorized state changes: native Bash. Large-data aggregation: ctx_execute; multi-command indexed research: ctx_batch_execute. Batch independent work without sharing mutable state; return enough evidence to act.',
    createExternalMcpGuidance: 'Use already returned MCP content directly. For large output, prefer tool-side filtering, file output or host orchestration; re-indexing content already in context cannot undo its cost. Index only for repeated queries, not every lookup.',
  };
  for (const [name, tip] of Object.entries(tips)) {
    const re = new RegExp(`(export function ${name}\\(t\\) \\{)\\n[\\s\\S]*?\\n\\}`);
    if (!re.test(out)) return { status: "fail", why: `找不到 ${name} 函数锚点` };
    out = out.replace(re, (_m, head) => `${head}\n  return ${JSON.stringify("<context_guidance>" + tip + "</context_guidance>").replace(/ctx_[a-z_]+/g, (name) => `" + t(${JSON.stringify(name)}) + "`)};\n}`);
  }
  return out === s ? { status: "skip", why: "共享路由引导已同步" } : { status: "write", text: out, why: "共享路由与读取提示按信息需求选择" };
});

const summary = `${wrote} 处改写、${skipped} 处已就绪、${failed} 处失败`;
for (const n of notes) console.warn(`⚠ ${n}`);
if (failed) {
  console.error(`[fork-patches] ${summary}`);
  console.error("[fork-patches] 锚点没了 = 上游改了对应实现，需要人工核对后用同一种锚定方式重新表达（不要退回 diff 补丁）");
  process.exit(1);
}
console.log(`[fork-patches] ${summary}`);
if (notes.length) process.exit(2);
