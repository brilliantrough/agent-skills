---
name: steady-do
description: Develop features in an existing project within the current session. Use when explicitly requested, or automatically for ordinary feature, plugin, extension and cross-module work that needs project understanding and clarification before implementation. Prefer quick-do for clear, bounded changes; plan-brief when long-horizon work needs planning and separate-session execution.
---

# Steady Do: understand → clarify → implement here → verify

Apply `goal-first`: anchor work to the agreed outcome, current uncertainty, next useful action and stopping condition. Recheck on surprises or scope/cost growth; finish the full requirement, not every improvement discovered along the way.

## When this skill applies

- Ordinary feature, plugin, extension, and cross-module work in an existing project, implemented and verified in this session.
- The user's explicit workflow choice wins; if the chosen one cannot fit the task, say why and ask before switching. Bounded and clear → `quick-do`; long-horizon work needing a durable plan and a separate-session handoff → `plan-brief` (propose it when a handoff would help but was not requested).
- These workflows govern requested development work; explanations and read-only questions need no workflow. Skill instructions are in English; replies and deliverables follow the user's language (Chinese by default).

## 1. Understand the request and project

- **User discipline first:** check any root AGENTS `user-discipline` block, apply relevant rules to scope and design, and immediately activate a newly invoked rule in the current plan and related work.
- Read the complete requirement and the decisions already settled in this conversation. Separate explicit requirements from open questions; investigate before modifying files.
- Read project rules, README, relevant entry points and modules. Trace the real flow, reuse opportunities, affected callers, and compatibility boundaries. Expand by relevance: wider than a single function, narrower than a whole-repo tour.
- **Look at the live site first (seconds, no approval):** activation command and interpreter, dependency versions that actually import now, launch commands, input/output formats, config paths, and whether anything relevant is already running. Inspect the interpreter instead of assuming system Python. Skipping ceremony is the point; skipping this look is not.
- Briefly state the goal, scope, non-goals, and observable completion criteria in chat. Do not create a plan document.

## 2. Grill the unresolved decisions

Use the round-based method below; it is self-contained and needs no separate skill or document workflow.

- **Find facts yourself; ask the user for decisions.** Consult code, config, project memory, and docs first. For uncertain external APIs or platform limits, check upstream docs, source, or issues before stating a constraint.
- Ask only questions that affect behavior, scope, compatibility, risk, or acceptance. Give a recommendation and a brief trade-off for each. Resolve ordinary implementation details using project conventions.
- Group independently answerable questions in one round; defer questions that depend on unanswered ones. Use structured questions when available, otherwise numbered questions in chat, then wait for answers.
- After each round, recompute what its answers unblocked and ask the next round. Rounds continue while a further question would still change behavior, scope, compatibility, risk, or acceptance; stop when nothing material is left open, which may take more than one round or none at all.
- Skip settled questions. If the request and context already resolve the decisions, proceed to the recap.
- **Verification mode — mandatory decision; name it in the recap and justify it in one line:**
  - **TDD mode** — when explicitly requested or required by project policy; use the `tdd` skill and choose a seam that actually verifies the requirement.
  - **Smoke-and-read mode** (default for research, long-running, or heavy-compute work): the smallest real execution path + rereading your own change + checking the adjacent behavior it touches; the user runs the real workload afterwards. No test scaffolding, no wrapper harnesses.
  - Rule of thumb: if writing and running the test costs more than the failures it would catch, don't write it.
- **Acceptance and responsibility** — what is observed, the expected result, and who runs/verifies what at the end. Reuse an agreed verification approach instead of asking again.
- Grill what the current requirement needs: implementation-critical and acceptance-critical ambiguity. Future requirements and per-function design stay out.

## 3. Recap and implement here

- Briefly recap the agreed scope, approach, and verification, then begin without an extra plan-approval gate. If the recap introduces an unresolved material choice, wait for its answer first.
- Keep primary implementation in this session. When the investigation splits into substantial, independent evidence questions, delegate the read-only branches together and work on the critical path. Use direct tools for short lookups; do not redo a worker’s search while waiting.
- No plan documents, launcher prompts, development reports, or review reports. Track multi-step work with a session todo; required product docs and project memory still apply.
- Work in coherent units: keep current exact source plus callers/contracts available through the edit, group independent lookups, and reuse unchanged evidence. Reread the affected unit after a match failure instead of retrying from a summary. For generated or minified output, find the editable source and generation path first.
- If new evidence invalidates the agreed approach or requires broader scope or changed external behavior, pause the affected work and realign. Resolve ordinary local implementation issues yourself.
- Before destructive or irreversible actions, show the impact and obtain explicit authorization. Permission to start does not permit overwriting secrets or changing unrelated environments.

## 4. Keep ponytail taste

- Keep the smallest complete change that satisfies the agreed outcome: reuse existing code, then stdlib/native features, then installed dependencies. Do not add dependencies for simple problems.
- No over-encapsulation, speculative abstractions, defensive boilerplate, redundant checks, future scaffolding, or unrelated cleanup.
- Finish with a clean tree: scratch scripts, probes, temporary tests, logs and derived outputs either become a minimal real asset or are deleted. If a small detail is needed later, rebuild it then.
- Fix root causes along the real call chain; inspect sibling callers of shared logic.
- When the fix answers a repeated problem or a single costly mistake, read `trust-pyramid` and consider turning the spoken rule into an API shape, type, or check in the project's existing lint/check scripts.
- Preserve necessary trust-boundary validation, security, accessibility, data protection, and error handling that prevents data loss.

## 5. Verify and finish

- **Discipline check:** verify each applicable user-discipline rule against the actual change and adjacent behavior, and report any violation.
- Run the smallest real execution path, then reread the change and the adjacent behavior it touches. Check the agreed observable outcome, since a clean exit alone proves little. For documentation-only changes, inspect content and applicable format checks.
- Check the source contract before expensive generation or broad validation: pin the relevant source/version and verify meanings, shapes, state transitions or parameter order against that source rather than against tables your own code produced. Validate a representative vertical slice before scaling out; the final agreed coverage still applies.
- When review is warranted, provide the baseline, changed scope, evidence paths and unresolved questions together. Stabilize shared components before repeated per-item reviews; re-review changed items and affected dependents, unless the agreed full review is required. Distinguish semantic defects from environment defects before regenerating artifacts.
- Do not add tests, TDD, or verification scripts by default. Explicit user requests and mandatory project checks still apply.
- Name the level of what ran: static check, successful load, local call, injected input, or complete user interaction. A loadable plugin is weaker evidence than a working feature, and injected input is weaker than a physical terminal interaction.
- If execution needs the user's environment or is blocked, state what remains unverified and give concrete steps and expected observations. **Blocked is a legitimate outcome:** say so with the exact check the user must run. Never invent completion or silently omit blocked work.
- Report what changed, what actually ran, and what needs user confirmation. Use one line only when it preserves all three.
