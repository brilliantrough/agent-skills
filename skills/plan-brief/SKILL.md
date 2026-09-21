---
name: plan-brief
description: Turn a complex, thought-through requirement into a detailed execution plan document plus a self-contained launcher prompt for a fresh agent session, and later review that session's report. Use when the user wants a plan before execution, wants execution handed to a separate session, or mentions 执行计划 / 计划文档 / 新会话执行 / 交接 prompt / 审查 report; also when reviewing a plan's execution report or dispatching a fix round. Grills what is still missing, applies ponytail taste, treats partial completion as legitimate, and never executes the plan itself. Prefer steady-do for implementation in this session and quick-do for clear, bounded changes.
---

# Plan Brief: requirement → grilled plan → launcher prompt → review (审查闭环)

**One job, three artifacts: (1) a detailed execution plan document, (2) a copy-paste launcher prompt that starts a FRESH session to execute it, (3) later, the review of that session's report.** You plan and review; you NEVER execute the plan and never spawn execution sub-agents.

Deliverables checklist — none of these may be skipped silently:

- [ ] plan doc `docs/plans/YYYY-MM-DD-<slug>.md` (the project's own working-doc dir if it differs)
- [ ] launcher prompt: fenced inside the plan doc AND printed in chat
- [ ] when the report comes back: `<slug>.review.md` beside the plan, plus a fix prompt if fixes are needed

## When this skill applies

- The user wants a durable execution plan, execution handed to a separate session, or a report reviewed / a fix round dispatched — the three artifacts above.
- The user's explicit choice wins; never switch workflows silently. In-session implementation is `quick-do` / `steady-do`; if a handoff would help but was not requested, propose it before changing who executes.

## Phase 0 — Absorb the requirement

- Read the raw requirement completely (chat text, or the file the user points at).
- Restate in 2-3 sentences: goal, scope, observable completion criteria, what "done" looks like.
- Split it into explicit requirements vs open details. Do NOT plan yet.

## Phase 1 — Survey the project

- Read project rules (AGENTS.md), README, project memory and docs, entry points, and everything the requirement touches.
- Establish: what exists today, the real call chains, existing capabilities and reuse points, compatibility boundaries, and this project's own conventions (env managers, doc locations, run commands, who launches formal runs).
- Investigate the facts yourself from code, config, memory, docs, and upstream source/issues. Never invent a command, API detail, or platform limit; ask the user for decisions, never for facts you can inspect.

## Phase 2 — Grill every open detail

The requirement never carries enough detail. Use this bounded round-based method directly — it needs no separate skill:

- Ask only unresolved decisions that change scope, behavior, compatibility, risk, execution order, or acceptance; give a recommendation with brief trade-offs.
- Group independently answerable questions into one round; defer dependent ones until their prerequisites settle. After each round, recompute what it unblocked and ask the next: rounds continue while a further question would still change a decision above. The stopping rule is "nothing material left open", not "one round done".
- Do not repeat settled questions, invent a quota, or assume every requirement is incomplete.

ALWAYS settle the following, from investigation or an explicit user decision:

- **Runtime environment** — exact interpreter and environment (venv/conda path + activation command), env var names, working directory, package manager, versions. NEVER assume system Python. Point at existing secret locations without copying credentials into the plan.
- **Inputs/outputs** — formats, paths, expected artifacts, compatibility constraints.
- **Execution order** — dependencies, milestones, genuinely independent or parallel work.
- **Document location** — the project's working-doc directory; default `docs/plans/YYYY-MM-DD-<slug>.md`. Report and review live beside the plan with the same basename.
- **Verification mode — mandatory decision; name it in one line in the plan and justify it:**
  - **TDD mode** — only when the feedback loop is fast and tests are cheap (frontend/UI, product services, library code with instant unit tests). Invoke the `tdd` skill.
  - **Smoke-and-read mode** (default for research, long-running, or heavy-compute work): the smallest real execution path + rereading your own code + checking the adjacent behavior it touches. No pytest, no test scaffolding, no wrapper harnesses — the run itself is the cost. The user runs the real workload afterwards.
  - Rule of thumb: if writing and running the test costs more than the failures it would catch, don't write it.
- **Acceptance and responsibility** — what is observed, the expected result, cost and environment limits, and who runs/verifies what at the end.

Recap the agreed scope, approach, and verification briefly, then write the plan without a separate approval gate — wait only if the recap introduced a new material choice.

## Phase 3 — Set the taste

Apply ponytail directly (spelling the rules out here is enough):

- Plan the smallest working change: reuse existing code, then stdlib/native features, then installed dependencies. No over-encapsulation, speculative abstraction, defensive boilerplate, redundant re-validation, future scaffolding, or unrelated cleanup.
- Fix root causes along the real call chains and account for sibling callers of shared logic. Preserve trust-boundary validation, security, accessibility, data protection, and error handling that prevents data loss.
- Include authorization gates for destructive or irreversible operations; permission to execute the plan is not permission to overwrite secrets or change unrelated environments. Functional code that runs correctly is DONE.

## Phase 4 — Write the plan document

One structured Markdown document in the user's language (Chinese headings by default: 目标与范围 / 现状 / 环境与前提 / 执行步骤 / 注意事项与已知坑 / 验证方式 / 交付物清单). Tables for comparisons and parameters, lists for steps, no heading followed by a wall of text. Sections:

1. **Goal and scope** — the Phase 0 restatement, including non-goals.
2. **Current state** — what exists now and which parts get reused; Phase 1 findings.
3. **Environment and prerequisites** — exact known commands, paths, versions; unresolved external blockers labeled as such.
4. **Execution steps** — ordered; each step states what / the files or command / the expected result / its dependencies. Do not invent commands or API details that were not verified.
5. **Constraints and known pitfalls** — compatibility, risks, and the authorization gates from Phase 3.
6. **Verification** — name the chosen mode (TDD / smoke-and-read) and why; concrete acceptance evidence and who runs what. Distinguish static checks, successful loading, local calls, and real user interaction; never treat absence of errors as proof of the outcome.
7. **Deliverables** — include `<plan-basename>.report.md` beside the plan. Required product docs and project memory still apply.

## Phase 5 — Write the launcher prompt

Append it to the plan doc inside a fenced block AND print it in chat for copying. It must be fully self-contained for a fresh session:

- Point to the plan doc path; instruct the executor to read it plus AGENTS.md and the relevant project docs before acting.
- Carry the agreed scope, environment, step order and dependencies, ponytail taste, verification mode, authorization gates, and deliverables. Follow the plan instead of restarting workflow selection or re-grilling settled decisions.
- Hard constraints: activate the specified environment before running anything; follow the plan's step order; no scope creep; stop and ask when the plan is ambiguous, new evidence invalidates it, or scope must change; resolve ordinary local implementation details without repeated approval.
- **Development report is mandatory — even for partial work:** write `<plan-basename>.report.md` beside the plan, in the user's language, with 完成情况总表 (per plan step: 完成 / 部分 / 搁置 / 未动 + evidence), 做了什么, 没做什么与搁置原因, 规范遵循情况, 特殊处理与偏离, 遗留问题与建议.
- **Partial completion is legitimate:** steps blocked by real constraints (missing dependencies, environment limits, out of scope) may be shelved — never fake completion, never silently skip. The report says exactly what was and was not done.
- Evidence honesty: separate static checks, successful loading, injected input, and real end-to-end behavior. If something depends on the user's environment, give the concrete remaining check and the expected observation.
- State the deliverables.

## Review loop (审查闭环) — when the user brings the report back

When the user returns saying the executor finished (or drops the report path), audit — do not re-explore the project from scratch:

1. Read the plan doc and the report side by side. Spot-check the code only where a claim needs evidence.
2. Build a 核对表: per plan step — report claim / evidence / verdict (符合 / 存疑 / 不符).
3. Audit 规范遵循: environment activation, step order, scope, ponytail taste, chosen verification mode, authorization gates, test-script restraint. Judge each deviation with its reason instead of assuming every deviation is wrong.
4. Verdict (符合 / 部分符合 / 不符合), then concrete prioritized minimal fixes in ponytail style.
5. Write `<slug>.review.md` beside the plan in the user's language and print it in chat. NEVER edit the executor's report — it is their artifact.
6. If fixes are needed, produce a new self-contained launcher prompt (Phase 5 rules) re-dispatching exactly the fix items; it must point at the review file, the plan, and the previous report.
7. **Fix rounds keep their own artifacts:** the fix session writes `<slug>.report-2.md` (then `-3`, …), never overwriting an earlier report, and each round gets its own `<slug>.review-2.md` (…), so every round stays auditable.
8. **Exit:** a 符合 verdict closes the loop — record `Status: done (rounds: N)` at the top of the plan doc, list anything still not done, and update project memory/docs per project rules. If a round makes no progress on the same blocking item, stop and hand the open questions back to the user instead of looping again.

Courier note: the return leg is user-mediated — this session is not woken by the executor and resumes only when the user brings the report back. Say so when handing off, so nobody waits for an automatic ping.

## Hard boundary

Once plan + launcher prompt are delivered, the planning job is DONE for now. Do not execute the plan here, do not spawn execution sub-agents, do not start a fix round yourself. The user launches the fresh session; this session's next role is reviewer (see Review loop).
