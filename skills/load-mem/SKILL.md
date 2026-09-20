---
name: load-mem
description: Understand a project through its existing memory when starting or resuming work, or when past decisions matter. Use StrictDoc docs/, Magic Context, claude-mem, and project evidence as complementary, overlapping sources. Identify current authoritative norms separately from history, recover relevant context, and surface meaningful contradictions. Choose the depth and retrieval path that suit the task.
---

# Load Memory

## Intent

Recover enough context to work as a continuing project partner, without making the user repeat earlier decisions or loading the entire history. Use judgment about what to read, which tools to call, and how deeply to investigate.

## Available memory

| Source | What it offers | Typical access |
|---|---|---|
| StrictDoc `docs/` | Human-readable current norms, decisions and rationale, project history, and maintained reference documents | Read relevant `.sdoc` files or their export |
| Magic Context | Stored facts, decisions, lessons, injected memories, and recoverable conversations | Injected memory, `ctx_search`, `ctx_expand`, `ctx_memory`, `ctx_note` |
| claude-mem | Searchable captured activity, observations, and historical context | `claude_mem_search` or available claude-mem MCP tools |
| Code, config, and git | Evidence of what exists and what actually changed | Relevant files, call chains, and history |

The same knowledge may appear in several sources. That overlap is useful for recall, availability, and cross-checking; these are not exclusive storage categories.

## Read with the right interpretation

- **StrictDoc is the source of truth for current project norms.** Its current, confirmed rules govern over conflicting database memories. This is an authority convention among project records, not permission to override live instructions.
- `project_memory/decisions.sdoc` holds decisions; `journal.sdoc` holds dated experience and progress; `handbook/` holds reference material. Existing projects may organize these differently.
- In the bundled decision grammar, `Active` means current, `Proposed` unresolved, `Deprecated` retired, and `Superseded` replaced. Follow replacement references when relevant. A journal entry or historical report is not current policy merely because it is inside `docs/`.
- Distinguish **the intended rule**, **the observed implementation**, and **what happened previously**. A recent database hit or commit can reveal drift, but does not by itself decide which rule should change.
- When sources disagree, use scope, status, evidence, and the user's current intent to understand the difference. Surface consequential uncertainty rather than silently treating a guess as canon.
- The canon can evolve. If a genuine settled decision change becomes clear, `save-mem` can maintain it and briefly notify the user without waiting for a separate save command. Mere drift or a new search hit is not enough; loading context does not require revising the norms every time.

## Practical guidance

- Start with the task and project instructions. Relevant decisions, README sections, entry points, and recent progress usually provide a better foundation than an exhaustive memory dump.
- Injected Magic Context memories are already available. Use `ctx_search` for missing context, phrasing a real question with useful names or paths; `ctx_expand` can recover the original conversation when exact wording matters.
- Use claude-mem when earlier activity or observations would help. Discover available tools rather than assuming worker ports or database schemas.
- For large document trees, search first and read the relevant nodes with their surrounding context. Source `.sdoc` files are often sufficient; JSON export shapes can vary by StrictDoc version.
- Missing layers are normal. Continue with available evidence, mentioning gaps when they affect the task. `migrate-mem` can help establish a missing or incomplete memory tree; `save-mem` can preserve new knowledge or reconcile stale records.
- Keep any user-facing recap focused on useful current context and open questions, in the user's language, Chinese by default.
