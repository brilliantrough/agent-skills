---
name: save-mem
description: save memory according to current state and progress — durable facts to ctx_memory, narrative to StrictDoc project_memory
---

Record the current state so the next session can resume quickly. Extract the most core and important content. Be concise and to the point.

**When to run this:** at milestones, before ending any work session, and immediately after a decision or config change lands — do not wait for the human to ask.

**Before writing, check what already exists:** the injected `<project-memory>` block lists current memories — update or merge an existing entry instead of writing a near-duplicate (`ctx_memory` action=`update`/`merge`/`archive`).

**Tools missing?** If `ctx_memory`/`ctx_note` don't exist on this machine, don't lose the fact: record it as a journal `[TEXT]` node and say plainly that the tool layer is absent.

**Route by content type — do not dump everything into files:**

1. **Durable operational facts** (constraints, config values, naming conventions, architecture facts, hard-won workarounds) → write to `ctx_memory`. These are auto-injected into every future session.
2. **Project narrative** (progress, decisions with rationale, next steps) → the `docs/project_memory/` tree (see below).
3. **Durable documents** (specs, research reports, evaluations, design docs) → the `docs/handbook/<topic>/` tree (see below).
4. **Follow-ups for later** → `ctx_note`.
5. **Action details** (which commands ran, which files were touched) → do NOT record. claude-mem captures tool activity automatically.

**Writing to `docs/project_memory/` (memory tree):**

- **No `docs/` skeleton yet?** Bootstrap from the bundled one: `mkdir -p <project>/docs && cp -r ~/.agents/skills/save-mem/assets/docs-skeleton/. <project>/docs/`, edit `project_title` in `strictdoc_config.py`, then validate with `strictdoc export .` — skeleton is pre-validated (custom DECISION grammar included).

- **Decisions** go to `decisions.sdoc` as `[DECISION]` nodes: `UID` (DEC-XXX-NNN), `STATUS` (Proposed/Active/Deprecated/Superseded), `TITLE`, `STATEMENT` (the canon), `RATIONALE` (the original motivation — always fill this; losing it is a known pain point).
- **Progress entries** go to `journal.sdoc` as `[TEXT]` nodes with a date UID (e.g. `JOURNAL-2026-08-26`), referencing decision UIDs where relevant.
- **Never delete or rewrite a node.** To retire one: set `STATUS: Deprecated` or `Superseded` and add a `RELATIONS: - TYPE: Parent / VALUE: <successor UID> / ROLE: Supersedes` link from the successor node.
- **Validate after every write**: run `strictdoc export .` in `docs/` (covers both trees). A parse error must be fixed immediately — never leave the tree broken. Environment: prefer plain `strictdoc` from the currently activated Python env (the agent shell usually inherits the user's conda/uv/venv env). If it's not on PATH, detect the project's env (e.g. `.venv/bin/strictdoc`, `uv run strictdoc`, or a named conda env) — do not assume `.venv`.
- SDoc strict rules: one empty line between nodes, no content outside grammar elements, no empty optional fields (omit them). Sections use ONLY the double-bracket form `[[SECTION]]`/`[[/SECTION]]` — the single-bracket `[SECTION]` was removed in strictdoc 0.28.3 (processor error). If export fails with "[SECTION] elements are no longer supported", some file uses the single-bracket form — fix with: `find . -name '*.sdoc' -exec sed -i -e 's/^\[SECTION\]/[[SECTION]]/g' -e 's/^\[\/SECTION\]/[[\/SECTION]]/g' {} +`

**Writing to `docs/handbook/` (document tree):**

- One `.sdoc` per document under a topic subdir (e.g. `handbook/research/`, `handbook/specs/`).
- `[DOCUMENT]` header has no UID field — use `TITLE:` + `DATE:`; add `OPTIONS:` with `MARKUP: Markdown` (the default RST chokes on ``` fences and `backticks`).
- Map `##` headings to `[[SECTION]]` + `[TEXT]` nodes; **every section must be closed with `[[/SECTION]]`**.
- Keep the content verbatim; structure is the only thing you add.

**Document taste (applies to everything you author — decisions, journal, handbook):**

- 中文为主,术语可保留英文。
- 结构优先:对比/参数/状态用**表格**,步骤/要点用**列表**;不要"小标题 + 大段连续文字"的形态。
- Ponytail 式简洁:一个节点只说一件事;不写铺垫、复述、总结性废话;同一信息只出现一处。
