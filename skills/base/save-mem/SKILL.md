---
name: save-mem
description: Preserve useful project knowledge at milestones, after a resolved failure or settled decision, when a feasibility concern or user worry surfaces, and before ending work. Use StrictDoc, Magic Context, and claude-mem together; when a claude-mem write tool is available, explicitly save important decisions, corrections, and handoff facts rather than assuming automatic capture succeeded. Harvest living negative knowledge (open concerns, risks, distance to goal) into the project's risk register. Keep current norms distinguishable from history, allow useful overlap, and choose storage, detail, and timing with judgment.
---

# Save Memory

## Intent

Leave memory that helps both the next Agent and the human reader understand **what applies now, why, and how the project got here**. Preserve useful knowledge rather than reproducing the conversation. Decide what deserves saving and where; the following are guidance, not a storage pipeline or a checklist for every save.

## Use the stores together

| Store | Useful capabilities |
|---|---|
| StrictDoc `docs/` | Readable current rules and decisions, rationale, project history, specs, and runbooks |
| Magic Context `ctx_memory` | Persistent facts, rules, decisions, lessons, and context available across sessions |
| Magic Context `ctx_search` / `ctx_expand` | Find existing knowledge and recover the discussion behind it |
| Magic Context `ctx_note` | Reminders and follow-ups for later |
| claude-mem | Searchable cross-session observations; explicit durable notes when a write tool is available |

- Storing the same knowledge in StrictDoc and Magic Context is reasonable and often useful. Database entries can contain substantive knowledge, not just document pointers.
- Choose the amount of overlap and detail that helps future work. There is no requirement for every memory to have a document counterpart, or for every document to be mirrored in a database.
- Existing memories and relevant source files help avoid accidental duplicates and stale claims. `ctx_memory` supports writing, updating, merging, and archiving; use the operation that fits. Paths and UIDs are useful cross-references, not prerequisites for saving.
- Missing tools need not stop the other stores from being useful. Be clear about any important knowledge that remains unsaved or unverified.
- A project's **vocabulary and domain model** are memory too: `domain-modeling` is the skill for changing them (challenging terms, glossary entries, hard-to-reverse decisions). Land its output in this project's own layers — the glossary in StrictDoc's handbook (or a `CONTEXT.md` where the project already uses one), hard-to-reverse decisions as `project_memory/decisions.sdoc` nodes rather than a second parallel decision tree.

## Preserve key outcomes in claude-mem

- Automatic capture can preserve work history, but tool availability or a successful host turn does not prove a key conclusion was stored. When a claude-mem write tool is available, explicitly save important decisions, corrections, resolved failures, and handoff facts; inspect the result before claiming persistence.
- Search relevant existing observations before adding a note, reusing evidence already retrieved. Keep useful conclusions and their scope, not full transcripts or secrets; useful overlap with StrictDoc and Magic Context is welcome, not a mandatory mirror of every entry.
- Tool identity follows the integration: Pi's native `mem_search` / `mem_timeline` / `mem_get_observations` and OpenCode's `claude_mem_search` are **claude-mem recall tools**, not write tools. See `load-mem` for the host-specific naming and parameter differences.
- With claude-mem MCP, `save_memory` (`text`, optional `title`/`project`) saves a local-worker note. In OpenCode v2 Code Mode, for server key `claude-mem`, that is `tools["claude-mem"].save_memory(...)`; direct exposure can be `claude-mem_save_memory`. An additionally configured Pi MCP can expose `mcp__claude_mem__save_memory`. Use the actual catalog, not a guessed name.
- In server runtime, use `observation_add` only when exposed for the intended server/project; `save_memory` does not write server notes. Native Pi alone has no explicit write tool in the verified 13.39.0 interface (2026-10-14): continue with available stores, without inventing `mem_save` or installing extra integrations just to finish a save.

## Keep the current project profile useful

When a settled change affects the project’s overall shape, use `project-profile` to update the affected parts of its existing profile (StrictDoc default: `docs/handbook/project-profile.sdoc`). Check the related code/config and state the actual verification scope; do not rewrite it for every save, local edit or experiment. If missing, suggest establishing one instead of silently adding a repository-wide survey. The profile explains what exists now; decisions and history retain the evidence and reasons.

## Keep current truth distinguishable from history

**StrictDoc is the source of truth for current project norms when records disagree.** Magic Context and claude-mem may legitimately contain earlier or conflicting accounts; useful overlap does not imply equal authority for every historical statement.

- Keep current rules and their scope easy to identify. In the bundled grammar, decisions use `Active`, `Proposed`, `Deprecated`, or `Superseded`; dated journal entries describe experience rather than policy.
- **Active norms are maintainable; historical facts and decision meaning must survive.** When the user changes a decision, or a settled change is clear from the conversation and evidence, add a successor when useful, mark the old node `Superseded`, and briefly tell the user. Do not change the canon for guesses, temporary experiments, or every task. Ordinary explanatory docs and non-normative memories may be revised more freely.
- Keep meaningful decision changes understandable. A journal note, revision context, or successor decision may preserve what mattered about the previous approach; choose the lightest suitable form rather than requiring a new node for every edit. Follow any project-specific history-preservation rules.
- Capture the reason when known: evidence, constraints, alternatives, or the user's intent. An unknown reason is better acknowledged than invented.
- Distinguish accepted decisions, observed behavior, pending work, and unverified claims. A working implementation may still differ from the intended rule.
- Research and experiment records must state their stage (e.g. proxy study, single-model fast iteration, multi-model full-scale validation). Stages differ in scale, the question answered, and the strength of the conclusion: a lower-stage result guides decisions but is not a higher-stage conclusion, and a higher stage checks semantic consistency. Never mix results from different stages in one report, journal entry, or database record, or substitute one for another.
- Harvest living negative knowledge, not only outcomes. At milestones — and after any feasibility discussion, including side sessions — record open concerns, unproven feasibility assumptions, known method weaknesses, shortcuts and the risks they carry, dead ends and why they were abandoned, and one line on the remaining distance to the goal. A concern discussed but never recorded is lost; a worry the user voices is worth recording even before there is evidence for it.
- Risk lenses are prompts to think, not quotas — record only real items: algorithm mechanism (do the premises hold?), real execution (does the trick survive a real implementation; any disallowed cost?), data and scale (is the dataset available and extensible; can the model scale up?), training process (convergence preconditions, generalization), and value placement (is this the real bottleneck of the actual task — judge that with the `goal-first` skill and record only its outcome here).
- Field semantics are fixed, organization is free. Every risk or concern entry carries its status (Open/Mitigated/Resolved/Accepted), stage, the decision it blocks, current evidence, and the condition that would resolve it; the prose layout is the writer's choice. Where the project keeps a risk register (e.g. `docs/project_memory/risks.sdoc`), update entries in place as they evolve and leave a short journal note per change; otherwise record the same fields in StrictDoc prose or a database entry.
- Where useful, reconcile known stale database claims and link related records. This does not call for auditing every store on every save.

## Human-readable writing

Before drafting or revising memory prose, load `readable-docs` for the shared project writing style. It applies to all human-facing technical records, not only memory: Chinese by default, phrases, lists, and compact tables without losing facts or conditions.

- For history, preserve outcomes, evidence, lessons, and remaining questions rather than a tool-by-tool diary. Link to original detail when useful.
- Daily saving is not append-only: update the relevant existing entry when appropriate instead of repeating its background and status. Preserve original evidence and meaningful history, not every old sentence.
- Explicit periodic memory restructuring belongs to `consolidator`, with **Ponytail** taste: keep the main thread clear, compress incidental process, and retain a recoverable baseline and traceable facts. Follow its rewrite/merge checks; do not automatically launch it on save. Pure expression changes do not require successor decisions.

## Practical StrictDoc reference

- The bundled layout is one project under `docs/`: `strictdoc_config.py`, `project_memory/{decisions,journal}.sdoc`, and `handbook/`. Adapt to an existing project's layout rather than assuming an empty directory.
- `assets/docs-skeleton/`, relative to this skill, provides a starting point. Add missing pieces without overwriting existing docs or config. `migrate-mem` covers onboarding an already-developed project.
- The decision grammar supports `UID`, `STATUS`, `TITLE`, `STATEMENT`, optional `RATIONALE`, and relations. Plain journal `[TEXT]` nodes do not automatically support decision fields such as `STATUS`.
- When a successor decision is useful, it can carry the relation below, pointing to the old UID; mark the old decision `Superseded`. The reverse relation is `SupersededBy`:

  ```text
  RELATIONS:
  - TYPE: Parent
    VALUE: DEC-TOPIC-001
    ROLE: Supersedes
  ```

- Markdown rendering is enabled by `OPTIONS:` followed by indented `MARKUP: Markdown`. Sections use `[[SECTION]]` / `[[/SECTION]]`; stable UIDs belong on content nodes, not `[DOCUMENT]` headers. Inspect the project's actual grammar when adding fields.
- Validate `.sdoc`, grammar, or config changes with `strictdoc export .` from the docs root. Use the available executable or project environment; no particular environment manager or hard-coded version is assumed. Report a missing validator or failed export honestly and resolve it before calling the document update complete.
- Keep secrets out of stored/exported content; names and references to secret locations usually suffice. Respect the project's existing rules for version control and preservation of historical nodes.
