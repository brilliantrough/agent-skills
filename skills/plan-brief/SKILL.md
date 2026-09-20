---
name: plan-brief
description: Plan long-horizon, multi-stage development for a separate execution session with ponytail taste. Use when explicitly requested, or when the user wants a durable execution plan, a handoff prompt, or review of a prior plan's execution report. Investigate and clarify decisions, write the plan and launcher prompt, then review the executor's report later; never implement here. For complex work without a requested handoff, propose this workflow rather than silently deferring execution. Prefer steady-do for implementation in this session and quick-do for clear, bounded changes.
---

# Plan Brief: understand → clarify → plan → hand off → review

## Choose the workflow

- An explicit user choice takes precedence. Do not silently switch workflows; if the chosen one cannot safely fit the task, explain the mismatch and ask about the necessary adjustment.
- Without an explicit choice: use `quick-do` for clear, bounded changes; `steady-do` for ordinary feature work or unresolved design decisions; `plan-brief` for long-horizon work needing a durable plan and separate-session execution.
- Judge by uncertainty, coupling, risk, and handoff needs, not prompt length or file count. If unsure between quick and steady, use steady. If a handoff would help but was not requested, propose it before changing who executes; complexity alone does not authorize a handoff.
- These workflows govern requested development work, not every explanation or read-only question. Skill instructions are in English; replies and deliverables follow the user's language (Chinese by default).

Your job is a detailed execution plan and a self-contained launcher prompt for a fresh session, followed by review when the user returns. No implementation or execution sub-agents here.

## 1. Understand the request and project

- Read the complete requirement and decisions already settled in this conversation. Restate the goal, scope, non-goals, and observable completion criteria in 2-3 sentences; separate explicit requirements from open questions.
- Read project rules, README, relevant entry points, and affected modules. Establish existing capabilities, reuse opportunities, real call chains, compatibility boundaries, and project conventions before designing the plan.
- Investigate the facts yourself using code, config, memory, and docs. Check upstream docs, source, or issues for uncertain external APIs and platform limits rather than inventing constraints.

## 2. Grill the unresolved decisions

Use the bounded, round-based grilling method below; it is self-contained and does not require a separate skill or extra document workflow.

- Ask only unresolved decisions that affect scope, behavior, compatibility, risk, execution dependencies, or acceptance. Give a recommendation and brief trade-offs; do not ask the user for facts you can inspect.
- Group independently answerable questions in one round; defer dependent questions until their prerequisites are settled. Use structured questions when available, otherwise numbered questions in chat, then wait for answers.
- Do not repeat settled questions, invent a quota, or assume every requirement is incomplete. Stop when the plan's execution-critical and acceptance-critical decisions are resolved and understanding is shared.
- Establish the following where relevant, from investigation or user decisions:
  - **Environment:** interpreter, environment activation, working directory, package manager, required versions and env var names. Never assume system Python; reference existing secret locations without copying credentials into the plan.
  - **Inputs and outputs:** formats, paths, expected artifacts, and compatibility constraints.
  - **Execution order:** dependencies, milestones, and genuinely independent work.
  - **Document location:** the project's working-doc directory; default `docs/plans/YYYY-MM-DD-<slug>.md`. Keep the report and review beside the plan with the same basename.
  - **Verification:** what runs, the observable expected result, cost and environment limits, and who verifies what.
- Default to **smoke-and-read**: the smallest real execution path plus code rereading and checks of relevant adjacent behavior. For documentation-only work, use content review and applicable format checks. Do not add tests, TDD, or verification scripts by default; follow explicit user requests and mandatory project checks. Invoke `tdd` only when TDD is requested or required, not merely because the task is frontend or library code.
- Briefly recap the agreed scope, approach, and verification, then write the plan without an extra approval gate. If the recap introduces an unresolved material choice, wait for its answer first.

## 3. Keep ponytail taste

- Plan the smallest working change: reuse existing code, then stdlib/native features, then installed dependencies. No over-encapsulation, speculative abstractions, defensive boilerplate, redundant checks, future scaffolding, or unrelated cleanup.
- Fix root causes along real call chains and account for sibling callers of shared logic. Preserve necessary trust-boundary validation, security, accessibility, data protection, and error handling that prevents data loss.
- Include authorization gates for destructive or irreversible operations; permission to execute the plan is not permission to overwrite secrets or change unrelated environments.

## 4. Write the plan

One structured Markdown document in the user's language: tables for comparisons and parameters, lists for steps, no walls of text. Sections:

1. **Goal and scope:** agreed outcomes and non-goals.
2. **Current state:** relevant existing code, behavior, and reuse points.
3. **Environment and prerequisites:** exact known commands, paths, versions, and unresolved external blockers clearly labeled.
4. **Execution steps:** ordered actions, relevant files or commands, expected results, and dependencies. Do not invent commands or API details that were not verified.
5. **Constraints and known pitfalls:** compatibility, risks, and necessary authorization gates.
6. **Verification:** agreed approach, concrete acceptance evidence, and responsibilities. Distinguish static checks, loading, local calls, and real user interaction; never treat lack of errors as proof of the full outcome.
7. **Deliverables:** include `<plan-basename>.report.md` beside the plan. Required product docs and project memory still apply.

## 5. Write the launcher prompt

Append a fenced prompt to the plan AND print it in chat for copying. It must be self-contained for a fresh session:

- Point to the plan; instruct the executor to read it, project rules, and relevant project docs before acting.
- Carry the agreed scope, environment, step dependencies, ponytail taste, verification, authorization gates, and deliverables. Follow the plan rather than restarting workflow selection and grilling settled decisions.
- Stop affected work and ask when the plan is ambiguous, new evidence invalidates it, or scope must change. Resolve ordinary local implementation details without repeated approval.
- **Development report is mandatory, even for partial work:** write `<plan-basename>.report.md` beside the plan, in the user's language. Include a per-step status/evidence table (complete / partial / blocked / not started), changes made, work omitted and why, convention compliance, deviations, and remaining issues.
- Report only actual evidence. Separate static checks, successful loading, injected input, and end-to-end user behavior. If blocked or dependent on the user's environment, give concrete remaining checks and expected observations; never fake completion or silently skip steps.

## Review loop

When the user returns with the executor's completion or report:

1. Read the plan and report side by side. Spot-check implementation and claimed evidence where needed; do not re-explore the entire project by default.
2. Build a per-step table: report claim, evidence, and verdict (conforms / uncertain / does not conform).
3. Audit environment use, step dependencies, scope, ponytail taste, agreed verification, and necessary authorization. Judge deviations with reasons rather than treating every deviation as wrong.
4. Give an overall verdict (conforms / partially conforms / does not conform), followed by prioritized minimal fixes.
5. Write `<plan-basename>.review.md` beside the plan in the user's language and present the review in chat. Never edit the executor's report.
6. If fixes are needed, provide a self-contained launcher prompt for exactly those fixes, preserving the same reporting and verification obligations.

## Hard boundary

After delivering the plan and prompt, wait for the user to launch the execution session. Do not implement here or spawn execution sub-agents. This session's next role is reviewer unless the user explicitly changes the workflow.
