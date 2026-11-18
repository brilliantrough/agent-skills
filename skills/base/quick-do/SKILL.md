---
name: quick-do
description: Execute small, well-understood changes directly in the current session with minimal ceremony. Use when explicitly requested, or automatically for localized fixes, mechanical edits, config tweaks and short scripts with clear behavior and a known verification path. Prefer steady-do when design, compatibility or acceptance decisions remain; plan-brief for a separate-session handoff.
---

# Quick Do: understand → do → verify

Apply `goal-first`: keep the requested outcome and smallest sufficient check in view. An incidental discovery is work only if it affects that outcome; a bounded edit stays bounded. No extra planning artifact.

## When this skill applies

- Small, well-understood changes with a known verification path: localized fixes, mechanical edits, config tweaks, short scripts.
- The user's explicit workflow choice wins; if the chosen one cannot fit the task, say why and ask before switching. Stuck on design, compatibility, or acceptance decisions → stop and propose `steady-do` (if unsure between quick and steady, use steady); a handoff to a separate session → propose `plan-brief`.
- These workflows govern requested development work; explanations and read-only questions need no workflow. Skill instructions are in English; replies and deliverables follow the user's language (Chinese by default).

## Do the work

- **User discipline first:** check any root AGENTS `user-discipline` block and apply relevant rules to this edit. A user invoking `discipline` requires immediate activation in the current work as well as the saved rule.
- Read the request, applicable project rules, and affected files before editing. Inspect relevant callers when changing shared behavior. Reuse unchanged context, keep the exact edit unit available, and reread it after a match failure instead of guessing another patch.
- **Look at the live site first (seconds, no approval):** env active, deps actually importable, files and callers as expected — one glance that prevents a whole round of avoidable errors. Skipping ceremony is the point here; skipping this look is not.
- Fix the root cause: grep the callers of what you touch and fix where all of them route through. A guard repeated in every caller is a bigger diff and leaves siblings broken.
- Take the obvious interpretation for ordinary implementation details. Ask at most one focused clarification on the quick path; if investigation reveals substantial ambiguity or risk, stop and propose `steady-do`.
- No plan documents, grilling sessions, or sub-agents. Use a todo only when the work or host instructions warrant it.
- Keep the smallest working change: reuse existing code, then stdlib/native features, then installed dependencies. No over-encapsulation, speculative abstractions, defensive boilerplate, redundant checks, or unrelated cleanup. Preserve necessary trust-boundary validation, security, accessibility, and data protection.
- Leave a clean tree: scratch scripts, probes, temporary tests, and outputs are deleted unless they become a minimal asset with a real consumer today.
- Before destructive or irreversible actions, show the impact and obtain explicit authorization. Permission to start does not permit overwriting secrets or changing unrelated environments.

## Verify and finish

- **Discipline check:** verify each applicable user-discipline rule against the actual change and report any violation.
- Run the smallest real execution path and reread the change; check the requested behavior, since a clean exit alone proves little. For documentation-only changes, inspect content and applicable format checks.
- Do not add tests, TDD, or verification scripts by default. Explicit user requests and mandatory project checks still apply.
- Report only what actually ran, and name its level: a static check, a successful load, and injected input are each weaker than end-to-end behavior. If execution is unavailable, state what remains unverified and the concrete user check.
- **Blocked is a legitimate outcome:** say so, name what is left and the exact check the user must run. Never fake completion or silently skip a step.
- Finish in one short line stating the change and verification status, including a blocker or required user check when present. Required product docs and project memory still apply.
