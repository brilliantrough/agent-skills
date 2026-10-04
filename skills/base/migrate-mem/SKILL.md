---
name: migrate-mem
description: Establish useful memory for a project that already has development history, or improve an incomplete memory setup. Survey the project and its existing evidence, then initialize or enrich human-readable StrictDoc docs/ with current norms and historical context. Use Magic Context and other available memory alongside it where useful. No previous workflow, legacy folder convention, or pre-existing StrictDoc skeleton is assumed.
---

# Migrate Memory

## Intent

Help an already-developed project acquire a readable, trustworthy memory foundation. The emphasis is **understanding the project and initializing useful StrictDoc documentation**, not moving old files or converting every artifact.

Use judgment about investigation depth, document structure, storage overlap, and which questions need the user's input. There is no fixed inventory, mandatory classification report, or approval ceremony for every initialization.

## Understand the project as it exists

- Look across project instructions, README, main modules, entry points, configuration, existing docs, and relevant development history. Follow the evidence far enough to understand purpose, architecture, conventions, current state, and unfinished work.
- Existing Magic Context memories and claude-mem observations can recover decisions or experiences not visible in code. Their absence does not prevent initializing StrictDoc.
- Read the useful sources in context rather than assuming particular note names, plan directories, or an older development methodology. Generated output and exhaustive transcripts rarely need the same attention as key code and decisions.
- Separate intended policy, observed implementation, past experience, and unresolved questions. Newer evidence can reveal change without automatically settling what the current rule ought to be.

## Build a useful memory foundation

The companion `save-mem` skill describes memory maintenance and StrictDoc mechanics. Its `assets/docs-skeleton/` is a starting point, located through the skill registry or the sibling `../save-mem/` directory, not a fixed home-directory path.

| Common location | Useful content |
|---|---|
| `docs/project_memory/decisions.sdoc` | Current rules and decisions, their scope and rationale, and retired predecessors |
| `docs/project_memory/journal.sdoc` | A dated project baseline, important experiences, progress, and open questions |
| `docs/handbook/` | Reference material worth maintaining: architecture, usage, specs, or operational guidance |
| `docs/strictdoc_config.py` | The StrictDoc project configuration |

- Adapt this layout to what already exists. Missing docs or a missing skeleton are normal starting conditions; an existing docs directory is not an invitation to overwrite it.
- Distill enough knowledge to make the project understandable. Prefer a small useful baseline over a document for every module or every past action.
- Make **current StrictDoc norms the source of truth**, distinguishable from historical journal entries and reports. Statuses such as Active, Proposed, Deprecated, and Superseded help preserve this distinction as the project evolves.
- When sources conflict or the intended rule is unclear, surface the consequential question. Avoid inventing a rationale or presenting inferred policy as confirmed. If a settled decision has genuinely changed, maintain the current norm and briefly tell the user rather than waiting for a separate documentation command; ordinary memory and explanatory cleanup can be more flexible.
- The same fact or decision may also be stored in Magic Context. Choose overlap that improves recall and resilience; neither one-store-per-fact nor mirror-everything is the goal.

## Preserve the project while improving readability

- Keep existing source material and working documentation useful. Add or integrate rather than automatically moving, archiving, deleting, or reformatting everything; discuss consequential restructuring with the user.
- On later runs, build on existing nodes and references instead of recreating the baseline. Observe the project's history-preservation and version-control conventions.
- Before drafting or revising prose, load `readable-docs` for the shared project writing style: phrases, lists, and compact tables without losing facts or conditions. It applies beyond memory and `docs/` as well.
- Where helpful, connect conclusions to source files, commits, or memory references. Original documents can remain as evidence rather than being copied verbatim into the new handbook.
- Startup/save guidance in `AGENTS.md` can help future Agents find the memory. Align it with the agreed intent where needed, preserving unrelated project instructions.

## Check the result in the real project

- Use the available StrictDoc installation or project environment. Inspect existing config and grammar before changing them; avoid assuming a specific version, environment manager, or plugin installation.
- Validate `.sdoc` and configuration changes with `strictdoc export .` from the docs root, and inspect enough of the export to see whether lists, tables, and notes are readable.
- Consider whether a new reader can tell what applies now, why it applies, what happened before, and what remains uncertain. A successful export alone does not establish that the content is correct.
- Briefly report the useful memory established, unresolved questions, and actual validation status. Missing integrations or unverified runtime claims can remain explicit gaps rather than reasons to invent completion.
