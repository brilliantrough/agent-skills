---
name: migrate-mem
description: Establish or repair memory for a project that already has development or research history. Use when a project has no memory tree or an incomplete one. Surveys existing evidence, then initializes or enriches human-readable StrictDoc docs/ with current norms and historical context. Assumes no prior workflow, folder convention or StrictDoc skeleton.
---

# Migrate Memory

## Intent

Help an existing project acquire a readable, trustworthy memory foundation. The work is **understanding the project and initializing useful StrictDoc documentation**; old files stay where they are and artifacts are converted only when that helps.

Use judgment about investigation depth, document structure, storage overlap, and which questions need the user's input. The output is a small useful baseline, without a fixed inventory or classification report.

## Understand the project as it exists

- Look across project instructions, README, relevant implementation, research notes and history.
  - Understand purpose, architecture or research question, current state and unfinished work.
  - For research, recover the major routes and their evidence from existing derivations, observations and results as well as code; organize them through `project-profile` and `save-mem`.
  - Routes may coexist, and missing evidence is recorded as missing.
- Existing Magic Context memories and claude-mem observations can recover decisions or experiences not visible in code. StrictDoc can be initialized without them.
- Read the useful sources in context; projects differ in note names, plan directories and development methodology. Key code and decisions deserve more attention than generated output and exhaustive transcripts.
- Separate intended policy, observed implementation, past experience, and unresolved questions. Newer evidence can reveal a change; what the current rule ought to be is settled by the user or by confirmed decisions.

## Build a useful memory foundation

The companion `save-mem` skill describes memory maintenance and StrictDoc mechanics. Its `assets/docs-skeleton/` is a starting point; locate it through the skill registry or the sibling `../save-mem/` directory.

| Common location | Useful content |
|---|---|
| `docs/project_memory/decisions.sdoc` | Current rules and decisions, their scope and rationale, and retired predecessors |
| `docs/project_memory/journal.sdoc` | A dated project baseline, important experiences, progress, and open questions |
| `docs/handbook/` | Reference material worth maintaining: architecture, usage, specs, or operational guidance |
| `docs/strictdoc_config.py` | The StrictDoc project configuration |

- Adapt this layout to what already exists. Missing docs or a missing skeleton are normal starting conditions. Add the missing pieces and leave existing docs and config intact.
- Establish a single current project profile with `project-profile`, reusing this survey and any equivalent existing overview. The StrictDoc default is `docs/handbook/project-profile.sdoc`; register its actual path in the project entry so `load-mem` reads it first. Content and verification rules live in that skill.
- Distill enough knowledge to make the project understandable. Prefer a small useful baseline over a document for every module or every past action.
- Make **current StrictDoc norms the source of truth among ordinary project records**, distinguishable from historical journal entries and reports.
  - A root AGENTS `user-discipline` block remains binding user instruction above those records: keep it where it is, unchanged; it is never migrated into StrictDoc or turned into background memory.
  - Statuses such as Active, Proposed, Deprecated, and Superseded keep the distinction as the project evolves.
- When sources conflict or the intended rule is unclear, surface the consequential question to the user. Record a rationale only when it is known, and label inferred policy as inferred. If a settled decision has genuinely changed, maintain the current norm and briefly tell the user; ordinary memory and explanatory cleanup can be more flexible.
- The same fact or decision may also be stored in Magic Context. Choose the overlap that improves recall and resilience.

## Preserve the project while improving readability

- Keep existing source material and working documentation useful. Add or integrate rather than automatically moving, archiving, deleting, or reformatting everything; discuss consequential restructuring with the user.
- On later runs, build on existing nodes and references instead of recreating the baseline. Observe the project's history-preservation and version-control conventions.
- Before drafting or revising prose, load `readable-docs` and follow its writing contract; it applies beyond memory and `docs/` as well.
- Where helpful, connect conclusions to source files, commits, or memory references. Original documents remain in place as evidence; the handbook cites them.
- Startup/save guidance in `AGENTS.md` can help future Agents find the memory. Align it with the agreed intent where needed, preserving unrelated project instructions.

## Check the result in the real project

- Use the available StrictDoc installation or project environment. Inspect existing config and grammar before changing them; versions, environment managers and plugins vary by project.
- Validate `.sdoc` and configuration changes with `strictdoc export .` from the docs root, and inspect enough of the export to see whether lists, tables, and notes are readable.
- Check whether a new reader can tell what applies now, why it applies, what happened before, and what remains uncertain. A successful export alone does not establish that the content is correct.
- Briefly report the useful memory established, unresolved questions, and actual validation status. Report missing integrations and unverified runtime claims as explicit gaps.
