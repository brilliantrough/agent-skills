<!-- memory-system:start -->
## Project Memory System

This project uses a three-layer memory system (Magic Context + StrictDoc + claude-mem).

- **At session start**: run the `load-mem` skill before doing substantial work.
- **At milestones and before ending work**: run the `save-mem` skill.

### Memory intent

- Use StrictDoc, Magic Context, and claude-mem together; their knowledge may intentionally overlap. Let the Agent choose useful storage, retrieval depth, and timing rather than enforcing a one-store-per-fact pipeline.
- Among project records, **current StrictDoc norms are the source of truth** when memories disagree. The usual `docs/` layout separates `project_memory/` (decisions and journal) from `handbook/` (reference documents). `Active` decisions describe current rules; proposals, retired decisions, journal entries, and historical reports should remain distinguishable from them.
- **当前规范可以维护，但历史节点不直接抹掉。** 用户明确改变决定，或已确定的变化足够清晰时，可新增 successor、标记旧节点 `Superseded` 并简短告知；不因猜测、临时尝试或每次任务就改规范。普通说明文档和非规范记忆可更灵活整理。
- Make documents easy to skim: Chinese by default, short phrases, lists, compact tables, and occasional adjacent `PS:` explanations. Keep enough context and technical precision to understand what applies and why.
- Validate `.sdoc` or StrictDoc config changes with `strictdoc export .` from the docs root. Use the available executable or project environment; resolve export failures before treating the update as complete.

### Context window (always applies)

- Big output never enters context: bulk commands / multi-file analysis -> `ctxm_batch_execute`, one-off computation -> `ctxm_execute`, reading a file -> `ctxm_execute_file`. Web -> the configured MCP tools first (`tavily_search` for facts/news, `firecrawl_search` for ranked results, `firecrawl_scrape` for a known page), over any host built-in like WebFetch; `ctxm_fetch_and_index` only for a page you will re-query (how-to lives in the `context-mode` skill).
- Magic Context supports recall and durable storage: `ctx_search` can recover earlier decisions before asking the user, `ctx_memory` can preserve useful knowledge, and `ctx_note` can hold reminders. Use alongside StrictDoc and claude-mem, with useful overlap.
- Native `Read`/`Grep`/`Glob` stay right when you need the exact bytes or will edit the file — never route those through `ctxm_*`.

### Steering the agent (always applies)

- Steer with prompts, skills and tool descriptions — never with hard blocks. Guidance keeps judgement and variety; deny rules are a last resort for damage, not for preference.
- Adding an MCP server: keep tool names short (pi-mcp-adapter `toolPrefix: "none"`) and descriptions rich — the description is all the model reads before choosing.
- When a behaviour goes wrong, fix the system that produced it (a line here, a skill, or a fork patch), not just the config of the machine you noticed it on.

### Code taste (always applies when writing or changing code)

- Running code without errors IS the verification — no tests, no TDD, no verification scripts unless explicitly asked.
- No over-encapsulation, no defensive programming, no speculative abstraction. Minimum code that works.
- Report results in one line; no summary essays.
- Script/repo comments carry usage and necessary function notes only. The reasoning behind a change — alternatives weighed, measurements, upstream drift, failure modes — is development process and belongs in the local memory system (the gitignored StrictDoc tree and session memory), never in the repository files.

**Placement**: paste this whole block at the *tail* of a project's own `AGENTS.md` — the project's own content stays on top, this block is the accelerator we append. The one-click setup scripts offer to write it there (opt-in, default no); paste it by hand otherwise.

(Memory intent and practical tool guidance live in `load-mem`, `save-mem`, and `migrate-mem` — keep this block short.)
<!-- memory-system:end -->
