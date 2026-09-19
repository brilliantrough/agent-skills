<!-- memory-system:start -->
## Project Memory System

This project uses a three-layer memory system (Magic Context + StrictDoc + claude-mem).

- **At session start**: run the `load-mem` skill before doing substantial work.
- **At milestones and before ending work**: run the `save-mem` skill.

### Rules that always apply (even if the skills are not loaded)

1. `docs/` is a single StrictDoc project with two trees: `project_memory/` (memory: decisions, journal) and `handbook/` (durable documents). Only nodes with `STATUS: Active` are current canon; `Deprecated`/`Superseded`/`Proposed` nodes are history — never quote them as current practice.
2. Never delete or rewrite memory nodes. Retire via `STATUS` change plus a `Supersedes` relation to the successor node.
3. After editing any `.sdoc` file, validate immediately: run `strictdoc export .` inside `docs/`. Prefer the `strictdoc` on PATH (the activated conda/uv/venv env is inherited by the agent shell); if absent, detect the project env (e.g. `.venv/bin/strictdoc`, `uv run strictdoc`) — do not assume a specific env manager. Never leave the tree broken.
4. On conflict between memory sources, `ctx_memory` (the injected `<project-memory>` block) wins.

### Context window (always applies)

- Big output never enters context: bulk commands / multi-file analysis -> `ctxm_batch_execute`, one-off computation -> `ctxm_execute`, reading a file -> `ctxm_execute_file`. Web -> the configured MCP tools first (`tavily_search` for facts/news, `firecrawl_search` for ranked results, `firecrawl_scrape` for a known page), over any host built-in like WebFetch; `ctxm_fetch_and_index` only for a page you will re-query (how-to lives in the `context-mode` skill).
- Recall and durable knowledge go through Magic Context: `ctx_search` before asking the user, `ctx_memory` for facts future sessions need, `ctx_note` for "later".
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

**Placement**: paste this whole block at the *tail* of a project's own `AGENTS.md` — the project's own content stays on top, this block is the accelerator we append. `bash sync-agents-block.sh <项目目录…>` refreshes it (block missing → appended, present → replaced in place).

(Procedures for reading/writing memory live in the `load-mem`/`save-mem` skills — keep this file short.)
<!-- memory-system:end -->
