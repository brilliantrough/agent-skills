---
name: steady-do
description: Develop ordinary features, plugins and cross-module changes in the current session. Clarify open decisions, implement and verify; when asked to execute an agreed plan start at implementation. Use quick-do for bounded changes and plan-brief for large frameworks, long migrations or a durable multi-stage plan.
---

# Steady Do: understand → clarify → implement here → verify

Apply `goal-first`: anchor work to the agreed outcome, current uncertainty, next useful action and stopping condition. Recheck on surprises or scope/cost growth; finish the full requirement, not every improvement discovered along the way.

## When this skill applies

- Ordinary feature, plugin, extension, and cross-module work in an existing project, implemented and verified in this session.
- The user's explicit workflow choice wins. Bounded and clear → `quick-do`; a large framework or migration needing a durable staged plan → [plan-brief](../plan-brief/SKILL.md). Do not turn ordinary implementation into a planning-only handoff.
- **An agreed plan plus an instruction to execute:** read the plan and project instructions, verify the baseline, prerequisites and task endpoint, then start at step 3. Use the plan's decisions, verification and deliverables; ask only if a changed premise affects them. Merely writing or approving a design is not an instruction to implement it.
- These workflows govern requested development work; explanations and read-only questions need no workflow. Skill instructions are in English; replies and deliverables follow the user's language (Chinese by default).

## 1. Understand the request and project

- **User discipline first:** check any root AGENTS `user-discipline` block, apply relevant rules to scope and design, and immediately activate a newly invoked rule in the current plan and related work.
- Read the complete requirement and the decisions already settled in this conversation. Separate explicit requirements from open questions; establish the task baseline and distinguish existing user work before modifying files.
- If a proposed fix keeps recurring or two interpretations would pass the same check, use `problem-framing` to find a case that separates them. Carry the resulting behavior into acceptance; skip framing when the contract is clear.
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
- Keep the critical path and integration in this session; default to single-agent implementation. For two or more substantial independent branches or an explicit multi-agent request, use [multi-agent](../multi-agent/SKILL.md) and follow its mandatory guide for investigation or implementation. Use direct tools for short lookups; do not redo a worker’s search while waiting.
- For a source investigation, include the tool route in the handoff: native Glob for paths, Grep for text, Read for the relevant block (Pi: find/grep/read). If the path is known, start with Read; stop once the evidence answers the question.
- For ordinary development, use the session todo without a plan, launcher or separate report. When executing someone’s plan, deliver the evidence and artifacts it calls for.
- Run the project's agreed audits and checks, then continue to the task endpoint without asking about each covered action. A request to open a PR stops short of merge. Neither endpoint requires multiple workers.
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
- Standard quality is the default: after implementation load and execute [`unslop-changes`](../unslop-changes/SKILL.md), separately inspecting the authorized diff, including a user draft explicitly placed in scope. Reading the skill alone is not cleanup.
- After final checks, load [`verification`](../verification/SKILL.md) and call the independent `verification-reviewer`. Do not run the same cleanup twice for explicit consolidation.
- Run the real behavior check after Unslop and before the Reviewer, even if cleanup changes nothing; a check run before Unslop does not replace it.
- An explicitly selected light tier skips the separate Unslop and Reviewer for low-risk work; stronger project rules and high-risk review still apply.
- A single-file security boundary is still high-risk: untrusted filesystem paths, traversal, or symlink escape require `verification-reviewer` even when light quality is selected. If review is unavailable, disclose it as incomplete.
- Run the smallest real execution path, then reread the change and the adjacent behavior it touches. Check the agreed observable outcome, since a clean exit alone proves little. For documentation-only changes, inspect content and applicable format checks.
- Check the source contract before expensive generation or broad validation: pin the relevant source/version and verify meanings, shapes, state transitions or parameter order against that source rather than against tables your own code produced. Validate a representative vertical slice before scaling out; the final agreed coverage still applies.
- When review is warranted, provide the baseline, changed scope, evidence paths and unresolved questions together. Stabilize shared components before repeated per-item reviews; re-review changed items and affected dependents, unless the agreed full review is required. Distinguish semantic defects from environment defects before regenerating artifacts.
- New features in either tier need a minimal executable regression in the existing gate; reuse existing coverage. Other changes do not add tests or TDD by default. Do not modify files the user excluded; report a required coverage gap instead.
- Name the level of what ran: static check, successful load, local call, injected input, or complete user interaction. A loadable plugin is weaker evidence than a working feature, and injected input is weaker than a physical terminal interaction.
- If execution needs the user's environment or is blocked, state what remains unverified and give concrete steps and expected observations. **Blocked is a legitimate outcome:** say so with the exact check the user must run. Never invent completion or silently omit blocked work.
- Report what changed, what actually ran, and what needs user confirmation. Use one line only when it preserves all three.

## 6. 长程与无人值守

用户明确说“做到完成”“我离开一会儿”“跑到绿”时，把任务当成一次有出口条件的运行，而不是把提问权留给自己。

- **先把出口写成一个可判定的谓词**：测试全绿、复现消失、N 个 PR 全部合入、pixel-diff 为零。谓词写在会话里，**不放松它以宣布胜利**。
- **注册唤醒**：时长已知用 `later` 把下一步指令发回本会话；宿主支持后台 shell／子任务时用它，结束时报告 running 与日志位置。不 sleep、不轮询。
- **每轮只做证据支持的最小改动**，按谓词验证：推进了就保留并提交，没推进就丢弃，不留“可能有用”的护栏。一个工作单元一个绿灯，不把检查堆到末尾。
- **途中发现**：支撑当前目标的能力缺口、坏掉的检查、登记漂移自己修，必要时单独提交；只有不可逆动作、产品取舍和真正的死路才交回用户，可回退的事不用提问工具。
- **每轮一行记录**：追加到本地 `decisions.tsv`（时间、阶段、决定、原因、证据指针、结果），只记决策点和检查点，不记每个动作；默认不入库，需要复核时才提交。交接前按记录回看真实发生的事，不按记忆补写。
- **停的条件**：谓词满足；或同一阻塞连续多轮无进展，把问题交回用户。平台期不是停的理由，原地旋转也不是进展。
