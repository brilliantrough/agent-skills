#!/usr/bin/env node
// v2.2.1 的行为与提示补丁；锚点变化时停止，不在新上游上静默猜测。
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const REPO = process.argv[2];
const CHECK = process.argv.includes("--check");
if (!REPO) {
  console.error("用法: node fork-patches.mjs <上游源码目录> [--check]");
  process.exit(2);
}

let wrote = 0, skipped = 0, failed = 0;
function edit(rel, name, fn) {
  const path = join(REPO, rel);
  if (!existsSync(path)) {
    failed++; console.error(`✗ ${name}: 找不到 ${rel}`); return;
  }
  const before = readFileSync(path, "utf8");
  try {
    const result = fn(before);
    if (result === before) { skipped++; console.log(`· ${name}: 已就绪`); return; }
    if (!CHECK) writeFileSync(path, result);
    wrote++; console.log(`✓ ${name}${CHECK ? "（仅检查，未写入）" : ""}`);
  } catch (error) {
    failed++; console.error(`✗ ${name}: ${error.message}`);
  }
}
function once(text, anchor, replacement) {
  if (text.includes(replacement)) return text;
  if (!text.includes(anchor)) throw new Error(`锚点消失：${anchor.slice(0, 100)}`);
  return text.replace(anchor, replacement);
}
function whole(text, value) { return text === value ? text : value; }

// v2 的九个工具是改名白名单；新增工具必须先完成 schema、权限与提示适配。
edit("src/core/contracts/constants.ts", "tool-contract", (s) => {
  const anchor = 'export const TOOL_ORDER = Object.freeze(["ctx_execute","ctx_batch","ctx_index","ctx_search","ctx_resume","ctx_stats","ctx_doctor","ctx_upgrade","ctx_purge"] as const);';
  if (!s.includes(anchor)) throw new Error("TOOL_ORDER 不再是已适配的 v2 九工具列表");
  return s;
});

// 主宿主使用原生输出门控；Pi 子代理没有该原生组合时，保留上游保护。
edit("src/core/hooks/dispatch.ts", "native-output-gates", (s) => once(s,
  '  // step 5: replace, DECISIONS-r9 F1 split. Subagent case B/C (ADR-0016), and the main agent on a row',
  '  // agent-skills: the main host uses context-output snapshots; Pi subagents keep upstream protection.\n' +
  '  if (process.env.MAGIC_CONTEXT_PI_SUBAGENT !== "1") return ALLOW;\n' +
  '  // step 5: replace, DECISIONS-r9 F1 split. Subagent case B/C (ADR-0016), and the main agent on a row'));

// 主宿主只保留用户自己的 deny；WebFetch/Bash/Read 由用户选择原生路径。Pi 子代理保留上游策略。
edit("src/core/policy/decide.ts", "native-tool-passthrough", (s) => once(s,
  '  if (hit !== null) return deny(USER_DENY_REASON_PREFIX + hit);\n\n  if (canonical === WEBFETCH)',
  '  if (hit !== null) return deny(USER_DENY_REASON_PREFIX + hit);\n\n' +
  '  if (process.env.MAGIC_CONTEXT_PI_SUBAGENT !== "1") return ALLOW; // agent-skills: no upstream routing deny.\n\n' +
  '  if (canonical === WEBFETCH)'));

// Bun 关闭 DatabaseSync 时可能保留 WAL；私有临时库发布前必须先把 schema 收进主文件。
edit("src/core/store/db.ts", "atomic-publication-checkpoint", (s) => once(s,
  '      applyMigrations(raw, readUserVersion(raw));\n    } finally {\n      raw.close(); // last connection: SQLite checkpoints and removes the temp -wal/-shm',
  '      applyMigrations(raw, readUserVersion(raw));\n' +
  '      raw.exec("PRAGMA wal_checkpoint(TRUNCATE)"); // Bun does not checkpoint on close before linkSync.\n' +
  '    } finally {\n      raw.close(); // last connection: SQLite checkpoints and removes the temp -wal/-shm'));

// 回填上游 main 的 #1403：显式代理不是目标，但 origin 仍逐跳做 SSRF 检查。
edit("src/core/sandbox/fetch.ts", "proxy-is-not-target", (s) => {
  let out = once(s,
`async function resolveTarget(u: URL, signal: AbortSignal): Promise<Target> {
  const host = bare(u.hostname);
  let addrs: { address: string }[];
  try {
    addrs = await lookup(host, { all: true });
  } catch (err) {
    throw fail(causeCode(err));
  }
  if (signal.aborted) throw fail("ABORT_ERR");
  if (addrs.length === 0) throw fail("ENOTFOUND");
  for (const a of addrs) checkAddress(host, a.address);
  return { host, port: u.port === "" ? defaultPort(u.protocol) : Number(u.port), address: addrs[0].address };
}`,
`async function lookupAll(host: string, signal: AbortSignal): Promise<{ address: string }[]> {
  let addrs: { address: string }[];
  try {
    addrs = await lookup(host, { all: true });
  } catch (err) {
    throw fail(causeCode(err));
  }
  if (signal.aborted) throw fail("ABORT_ERR");
  if (addrs.length === 0) throw fail("ENOTFOUND");
  return addrs;
}

async function resolveTarget(u: URL, signal: AbortSignal, checked: boolean): Promise<Target> {
  const host = bare(u.hostname);
  const addrs = await lookupAll(host, signal);
  if (checked) for (const a of addrs) checkAddress(host, a.address);
  return { host, port: u.port === "" ? defaultPort(u.protocol) : Number(u.port), address: addrs[0].address };
}

// Upstream main D-1403-PROXY-NOT-TARGET-1 (#1403): check the origin, not the user-configured proxy.
async function checkProxiedTarget(u: URL, signal: AbortSignal): Promise<void> {
  const host = bare(u.hostname);
  if (isIP(host) !== 0) return checkAddress(host, host);
  let addrs: { address: string }[];
  try {
    addrs = await lookupAll(host, signal);
  } catch (err) {
    if (signal.aborted) throw err;
    return; // a name only the proxy can resolve is allowed by upstream #1403
  }
  for (const a of addrs) checkAddress(host, a.address);
}`);
  out = once(out,
`    const proxy = pickProxy(current);
    // D-M2-T5-2: through a proxy the proxy resolves the origin name; an IP-literal origin is still checked here.
    const origin = bare(current.hostname);
    if (proxy !== undefined && isIP(origin) !== 0) checkAddress(origin, origin);
    const conn = await resolveTarget(proxy === undefined ? current : proxy.url, signal);`,
`    const proxy = pickProxy(current);
    // Upstream main #1403: the proxy is the socket endpoint; every origin hop is still checked.
    if (proxy !== undefined) await checkProxiedTarget(current, signal);
    const conn = await resolveTarget(proxy === undefined ? current : proxy.url, signal, proxy === undefined);`);
  return out;
});

const INSTRUCTIONS = `context-mode provides on-demand code execution and FTS retrieval; it is not a default wrapper for tool calls.

Call native Glob to find paths and Grep to locate text (Pi: find and grep tools). Read known paths or matched blocks directly. Use the host's Patch/Edit tool for changes or Write to create a file where available. Use native Bash to run programs, tests or one-off calculations, and native Code Mode to coordinate host/MCP tools. Use ctx_execute for noisy command output, ctx_batch for several outputs queried together, and ctx_index/ctx_search for repeated queries. Stop searching once the evidence answers the question.

The host's native output gates own truncation previews, saved output paths and pagination. context-mode does not replace large tool results, deny large Reads, or force WebFetch/Bash through ctxm on main hosts. Use native Read with offset/limit for full output paths; index a path explicitly only for repeated retrieval. Pi subagents retain upstream protection.

ctx_upgrade is disabled in this fork: use the suite's context-mode/setup.sh maintenance path.
`;
const DESCRIPTIONS = {
  "src/prompt/instructions.md": INSTRUCTIONS,
  "src/prompt/tools/ctx_execute.md": `Example: \`ctx_execute({language:"shell",code:"git log --format=%as | sort | uniq -c | sort -nr | head"})\`. Required: language, code.\nRun and filter a noisy command or analyze a local dataset. For file navigation call native Glob or Grep; for source text call Read. Optional \`file\` exposes a project file as CTX_FILE. \`intent\` is a retrieval query and triggers indexing; omit it when code already prints the answer. Output over 16 KiB is indexed. \`timeoutMs\` defaults to and caps at 600000.\n`,
  "src/prompt/tools/ctx_batch.md": `Example: \`ctx_batch({commands:["git log -100 --oneline -- src", "git diff HEAD -- tests"],queries:["Which changes mention retries?", "Which tests cover timeout handling?"]})\`. Required: commands, queries.\nRun several shell commands sequentially, index their combined output, and answer the supplied queries in one call. Use for large outputs and multiple retrieval questions, not for short results consumed directly. There is no concurrency parameter; a failing command stops later commands. Return enough matching evidence for the next action.\n`,
  "src/prompt/tools/ctx_index.md": `Example: \`ctx_index({path:"docs/api.md"})\`. Required: one of path, content, url.\nStore a local file/folder, small inline text, or a URL for repeated ctx_search queries. Prefer path over large inline content. One-off analysis needs no index; already-visible content needs no second copy. URL fetch is plain HTTP with no JS rendering. Returns the source label for scoped searches.\n`,
  "src/prompt/tools/ctx_search.md": `Example: \`ctx_search({queries:["exact error"],source:"source-label"})\`. Required: queries.\nRetrieve missing information from explicitly indexed content or this session's captured journal. Reuse visible evidence first; batch related questions and scope with source when known. No hit is not proof of absence. Indexed snippets are not a substitute for exact source before editing.\n`,
  "src/prompt/tools/ctx_stats.md": `Example: \`ctx_stats({})\`. Read-only.\nShow context-mode byte counters and estimated savings for the reported scope. These are not whole-session provider tokens, cost, model rounds, elapsed time, or proof of a speedup. Check the returned session/project/lifetime scope before attribution.\n`,
  "src/prompt/tools/ctx_upgrade.md": `FORK: do not call（本地 fork，勿调用）. The upstream upgrade replaces this modified package and removes the ctxm_* rename and output-owner patch. Maintain with \`bash context-mode/setup.sh --publish\`; target machines update through the suite setup.\n`,
};
for (const [rel, value] of Object.entries(DESCRIPTIONS)) edit(rel, `prompt:${rel.split("/").at(-1)}`, (s) => whole(s, value));

const summary = `${wrote} 处改写、${skipped} 处已就绪、${failed} 处失败`;
console.log(`[fork-patches] ${summary}`);
if (failed) process.exit(1);
