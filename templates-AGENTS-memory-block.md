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

(Procedures for reading/writing memory live in the `load-mem`/`save-mem` skills — keep this file short.)
<!-- memory-system:end -->
