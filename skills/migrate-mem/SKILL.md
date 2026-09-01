---
name: migrate-mem
description: migrate an existing project's scattered/flat legacy memory files and documents into the three-layer memory system (ctx_memory + StrictDoc project_memory/handbook). Use when adopting the memory stack in a project that already has accumulated messy memory notes or docs.
---

Migrate legacy memory files into the three-layer system WITHOUT losing information or misjudging what is still current. Work in phases; the classification plan must be reviewed by the human before any writing.

**Prerequisites (verify first, stop if missing):** strictdoc env installed (pin the version, e.g. `strictdoc==0.28.1`, and keep it identical across machines — GitHub releases run ahead of PyPI and 0.28.3 removes single-bracket `[SECTION]`), `docs/` StrictDoc skeleton exists in the v2 layout (config at `docs/strictdoc_config.py` + `project_memory/` + `handbook/` trees), project `AGENTS.md` trigger block in place. If the skeleton is absent or a different layout, stop and ask the human — do not improvise a restructure.

## Phase 0 — Safety

- Copy every legacy memory file to `docs/_memory_archive/` (OUTSIDE the two sdoc trees, preserving paths). Originals are only moved, never deleted, and only after the final report is accepted.

## Phase 1 — Inventory

- Find all memory-bearing files: old `docs/project_memory/*.md`, scattered NOTES/TODO files, spec/plan/research/evaluation docs under `docs/` subdirectories, root-level notes.
- Read them fully (chunk large files; keep a ledger file so compaction loses nothing). Extract discrete items, each tagged: operational fact / decision / progress / durable document / action trivia / obsolete — with its source file path.

## Phase 2 — Classification plan (HUMAN CHECKPOINT)

- Route each item per the standard rules: durable operational fact → `ctx_memory`; decision → `[DECISION]` node; progress/status → `journal.sdoc`; durable document (spec/research/evaluation/design doc) → `docs/handbook/<topic>/` via md→sdoc wrapping (see Phase 3); pure action trivia → drop (claude-mem covers it).
- Contradictions: pick the current canon, mark losers as `Superseded` with a relation to the winner. If you cannot tell which is current, mark the item `STATUS: Proposed` and flag it — do NOT guess.
- **Never fabricate a RATIONALE.** Only write one when the original motivation is discernible from the source text; otherwise omit the field. An invented rationale is worse than a missing one.
- Present the plan as a table (item → destination → STATUS → reason) and STOP for human approval. On first migration of a project, always stop; on later runs, stop only if conflicts or Proposed items exist.

## Phase 3 — Execute (after approval)

- UIDs: scan existing nodes, continue the sequence; topic prefixes (DEC-MEM-*, DEC-AUTH-*, ...).
- Write `decisions.sdoc` / `journal.sdoc` nodes. STATEMENT keeps the original wording of the canon (light clarity edits only). Newly authored node content follows the document taste in `save-mem` (中文为主;表格/列表优先,忌小标题+大段文字;不冗余). Legacy documents being wrapped stay verbatim — structure only.
- **Document wrapping (md → handbook sdoc)**: one md file → one `.sdoc` under `docs/handbook/<topic>/`. `[DOCUMENT]` header: `TITLE:` + `DATE:` (no UID field exists) + `OPTIONS:` with `MARKUP: Markdown`. Map `##` headings to `[[SECTION]]` + `[TEXT]` nodes (double brackets ONLY — single-bracket `[SECTION]` is removed in 0.28.3+); close every section with `[[/SECTION]]`. Content stays verbatim — you add structure, not prose.
- Write `ctx_memory` entries for operational facts — list existing memories first to avoid duplicates.
- Validate after EVERY file edit: `strictdoc export .` in `docs/`. Fix parse errors immediately. Prefer plain `strictdoc` from the activated Python env (conda/uv/venv — the agent shell usually inherits it); if not on PATH, detect the project's env instead of assuming `.venv`.

## Phase 4 — Report & archive

- Report: counts by destination, conflicts resolved (and which side won), `Proposed` items awaiting human confirmation, dropped trivia.
- Move originals into `docs/_memory_archive/`. Confirm `strictdoc export .` still passes.
