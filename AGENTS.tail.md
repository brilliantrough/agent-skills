<!-- memory-system:start -->
## Project Memory System

This project uses a three-layer memory system (Magic Context + StrictDoc + claude-mem).

- **At session start**: run the `load-mem` skill before doing substantial work.
- **At milestones and before ending work**: run the `save-mem` skill.

### Memory intent

- Use StrictDoc, Magic Context, and claude-mem together; their knowledge may intentionally overlap. Let the Agent choose useful storage, retrieval depth, and timing rather than enforcing a one-store-per-fact pipeline.
- For prior decisions, attempted solutions, recurring failures, or cross-session work, proactively retrieve relevant claude-mem observations alongside StrictDoc and Magic Context before asking the user to repeat context or redoing past investigation. Injected memories are only a partial view; reuse sufficient evidence instead of querying every store on every turn.
- The official claude-mem Pi extension exposes `mem_search`, `mem_timeline`, and `mem_get_observations`; OpenCode has `claude_mem_search` plus namespaced claude-mem MCP tools. These are claude-mem entry points, not unrelated memory systems. Use the actual tool catalog and schema; `load-mem` explains host-specific names and recall flows.
- Among project records, **current StrictDoc norms are the source of truth** when memories disagree. The usual `docs/` layout separates `project_memory/` (decisions and journal) from `handbook/` (reference documents). `Active` decisions describe current rules; proposals, retired decisions, journal entries, and historical reports should remain distinguishable from them.
- Read the StrictDoc tree narrowly: grep it instead of loading whole files — list current decisions with `grep -B1 -A1 '^STATUS: Active' docs/project_memory/decisions.sdoc`, search one topic across `docs/project_memory/`, then read only the matched node. A full-tree read buries the answer and costs the session; `load-mem` gives the exact commands.
- **当前规范可以维护，历史事实与决策含义不能抹掉。** 用户明确改变决定，或已确定的变化足够清晰时，可新增 successor、标记旧节点 `Superseded` 并简短告知；不因猜测、临时尝试或每次任务就改规范。普通说明文档和非规范记忆可更灵活整理。
- 用户显式要求记忆重组时，用 `consolidator` 按 **Ponytail** 风格改写、合并、重排和压缩：主线讲清，次要过程简述，不保留重复流水。先留可恢复基线，保持实质信息、状态、被引用身份与证据可追溯；纯表达整理无需 successor，不自动触发或另造摘要维护源。
- Record living negative knowledge alongside outcomes: open concerns, unproven feasibility assumptions, method weaknesses, shortcut risks, and the remaining distance to the goal belong in the project's risk register (`docs/project_memory/risks.sdoc`) when one exists — `save-mem` defines the fields and lenses. A concern the user voices is worth recording even before there is evidence for it.
- Validate `.sdoc` or StrictDoc config changes with `strictdoc export .` from the docs root. Use the available executable or project environment; resolve export failures before treating the update as complete.

### Technical writing (always applies)

- Before writing or revising any human-facing project technical text, load `readable-docs`: README, specs, design notes, plans, reports, runbooks, changelogs, and memory. This applies regardless of directory or workflow, not just `docs/`, `save-mem`, or `migrate-mem`.
- Write for scanning: Chinese by default, phrases, lists, compact comparison tables; omit subjects or objects only when clear. Preserve facts, conditions, uncertainty, required structure, and instruction strength. Short connected prose is welcome when it explains better; no invented facts or personality.

### Context window (always applies)

- Choose by the next action: exact source or a complete edit/logic unit -> native `Read`/`Grep`; short output consumed directly -> native `Bash`/`Read`; large-data aggregation -> `ctxm_execute`/`ctxm_execute_file`; multi-command indexed research -> `ctxm_batch_execute`. Return enough evidence to act, not bulk dumps or summaries that force another lookup.
- Web: never the host built-ins (WebSearch, WebFetch, web_search) — they are weaker or unconfigured here. Use the web MCP tools: `tavily_search`/`tavily_extract` for facts/news, `firecrawl_search` for ranked results, `firecrawl_scrape` for a known page (use the actual exposed name; Pi native names are `mcp__<server>__<tool>` with non-identifier characters replaced by underscores; long or colliding names get a hash suffix, so use the exposed metadata rather than constructing names). Discover the remaining tools (firecrawl crawl/map/research, context7 docs) through Pi's `tool_search` and call them directly or via `codemode`; on hosts with an MCP gateway, use its search/describe/call flow. `ctxm_fetch_and_index` only for a page you will re-query (how-to lives in the `context-mode` skill).
- Magic Context supports recall and durable storage: `ctx_search` can recover earlier decisions before asking the user, `ctx_memory` can preserve useful knowledge, and `ctx_note` can hold reminders. Use alongside StrictDoc and claude-mem, with useful overlap.
- Reuse loaded skills, confirmed facts and current source while they remain available and unchanged. Recover only missing or stale context; after an exact-match edit fails, reread the affected unit rather than guessing another patch. `intent` is an optional retrieval query, not a task note; omit it when code already prints the answer.

### Long-running work (always applies)

- Pi: unknown completion time → `pi-background-tasks` (`bg_run` for shell, `bg_delegate` for read-only investigation, Fusion only for an explicit multi-model review). Known duration plus a custom next-step prompt → `later`. OpenCode v2: native `shell`/`subagent` with `background: true`, or `Ctrl+B`; it has no custom wake prompt, so use `later` when the resumed turn needs instructions.
- Launch, then end the turn. Do not sleep, poll, or block on completion. A wake-up is not proof of success: read the result, logs, or exit state before continuing.
- Background shell is not sandboxed. Keep `bg_delegate` isolated unless an extension-registered provider requires `ambient`.

### Steering the agent (always applies)

- Steer with prompts, skills and tool descriptions — never with hard blocks. Guidance keeps judgement and variety; deny rules are a last resort for damage, not for preference.
- `quick-do`, `steady-do`, and `plan-brief` are user-selected modes. If none is named, load one: `steady-do` for most work, `quick-do` for a small bounded change, `plan-brief` only for a large project or major change.
- Adding an MCP server: use descriptive server/tool names and rich descriptions. Pi native MCP keeps its namespace prefix; use `exposure` / `toolExposure` for direct versus discoverable tools, not adapter-only `toolPrefix` / `directTools`.
- When a behaviour goes wrong, fix the system that produced it (a line here, a skill, or a fork patch), not just the config of the machine you noticed it on.

### Code taste (always applies when writing or changing code)

- Running code without errors IS the verification — no tests, no TDD, no verification scripts unless explicitly asked.
- No over-encapsulation, no defensive programming, no speculative abstraction. Minimum code that works.
- Report results in one line; no summary essays.
- Script/repo comments carry usage and necessary function notes only. The reasoning behind a change — alternatives weighed, measurements, upstream drift, failure modes — is development process and belongs in the local memory system (the gitignored StrictDoc tree and session memory), never in the repository files.

**Placement**: paste this whole block at the *tail* of a project's own `AGENTS.md` — the project's own content stays on top, this block is the accelerator we append. The one-click setup scripts offer to write it there (opt-in, default no); paste it by hand otherwise.

(Practical guidance lives in `load-mem`, `save-mem`, `migrate-mem`, and `readable-docs` — keep this block short.)
<!-- memory-system:end -->
