---
name: save-mem
description: Preserve useful project knowledge through StrictDoc, Magic Context, and available memory tools, including overlapping storage where useful. Maintain readable current norms in StrictDoc; update them when a genuine decision change is clear and briefly inform the user, without routinely churning the canon. Ordinary memories and explanatory docs can evolve more freely. Favor concise phrases, lists, tables, and occasional PS explanations; choose storage, detail, and timing with judgment.
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
| claude-mem | Captured activity and searchable observations, where installed and capturing |

- Storing the same knowledge in StrictDoc and Magic Context is reasonable and often useful. Database entries can contain substantive knowledge, not just document pointers.
- Choose the amount of overlap and detail that helps future work. There is no requirement for every memory to have a document counterpart, or for every document to be mirrored in a database.
- Existing memories and relevant source files help avoid accidental duplicates and stale claims. `ctx_memory` supports writing, updating, merging, and archiving; use the operation that fits. Paths and UIDs are useful cross-references, not prerequisites for saving.
- Missing tools need not stop the other stores from being useful. Be clear about any important knowledge that remains unsaved or unverified.
- A project's **vocabulary and domain model** are memory too: `domain-modeling` is the skill for changing them (challenging terms, glossary entries, hard-to-reverse decisions). Land its output in this project's own layers — the glossary in StrictDoc's handbook (or a `CONTEXT.md` where the project already uses one), hard-to-reverse decisions as `project_memory/decisions.sdoc` nodes rather than a second parallel decision tree.

## Keep current truth distinguishable from history

**StrictDoc is the source of truth for current project norms when records disagree.** Magic Context and claude-mem may legitimately contain earlier or conflicting accounts; useful overlap does not imply equal authority for every historical statement.

- Keep current rules and their scope easy to identify. In the bundled grammar, decisions use `Active`, `Proposed`, `Deprecated`, or `Superseded`; dated journal entries describe experience rather than policy.
- **Active norms are maintainable, but historical nodes are not erased.** When the user changes a decision, or a settled change is clear from the conversation and evidence, add a successor when useful, mark the old node `Superseded`, and briefly tell the user. Do not change the canon for guesses, temporary experiments, or every task. Ordinary explanatory docs and non-normative memories may be revised more freely.
- Keep meaningful decision changes understandable. A journal note, revision context, or successor decision may preserve what mattered about the previous approach; choose the lightest suitable form rather than requiring a new node for every edit. Follow any project-specific history-preservation rules.
- Capture the reason when known: evidence, constraints, alternatives, or the user's intent. An unknown reason is better acknowledged than invented.
- Distinguish accepted decisions, observed behavior, pending work, and unverified claims. A working implementation may still differ from the intended rule.
- Where useful, reconcile known stale database claims and link related records. This does not call for auditing every store on every save.

## Human-readable writing

Before drafting or revising memory prose, load `readable-docs` for the shared project writing style. It applies to all human-facing technical records, not only memory: Chinese by default, phrases, lists, and compact tables without losing facts or conditions.

- For history, preserve outcomes, evidence, lessons, and remaining questions rather than a tool-by-tool diary. Link to original detail when useful.
- Distill readable current guidance; preserve original evidence and historical nodes instead of rewriting them merely for style.

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
