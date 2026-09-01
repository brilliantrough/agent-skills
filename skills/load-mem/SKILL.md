---
name: load-mem
description: load all memory layers (injected memory, StrictDoc project_memory, claude-mem history) plus core files to understand the project
---

Build an understanding of this project from all available memory layers, then verify against core files and directory structure.

**Memory layers (in priority order):**

1. **Injected project memory** — the `<project-memory>` block in your system prompt is already loaded. Do NOT re-fetch it. It is the authoritative source for constraints, config values, and conventions.
2. **File memory (StrictDoc)** — `docs/` is one StrictDoc project with two trees: `project_memory/` (memory: `decisions.sdoc` for 口径+初衷, `journal.sdoc` for progress) and `handbook/` (durable documents: specs, research, evaluations). Read the `.sdoc` files directly:
   - Nodes carry `UID` (stable anchor), `STATUS`, `STATEMENT` (the decision itself), `RATIONALE` (why it was made).
   - **STATUS discipline: only `Active` nodes are current canon.** `Deprecated`/`Superseded`/`Proposed` nodes are history — never quote them as current practice. When a node is Superseded, follow the relation to its successor.
   - To query precisely instead of reading everything: `strictdoc export --formats=json .` in `docs/`, then e.g. `jq '.DOCUMENTS[].NODES[] | select(.STATUS=="Active")' output/json/index.json`.
3. **Action history (claude-mem)** — a passive log of past tool activity with semantic search. If the files look stale or you need "what was actually done recently", use the `claude_mem_search` tool (fallback: `curl http://127.0.0.1:37700/...` worker API). Treat results as leads, not gospel — verify against files/git before acting on them.

**Missing pieces are normal on new machines:** no `<project-memory>` block, no claude-mem tool/worker, or no `docs/` tree means that layer is simply absent — say which layers are unavailable and continue with what exists. Never stall and never invent tool output.

**Then ground it in code:**

- Glob the directory structure and read core files to confirm the memory matches reality.
- In projects not yet migrated, legacy markdown may still exist in other subdirectories under `docs/` (e.g. old `superpowers/`, `research/`). Skim for context but treat as historical until migrated into `docs/handbook/`.

You can use ripgrep and naive grep, and load relevant skills as needed.

**Keep the loop closed (ongoing duty, not a one-shot load):**

- The moment you learn a durable fact (constraint, config value, naming rule, hard-won workaround), write it to `ctx_memory` immediately — do not batch it for later.
- At milestones and before ending any work session, run the `save-mem` skill so progress and decisions reach the StrictDoc tree.
