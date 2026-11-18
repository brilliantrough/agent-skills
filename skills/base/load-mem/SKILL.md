---
name: load-mem
description: Recover project context when starting or resuming work, revisiting earlier decisions or attempted solutions, or diagnosing a recurring failure (之前怎么做、为什么放弃、这个坑又出现了). Proactively retrieve relevant claude-mem observations alongside StrictDoc, Magic Context, and project evidence. Distinguish current norms from history, use the host's actual memory tools, and stop when the available evidence is sufficient.
---

# Load Memory

## Intent

Recover enough context to work as a continuing project partner, so the user does not have to repeat earlier decisions and the session does not load the entire history. Use judgment about what to read, which tools to call, and how deeply to investigate; stop when the evidence is sufficient to act.

## Apply user discipline before recall

- After project instructions, check the root `AGENTS.md` `user-discipline` block when present. It is binding user instruction; within project records it outranks the profile, decisions, journal and database memories. If it changed during this session, reread it.
- Leave active discipline as written while loading memory: no copying, demoting or revising. Surface conflicts with other records; only explicit user instruction changes the block.

## Orient with the project profile first

- After project instructions, read the current project profile from the registered entry; the StrictDoc default is `docs/handbook/project-profile.sdoc`. If the project already has an equivalent overview, use that one. Reuse it if already read and unchanged.
- Build the overall model first — purpose, main flow, module responsibilities and key design; for research, the shared question, major routes, their relations and evidence limits — then retrieve task-relevant decisions, history and specialist documents. `project-profile` defines this view. Resume the route the task belongs to; the latest or currently leading route is one of several.
- Check its last verification scope and unknowns. A profile is navigation: verify the relevant implementation before editing, and report or correct consequential drift within scope.
- If no profile exists, continue normal targeted recall and suggest creating one when useful. Startup does not depend on a profile and does not expand into a full-repository survey.

## Available memory

| Source | What it offers | Typical access |
|---|---|---|
| StrictDoc `docs/` | Human-readable current norms, decisions and rationale, project history, and maintained reference documents | Read relevant `.sdoc` files or their export |
| Magic Context | Stored facts, decisions, lessons, injected memories, and recoverable conversations | Injected memory, `ctx_search`, `ctx_expand`, `ctx_memory`, `ctx_note` |
| claude-mem | Cross-session observations of decisions, attempted solutions, failures, fixes, and actual work | Pi native `mem_*`; OpenCode `claude_mem_search` or claude-mem MCP tools; see below |
| Code, config, and git | Evidence of what exists and what actually changed | Relevant files, call chains, and history |

The same knowledge may appear in several sources. That overlap helps recall, availability, and cross-checking.

## Recall with claude-mem

- When earlier decisions, attempts, fixes, or work history could change the next action, proactively search claude-mem before asking the user to repeat them or redoing the investigation. Use it alongside the other stores from the start, whether or not Magic Context has already answered.
- Automatic capture, injected context, and active search are different. An injected index is a partial view, and a miss in Magic Context says nothing about claude-mem. If evidence is already sufficient, skip duplicate queries. Empty results can reflect project/platform scope rather than an empty database.

### Recognize the host's tools

These are all entry points to **claude-mem**. Names below reflect claude-mem 13.39.0, Pi 1.2.0 and OpenCode 2.0.29 (2026-10-14); discover the actual catalog and parameter schema when versions or server names differ.

| Integration | Tool names / access | Recall flow |
|---|---|---|
| Pi official native extension | `mem_search`, `mem_timeline`, `mem_get_observations` — no MCP prefix | Search with `query`/`limit`; inspect useful anchors with `mem_timeline`; fetch selected IDs with `mem_get_observations` |
| OpenCode plugin's simple search | `claude_mem_search` | `query` only; not the full MCP workflow |
| OpenCode claude-mem MCP | Server tools `mem_search`, `search`, `timeline`, `get_observations`, etc.; v2 Code Mode example: `tools["claude-mem"].mem_search(...)`; direct exposure example: `claude-mem_mem_search` | MCP `mem_search` supports guided/auto retrieval; use its own schema and returned next-step guidance |
| Pi with an additionally configured claude-mem MCP | Example: `mcp__claude_mem__mem_search` | MCP contract (differs from the native Pi contract); this extra MCP is optional |

- MCP examples assume the server key `claude-mem`. Use the catalog's exact prefix, punctuation, and call signature; OpenCode and Pi expose them differently. In Code Mode, search its catalog if a tool is not listed.
- **Same basename does not mean same parameters:** Pi native `mem_search` does not accept MCP `mode`, `continuation`, or `selectedIds`. MCP guided replies supply the continuation and selectable IDs; auto mode performs bounded retrieval in one call. Older MCP `search` → `timeline` → `get_observations` remains a separate layered interface.
- Fetch only the context/details needed to answer the question; an adequate index needs no further expansion. If injected text says `get_observations` or `mem-search skill`, map it to the available claude-mem tools; that skill may not be installed. On native Pi, detail retrieval is `mem_get_observations`.
- Treat retrieved observations as historical evidence. Verify changed facts against current norms and source before acting on them.

## Read with the right interpretation

- Below live user instructions and any user-discipline block, **StrictDoc is the source of truth among other project records**. Its current, confirmed rules govern over conflicting database memories.
- `project_memory/decisions.sdoc` holds decisions; `journal.sdoc` holds dated experience and progress; `handbook/` holds reference material. Existing projects may organize these differently.
- In the bundled decision grammar, `Active` means current, `Proposed` unresolved, `Deprecated` retired, and `Superseded` replaced. Follow replacement references when relevant. Journal entries and historical reports inside `docs/` are history; only `Active` decisions are current policy.
- Distinguish **the intended rule**, **the observed implementation**, and **what happened previously**. A recent database hit or commit can reveal drift; deciding which side should change takes the rule's status, evidence and the user's intent.
- When sources disagree, use scope, status, evidence, and the user's current intent to understand the difference, and surface consequential uncertainty to the user.
- The canon can evolve. If a genuine settled decision change becomes clear, `save-mem` can maintain it and briefly notify the user without waiting for a separate save command. Drift or a new search hit alone does not change the norms.

## Practical guidance

- Start with the task and project instructions. Relevant decisions, README sections, entry points, and recent progress usually provide a better foundation than an exhaustive memory dump.
- Reuse skills and confirmed facts already available in this session, and reload only missing or changed material. Keep a compact working set of current constraints, source locations, open questions and the next action in the existing session context/todo.
- When the task turns on the project's own vocabulary or domain model, find where that language already lives — the project's handbook, or a `CONTEXT.md` where the project uses one — before inventing names. Changing the model is `domain-modeling`'s job.
- Injected Magic Context memories are already available. Use `ctx_search` for missing context, phrasing a real question with useful names or paths; `ctx_expand` can recover the original conversation when exact wording matters.
- Discover claude-mem tools through the host's catalog rather than assuming worker ports or database schemas. A missing tool or failed call is a capability gap; history may still exist.
- Missing layers are normal. Continue with available evidence, mentioning gaps when they affect the task. `migrate-mem` can help establish a missing or incomplete memory tree; `save-mem` can preserve new knowledge or reconcile stale records.
- Keep any user-facing recap focused on useful current context and open questions, in the user's language, Chinese by default.

## Narrow the tree before reading it

A StrictDoc tree outgrows a single read: one decisions file plus one journal can run past 20k tokens. `.sdoc` is plain text, so grep it instead of loading it whole.

```bash
# the authoritative set: current decisions with their UID and title
grep -B1 -A1 '^STATUS: Active' docs/project_memory/decisions.sdoc

# one topic across the whole tree (decisions, journal, handbook)
grep -rn -i -B2 -A6 '<keyword>' docs/project_memory/

# list journal entries, then read only the one you need
grep -n '^UID: ' docs/project_memory/journal.sdoc
```

Then read the matched node and its immediate neighbours. Paths differ per project — find them first (`ls docs/project_memory/`) instead of assuming the layout above. Reading only the matching node keeps the answer and the context window intact. Source `.sdoc` files are usually sufficient; JSON export shapes can vary by StrictDoc version.
