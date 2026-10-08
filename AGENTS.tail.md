<!-- memory-system:start -->
## Project Memory System

This project uses a three-layer memory system (Magic Context + StrictDoc + claude-mem).

- **At session start**: run the `load-mem` skill before doing substantial work.
- **At milestones and before ending work**: run the `save-mem` skill.

### Memory intent

- Use StrictDoc, Magic Context, and claude-mem together; their knowledge may intentionally overlap. Let the Agent choose useful storage, retrieval depth, and timing rather than enforcing a one-store-per-fact pipeline.
- Among project records, **current StrictDoc norms are the source of truth** when memories disagree. The usual `docs/` layout separates `project_memory/` (decisions and journal) from `handbook/` (reference documents). `Active` decisions describe current rules; proposals, retired decisions, journal entries, and historical reports should remain distinguishable from them.
- **当前规范可以维护，但历史节点不直接抹掉。** 用户明确改变决定，或已确定的变化足够清晰时，可新增 successor、标记旧节点 `Superseded` 并简短告知；不因猜测、临时尝试或每次任务就改规范。普通说明文档和非规范记忆可更灵活整理。
- Validate `.sdoc` or StrictDoc config changes with `strictdoc export .` from the docs root. Use the available executable or project environment; resolve export failures before treating the update as complete.

### Technical writing (always applies)

- Before writing or revising any human-facing project technical text, load `readable-docs`: README, specs, design notes, plans, reports, runbooks, changelogs, and memory. This applies regardless of directory or workflow, not just `docs/`, `save-mem`, or `migrate-mem`.
- Write for scanning: Chinese by default, phrases, lists, compact comparison tables; omit subjects or objects only when clear. Preserve facts, conditions, uncertainty, required structure, and instruction strength. Short connected prose is welcome when it explains better; no invented facts or personality.

### Context window (always applies)

- Big output never enters context: bulk commands / multi-file analysis -> `ctxm_batch_execute`, one-off computation -> `ctxm_execute`, reading a file -> `ctxm_execute_file`.
- Web: never the host built-ins (WebSearch, WebFetch, web_search) — they are weaker or unconfigured here. Use the mcphub-web MCP tools: `tavily_search`/`tavily_extract` for facts/news, `firecrawl_search` for ranked results, `firecrawl_scrape` for a known page (use the actual exposed name; Pi native names are `mcp__<server>__<tool>` with hyphens replaced by underscores). Discover the remaining tools (firecrawl crawl/map/research, context7 docs) through Pi's `tool_search` and call them directly or via `codemode`; on hosts with an MCP gateway, use its search/describe/call flow. `ctxm_fetch_and_index` only for a page you will re-query (how-to lives in the `context-mode` skill).
- Magic Context supports recall and durable storage: `ctx_search` can recover earlier decisions before asking the user, `ctx_memory` can preserve useful knowledge, and `ctx_note` can hold reminders. Use alongside StrictDoc and claude-mem, with useful overlap.
- Native `Read`/`Grep`/`Glob` stay right when you need the exact bytes or will edit the file — never route those through `ctxm_*`.

### Steering the agent (always applies)

- Steer with prompts, skills and tool descriptions — never with hard blocks. Guidance keeps judgement and variety; deny rules are a last resort for damage, not for preference.
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
