---
name: plan-brief
description: Plan large frameworks, migrations and multi-stage work, then execute the agreed plan on request in the current session or hand it off. Use for 制定计划、按计划执行、长程移植、跨会话交接、审查 report. Prepare independent slices when useful; one Agent can execute the whole plan. Use steady-do for daily development.
---

# Plan Brief: design the plan, then execute on request

Use a durable plan for a large framework, a migration, or work with consequential stage dependencies. For everyday development use [steady-do](../steady-do/SKILL.md).

## Choose the entry from the user's request

- **Plan.** Resolve the material decisions and write the plan. A request to plan, or agreement with the design alone, does not authorize implementation or execution workers. End a planning-only request with the plan path and “计划已就绪，尚未执行”.
- **Execute.** On “按这份计划执行” or “用 Multi Agent 执行这份计划”, enter [Execute an agreed plan](#execute-an-agreed-plan) in this session. A request to carry out an existing plan does not require authoring another one.
- **Hand off or review.** If the user wants another session or machine to execute, provide the [launcher](#separate-session-handoff). Review a returned report against its plan. Preparing a handoff does not launch it.

Apply `goal-first`: plan only work that delivers the outcome or resolves a decision-critical unknown. Put the budget, stopping conditions and treatment of incidental findings in the plan.

## Phase 0 — Absorb the requirement

- Read the raw requirement completely (chat text, or the file the user points at).
- Restate in 2-3 sentences: goal, scope, observable completion criteria, what "done" looks like.
- Split it into explicit requirements vs open details. Do NOT plan yet.
- If competing interpretations would lead to different plans, use `problem-framing` to settle the distinguishing case before choosing stages. Keep that case in the plan's acceptance criteria.

## Phase 1 — Survey the project

- Read project rules (AGENTS.md), including any `user-discipline` block as binding constraints; then read README, project memory and docs, entry points, and everything the requirement touches.
- Establish: what exists today, the real call chains, existing capabilities and reuse points, compatibility boundaries, and this project's own conventions (env managers, doc locations, run commands, who launches formal runs).
- Investigate the facts yourself from code, config, memory, docs, and upstream source/issues. Every command, API detail, and platform limit in the plan comes from something you inspected; ask the user for decisions, never for facts you can inspect.

## Phase 2 — Grill every open detail

Resolve the material details still missing after investigation. The round-based method below is self-contained:

- Ask only unresolved decisions that change scope, behavior, compatibility, risk, execution order, or acceptance; give a recommendation with brief trade-offs.
- Group independently answerable questions into one round; defer dependent ones until their prerequisites settle.
  - After each round, recompute what it unblocked and ask the next: rounds continue while a further question would still change a decision above.
  - Stop when nothing material is left open, which may take more than one round or none at all.
- Skip settled questions.

ALWAYS settle the following, from investigation or an explicit user decision:

- **Runtime environment** — exact interpreter and environment (venv/conda path + activation command), env var names, working directory, package manager, versions. NEVER assume system Python. Point at existing secret locations without copying credentials into the plan.
- **Inputs/outputs** — formats, paths, expected artifacts, compatibility constraints.
- **Execution order** — dependencies, milestones, genuinely independent or parallel work.
- **Document location** — the project's working-doc directory; default `docs/plans/YYYY-MM-DD-<slug>.md`. For a separate-session handoff, report and review live beside the plan.
- **Verification mode — mandatory decision; name it in one line in the plan and justify it:**
  - **TDD mode** — when explicitly requested or required by project policy; invoke the `tdd` skill and identify a meaningful verification seam.
  - **Smoke-and-read mode** (default for research, long-running, or heavy-compute work): the smallest real execution path + rereading your own code + checking the adjacent behavior it touches.
    - Reuse the project's checks; do not introduce another test harness for a smoke run.
    - The user runs the real workload afterwards.
  - Rule of thumb: if writing and running the test costs more than the failures it would catch, don't write it.
- **Acceptance and responsibility** — what is observed, the expected result, cost and environment limits, and who runs/verifies what at the end.

Recap the agreed scope, approach, and verification briefly, then write the plan without a separate approval gate — wait only if the recap introduced a new material choice.

## Phase 3 — Set the taste

- Plan the smallest complete change that satisfies the agreed outcome: reuse existing code, then stdlib/native features, then installed dependencies. No over-encapsulation, speculative abstraction, defensive boilerplate, redundant re-validation, future scaffolding, or unrelated cleanup.
- Choose the highest-value outcome and accept small recoverable rework. Plan a clean tree at the end: no speculative defenses, no preserved scratch artifacts; a small detail is re-added when a real need returns.
- Fix root causes along the real call chains and account for sibling callers of shared logic. Preserve trust-boundary validation, security, accessibility, data protection, and error handling that prevents data loss.
- Include authorization gates for destructive or irreversible operations. Permission to execute the plan does not permit overwriting secrets or changing unrelated environments.

## Phase 4 — Write the plan document

One structured Markdown document in the user's language (Chinese headings by default: 目标与范围 / 现状 / 环境与前提 / 执行步骤 / 注意事项与已知坑 / 验证方式 / 交付物清单). Tables for comparisons and parameters, lists for steps, no heading followed by a wall of text. Sections:

1. **Goal and scope** — the Phase 0 restatement, including non-goals.
2. **Current state** — what exists now and which parts get reused; Phase 1 findings.
3. **Environment and prerequisites** — exact known commands, paths, versions; unresolved external blockers labeled as such.
4. **Execution steps** — ordered; each step states what / the files or command / the expected result / its dependencies.
   - Before bulk generation or a broad matrix, settle source/version and semantic contracts, then validate a representative vertical slice and shared components.
   - Design for possible parallel work: settle shared contracts first; for each independent slice name its prerequisites, write scope, output and acceptance evidence. Name the integration step. For example: agree on the API → port two adapters independently → test them together. Keep coupled steps serial; a slice does not require a worker.
   - Write only verified commands and API details.
5. **Constraints and known pitfalls** — applicable user discipline, compatibility, risks, and the authorization gates from Phase 3.
6. **Verification** — name the chosen mode (TDD / smoke-and-read) and why; concrete acceptance evidence and who runs what. Name the level of each check: static check, successful loading, local call, or real user interaction; a clean exit alone proves little.
7. **Deliverables** — name the product and the requested endpoint (local verification, PR, or merge, as applicable). A separate-session handoff also requires `<plan-basename>.report.md`; same-session execution records results against the plan without a duplicate report unless requested.

## Execute an agreed plan

1. Read the named plan and applicable project instructions. Recheck the working tree, environment, stage prerequisites and current authorization where they could have changed. Keep settled decisions; reopen only the affected step if new evidence invalidates a premise.
2. Start [steady-do](../steady-do/SKILL.md) at implementation. The primary Agent owns the critical path and integration. Respect a request to work solo; otherwise use [multi-agent](../multi-agent/SKILL.md) when requested or independent branches warrant it. Proceed serially if none qualify or delegation is unavailable. Worktree and Git operations stay within the authorized endpoint.
3. Run the agreed checks on the integrated result; apply [verification](../verification/SKILL.md) when its triggers hold. In this session, record outcomes, evidence and blockers in the plan. Mark it done only when scope and verification are complete. In a separate-session handoff, write the report instead; the planning session closes the plan after review.

## Separate-session handoff

Append a self-contained launcher prompt to the plan inside a fenced block and print it in chat for copying:

- Point to the plan doc path; instruct the executor to read it plus AGENTS.md, including the active `user-discipline` block, and the relevant project docs before acting.
- Carry the agreed scope, environment, step order and dependencies, ponytail taste, verification mode, authorization gates, and deliverables. Follow the plan instead of restarting workflow selection or re-grilling settled decisions.
- Keep current constraints, evidence paths and the active edit unit in the existing todo/context; recover only missing or changed material. Read exact source before editing, refresh after a match failure, and edit the generator rather than giant generated output when a source path exists.
- Hard constraints: activate the specified environment before running anything; follow the plan's step order; no scope creep; stop and ask when the plan is ambiguous, new evidence invalidates it, or scope must change; resolve ordinary local implementation details without repeated approval.
- **Development report is mandatory — even for partial work:** write `<plan-basename>.report.md` beside the plan, in the user's language, with 完成情况总表 (per plan step: 完成 / 部分 / 搁置 / 未动 + evidence), 做了什么, 没做什么与搁置原因, 规范遵循情况, 特殊处理与偏离, 遗留问题与建议.
- **Partial completion is legitimate:** steps blocked by real constraints (missing dependencies, environment limits, out of scope) may be shelved. Never fake completion or silently skip; the report says exactly what was and was not done.
- Evidence honesty: separate static checks, successful loading, injected input, and real end-to-end behavior. If something depends on the user's environment, give the concrete remaining check and the expected observation.
- State the deliverables.

## Review loop (审查闭环) — when the user brings the report back

When the user returns saying the executor finished (or drops the report path), audit from the plan and report; a fresh survey of the project is not needed:

1. Read the plan doc and the report side by side. Spot-check the code only where a claim needs evidence.
2. Build a 核对表: per plan step — report claim / evidence / verdict (符合 / 存疑 / 不符).
3. Audit 规范遵循: active user discipline, environment activation, step order, scope, ponytail taste, chosen verification mode, authorization gates, test-script restraint.
   - Flag both defects and "should delete but remains": speculative defenses, temporary artifacts, duplicate implementations and unused compatibility paths.
   - Judge each deviation with its reason; fix the specific omission without recreating scaffolding.
4. Verdict (符合 / 部分符合 / 不符合), then concrete prioritized minimal fixes in ponytail style.
5. Write `<slug>.review.md` beside the plan in the user's language and print it in chat. NEVER edit the executor's report — it is their artifact.
6. If fixes are needed, prepare a self-contained handoff for exactly the fix items, pointing at the review file, plan and previous report. The user decides when and where to execute the fix.
   - Re-review changes and affected dependents using prior evidence for unchanged scope; repeat the full matrix only when required by the agreed acceptance or blast radius.
   - Separate source-semantic defects from verification-environment defects before ordering regeneration.
7. **Fix rounds keep their own artifacts:** the fix session writes `<slug>.report-2.md` (then `-3`, …), never overwriting an earlier report, and each round gets its own `<slug>.review-2.md` (…), so every round stays auditable.
8. **Exit:** a 符合 verdict closes the loop only when every required step and the agreed verification are complete. Record `Status: done (rounds: N)` at the top of the plan doc and update project memory/docs per project rules. If required work remains incomplete or unverified, keep the loop open with the exact remaining work; never write `done`.
   - If a round makes no progress on the same blocking item, stop and hand the open questions back to the user instead of looping again.

For a manually launched separate session, tell the user to bring back the report: handing them a launcher does not wire up a completion notification. Same-session native workers return to the primary Agent through the host instead.
