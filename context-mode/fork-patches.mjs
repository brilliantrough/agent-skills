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
  "      // Fork 口径（2026-09-19）：本机是 ~/Linewrite/forks/context-mode（纯上游 clone + 锚定改写）。",
  "      // 锚点原本还写着 \"Upgrade → ctx_upgrade\"，而升级会把上游装回来、抹掉改名补丁，",
  "      // 导致与 pi-magic-context 的 ctx_search 重新撞名——所以这里不再提升级；",
  "      // 并且 \"Read/edit files →\" 改掉：ctx_execute_file 只能读（它把文件读进 FILE_CONTENT），不能编辑。",
  "      parts.push(",
  '        "context-mode active. Hierarchy: ctx_batch_execute > ctx_execute > ctx_execute_file > ctx_search. " +',
  '        "Read files / bulk processing → ctx_execute_file. Multi-command research → ctx_batch_execute. " +',
  '        "Web pages → ctx_fetch_and_index then ctx_search. Index docs → ctx_index. " +',
  '        "Stats → ctx_stats. Doctor → ctx_doctor. Purge → ctx_purge (destructive, needs confirm:true). " +',
  '        "Native Read stays right when you will edit that file or need exact bytes; Bash stays right for short fixed output and state mutations."',
  "      );",
].join("\n");

edit("src/adapters/pi/extension.ts", "upgrade-anchor", (s) => {
  const NEEDLE = '"context-mode active. Hierarchy:';
  if (s.includes("Native Read stays right when you will edit")) return { status: "skip", why: "锚点已是我们的版本" };
  const at = s.indexOf(NEEDLE);
  if (at < 0) {
    return { status: "fail", why: `扩展里找不到 ${NEEDLE} 这段路由提示，上游可能改了注入逻辑，需要人工看一眼 src/adapters/pi/extension.ts` };
  }
  const start = s.lastIndexOf("parts.push(", at);
  const m = /\n\s*\);/.exec(s.slice(at));
  if (start < 0 || !m) return { status: "fail", why: "找到了锚点文本，但定位不到 parts.push(...) 语句边界" };
  const end = at + m.index + m[0].length;
  return { status: "write", text: s.slice(0, start) + ANCHOR + s.slice(end), why: "升级锚点去掉（不再把模型引去跑会抹掉改名的升级）" };
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
    "Run code in a sandboxed subprocess ${bunNote} Languages: ${langList}. Only what you console.log() enters context; the raw bytes never do. Reach for it to derive an answer FROM data (filter/count/aggregate/parse) rather than reading the bytes, and to keep long-running processes alive (background:true). Full guidance: skill context-mode.",
  ctx_execute_file:
    "Read one file into a sandboxed FILE_CONTENT variable and print only the derived answer — the file bytes never enter context. The path must be inside the workspace (outside paths are refused by design, issue #852). Use it to KNOW something about a file without seeing all of it. Full guidance: skill `context-mode`.",
  ctx_batch_execute:
    "Run several commands in ONE call. Every command's output is auto-indexed into the knowledge base; pass `queries` and the matching sections come back in the same round trip (gather + answer together). `concurrency` parallelizes the fetch phase — keep it at 1 for CPU-bound or stateful commands. Full guidance: skill `context-mode`.",
  ctx_index:
    "Store content — inline text, or a file/directory via `path` — in the persistent FTS5 knowledge base: split by headings, code blocks kept intact, raw chunks persisted for later retrieval. Retrieve with ctx_search. Full guidance: skill `ctx-index`.",
  ctx_search:
    "Search the unified knowledge base (content you indexed + auto-captured session memory) with a multi-strategy pipeline: Porter-stemming matcher and trigram-substring matcher fused by RRF, Levenshtein typo correction, proximity rerank, window-extracted snippets. Returns section titles and previews, never full bytes — drill in with more queries. Full guidance: skill `ctx-search`.",
  ctx_fetch_and_index:
    "Fetch a URL, convert HTML to markdown (JSON chunked by key paths), index it, and return only a small preview window per source — the page bytes never enter context. Cached on disk (24h TTL; override with `ttl`, bypass with `ttl: 0` or `force`). Plain HTTP fetch, no headless browser. Full guidance: skill `context-mode`.",
  ctx_stats:
    "Return this session's context-consumption statistics: total bytes returned, per-tool breakdown, call counts, estimated token usage, context-savings ratio. Read-only. Full guidance: skill `ctx-stats`.",
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

// ─────────────────────────────────────────────────────────────────────────────
// 3. skill 补充：主 skill 原本完全没提 batch_execute（而注入锚点把它列为第一优先级），
//    外加一张从描述里采下来的「什么时候不要用」表 —— 描述压短的前提是深度已经在这
// ─────────────────────────────────────────────────────────────────────────────
const SKILL = "skills/context-mode/SKILL.md";
const MANDATE = `

**Several commands, or output you'll want to search later → \`ctx_batch_execute\`.** One call runs them all, indexes every output, and returns only the sections matching your \`queries\` — gather and answer in a single round trip instead of N sequential \`ctx_execute\` calls.`;
const TREE = `├── MORE THAN ONE command, or one command whose output you'll query later?
│   └── Use ctx_batch_execute — one call runs them all, indexes every output,
│       and returns only the sections matching \`queries\`. Replaces N sequential
│       ctx_execute calls (N round-trips) with one.
│
`;
const ROWS = `| Several commands / multi-issue lookups | \`ctx_batch_execute\` | \`[{label: "issue 1", command: "gh issue view 1"}, ...]\` + \`queries: [...]\` |
| Need the answer AND a searchable index in one round trip | \`ctx_batch_execute\` | output is auto-indexed; \`queries\` returns the matching sections inline |
| Summarize N files without reading any of them | \`ctx_batch_execute\` | one command per file, print only the derived answer |
`;
const WHENNOT = `## When NOT to Use

Each tool's description only carries the short contract; these are the negative halves — when something else is the right surface.

| Tool | Don't reach for it when | Use instead |
|------|-------------------------|-------------|
| \`ctx_execute\` | One observational command whose whole short output you'll consume verbatim (\`whoami\`, \`pwd\`, \`git status\` on a clean tree) | Bash |
| \`ctx_execute\` | File mutations (Edit/Write) or navigation (\`cd\`, \`ls\`) | Bash / the host's edit tools |
| \`ctx_execute_file\` | You intend to EDIT the file | the host's Read + exact-match Edit |
| \`ctx_execute_file\` | You need one known line, or the file is small and you'll consume all of it | the host's Read (offset/limit) |
| \`ctx_execute_file\` | The file is outside the workspace | refused by design (#852); use the host's Read |
| \`ctx_batch_execute\` | Single command with no follow-up query | plain \`ctx_execute\` |
| \`ctx_batch_execute\` | CPU-bound or stateful commands — keep \`concurrency: 1\` (npm test, build, lint, port-binding servers, lock holders) | serial, in one batch |
| \`ctx_index\` | Log files, test output, CSV or build output | \`ctx_execute_file\` — processes in-sandbox, persists nothing |
| \`ctx_index\` | Single-use content you'll never query again | keep it inline if it fits, else \`ctx_execute_file\` |
| \`ctx_index\` | Passing large data as \`content:\` | pass \`path:\` — \`content\` puts those bytes into context as a parameter |
| \`ctx_search\` | The data was never stored and no session memory accumulated around it | capture first (\`ctx_batch_execute\` / \`ctx_index\`), then search |
| \`ctx_search\` | One ad-hoc question against data that is not in the knowledge base | answer it inline in the sandbox — one round trip |
| \`ctx_fetch_and_index\` | You already have the content locally | \`ctx_index\` |
| \`ctx_fetch_and_index\` | The page is SPA / JavaScript-rendered | it is a plain HTTP fetch, no headless browser |
| \`ctx_stats\` | You actually want to delete something | \`ctx_purge(confirm: true)\` |
| \`ctx_purge\` | The user says "reset"/"clear"/"wipe" without naming a scope | ask which scope first |
| \`ctx_purge\` | The user wants to free memory or improve performance | show \`ctx_stats\` first, do not purge |

`;

edit(SKILL, "skill-coverage", (s) => {
  const did = [];
  const missing = [];
  let out = s;

  const insertAfter = (anchor, addition, marker, label) => {
    if (out.includes(marker)) { did.push(`${label}（已存在）`); return; }
    const at = out.indexOf(anchor);
    if (at < 0) { missing.push(`${label}：找不到锚点 ${JSON.stringify(anchor.slice(0, 40))}`); return; }
    out = out.slice(0, at + anchor.length) + addition + out.slice(at + anchor.length);
    did.push(label);
  };

  // 3a. MANDATORY RULE 里补一句
  insertAfter("cannot list them all.", MANDATE, "**Several commands, or output you'll want to search later", "MANDATORY RULE 补 batch_execute");
  // 3b. Decision Tree 补分支
  const treeAnchor = "├── Command is on the Bash whitelist (file mutations, git writes, navigation, echo)?";
  if (out.includes("MORE THAN ONE command")) did.push("Decision Tree 分支（已存在）");
  else if (!out.includes(treeAnchor)) missing.push("Decision Tree 分支：找不到 Bash whitelist 那一行");
  else { out = out.replace(treeAnchor, TREE + treeAnchor); did.push("Decision Tree 分支"); }
  // 3c. 工具表补三行
  insertAfter("| Situation | Tool | Example |\n|-----------|------|---------|\n", ROWS, "Several commands / multi-issue lookups", "工具表补 batch_execute 三行");
  // 3d. When NOT to Use 一节
  const autoAnchor = "## Automatic Triggers";
  if (out.includes("## When NOT to Use")) did.push("When NOT to Use（已存在）");
  else if (!out.includes(autoAnchor)) missing.push("When NOT to Use：找不到 ## Automatic Triggers 这个锚点");
  else { out = out.replace(autoAnchor, WHENNOT + autoAnchor); did.push("When NOT to Use 17 条"); }

  if (missing.length) return { status: "fail", why: missing.join("；") };
  if (out === s) return { status: "skip", why: "已是我们的版本" };
  return { status: "write", text: out, why: did.join("、") };
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. 沙箱机制的坑（cwd / 临时目录 / 环境变量 / 回显 / 超时 / 边界）与
//    Bash-vs-ctxm_* 取舍：主 skill 原本 0 处提及，第一次调用最容易踩
// ─────────────────────────────────────────────────────────────────────────────
const PITFALLS = `## Sandbox mechanics (pitfalls)

\`ctx_batch_execute\` / \`ctx_execute\` / \`ctx_execute_file\` run code in a fresh subprocess sandbox — not in the project shell.

- **cwd**: every language except \`shell\` runs in a fresh temp dir, so project-relative paths do NOT resolve. Use absolute paths, or \`language: "shell"\` (shell honors \`cwd\`, default: project root).
- **Nothing is written**: the sandbox filesystem is discarded — file changes go through the host's Write/Edit tools.
- **env**: cross-language injection variables are stripped (\`BASH_ENV\`, \`ENV\`, \`PROMPT_COMMAND\`, \`NODE_OPTIONS\`, \`PYTHONSTARTUP\`, \`RUBYOPT\`, \`PERL5OPT\`, \`ERL_FLAGS\`, \`GOFLAGS\`, \`RUSTC\`, …), \`TMPDIR\` points at the sandbox, \`LANG\` / \`NO_COLOR\` / \`PYTHON*\` are forced. Secrets (API keys) are inherited as usual.
- **echo**: the code you pass comes back (≤2000 chars) ahead of stdout — for tiny outputs plain Bash is cheaper.
- **timeout**: none by default (the host's RPC limit is the only bound) — pass \`timeout\` (ms) or \`background: true\` for long jobs.
- **boundary**: \`ctx_execute_file\` refuses paths outside the workspace (#852); \`ctx_execute\` has no such guard.

**Bash vs ctxm_\***: Bash — or the host's Read — is right when the output is short and fixed and you will use it verbatim, when you need the exact bytes (editing, error text, config values), or when you mutate state (git, mkdir, rm, mv, install). ctxm_* is right when the alternative is pulling bulk data into the conversation: repo-wide grep/glob, log or dependency or build output, multi-file scans, data aggregation. Native Grep/Glob/Read put every hit into the conversation — that is the cost this toolset exists to remove.

`;

edit(SKILL, "skill-pitfalls", (s) => {
  const anchor = "## Automatic Triggers";
  if (s.includes("## Sandbox mechanics (pitfalls)")) return { status: "skip", why: "已有 Sandbox mechanics 一节" };
  if (!s.includes(anchor)) return { status: "fail", why: `找不到 ${anchor} 锚点，无法插入沙箱坑位一节` };
  return { status: "write", text: s.replace(anchor, PITFALLS + anchor), why: "补沙箱机制与 Bash-vs-ctxm_* 取舍（cwd/临时目录/env/回显/超时/边界）" };
});

// ─────────────────────────────────────────────────────────────────────────────
const summary = `${wrote} 处改写、${skipped} 处已就绪、${failed} 处失败`;
for (const n of notes) console.warn(`⚠ ${n}`);
if (failed) {
  console.error(`[fork-patches] ${summary}`);
  console.error("[fork-patches] 锚点没了 = 上游改了对应实现，需要人工核对后用同一种锚定方式重新表达（不要退回 diff 补丁）");
  process.exit(1);
}
console.log(`[fork-patches] ${summary}`);
if (notes.length) process.exit(2);
