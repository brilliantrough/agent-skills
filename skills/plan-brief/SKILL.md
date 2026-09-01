---
name: plan-brief
description: Turn a complex, thought-through requirement into a detailed execution plan document plus a standalone launcher prompt for a fresh agent session. Use when the user provides a long requirement (in chat or a file) and wants a plan before execution, or mentions 执行计划 / 计划文档 / 新会话执行 / 交接 prompt. Grills missing details first (runtime env, paths, verification philosophy), applies ponytail taste, and never executes the plan itself.
---

# Plan Brief: requirement → grilled plan → clean-session prompt

One job: produce (1) a detailed execution plan document and (2) a copy-paste prompt that launches a FRESH agent session to execute it. You plan; you never execute. No execution sub-agents.

## Phase 0 — Absorb the requirement

- Read the raw requirement completely (chat text, or the file the user points at).
- Restate in 2-3 sentences: goal, scope, what "done" looks like.
- Split it into: explicit requirements vs open details. Do NOT plan yet.

## Phase 1 — Survey the project

- Skim directory structure, AGENTS.md/README, entry points, and everything the requirement touches.
- Establish: what exists, its current state, which conventions the project already follows (env managers, doc locations, run commands).

## Phase 2 — Grill the details

Invoke the `grilling` skill (or `grill-with-docs` in memory-stack projects). The requirement never contains enough detail — interview the user, one question at a time, until every step of the plan is unambiguous. ALWAYS cover:

- **Runtime environment**: exact interpreter and env (venv/conda path + activation command), env vars, working directory, package manager, versions. NEVER assume system python.
- **Inputs/outputs**: formats, paths, expected artifacts.
- **Execution order**: dependencies between steps, what is parallelizable.
- **Conventions**: where outputs, docs, and configs live in this project.
- **Verification mode (mandatory decision — pick ONE and justify in one line)**:
  - **TDD mode** — only when the feedback loop is fast and tests are cheap: frontend/UI, product services, library code with instant unit tests. Invoke the `tdd` skill.
  - **Smoke-and-read mode** (default for research/exploration) — long-running or heavy-compute work (model training, data pipelines, experiments, one-off scripts). NO pytest, NO test scaffolding, NO wrapper harnesses: the run itself is expensive, so tests are 入不敷出. Verification = a short smoke run that exits without errors + the agent re-reads its own code to confirm the semantics are right + the user runs the real workload afterwards.
  - Rule of thumb: if writing/running the test costs more than the failures it would catch, don't write it.

## Phase 3 — Set the taste

Invoke `ponytail` if installed; otherwise apply these rules directly: minimum code that works. No over-encapsulation, no defensive programming, no redundant re-validation, no speculative abstraction. Functional code that runs correctly is DONE. Plan the lazy path.

## Phase 4 — Write the plan document

One Chinese markdown document, structured (tables for comparisons/params, lists for steps — no heading + wall of text), saved to the project's working-doc location (default `docs/plans/YYYY-MM-DD-<slug>.md`; confirm the location during grilling). Sections:

1. **目标与范围** — the Phase 0 restatement
2. **现状** — what exists now; Phase 1 findings
3. **环境与前提** — exact activation commands, env vars, versions
4. **执行步骤** — ordered; each step: what / command / expected result
5. **注意事项与已知坑** — everything surfaced in grilling
6. **验证方式** — name the chosen verification mode (TDD / smoke-and-read) and why; per the Phase 2 discussion; who runs what at the end
7. **交付物清单** — including the development report path: `docs/plans/YYYY-MM-DD-<slug>.report.md` (same slug as this plan)

## Phase 5 — Write the launcher prompt

Append it to the plan doc inside a fenced block AND print it in chat for copying. It must be fully self-contained for a clean session:

- Point to the plan doc path; instruct the new agent to read it plus AGENTS.md/project docs before acting.
- Hard constraints: activate the specified env before running anything; follow the plan's step order; ponytail taste; no scope creep; stop and ask when the plan is ambiguous; report results per the verification section.
- **Development report (mandatory, even for partial work)**: when done — or when stopping — write `docs/plans/YYYY-MM-DD-<slug>.report.md` (Chinese, structured) with sections: 完成情况总表 (per plan step: 完成/部分/搁置/未动 + evidence) / 做了什么 / 没做什么与搁置原因 / 规范遵循情况 / 特殊处理与偏离 / 遗留问题与建议.
- **Partial completion is legitimate**: steps blocked by real constraints (missing deps, env limits, out of scope) may be shelved — never fake completion, never silently skip. The report must say exactly what was and wasn't done.
- State the deliverables.

## Review loop (审查闭环)

When the user returns saying the executor finished (or drops the report path), audit — do not re-explore the codebase from scratch:

1. Read the plan doc and the report side by side. Spot-check the code only where claims need evidence.
2. Build a 核对表: per plan step — report claim vs evidence vs verdict (符合/存疑/不符).
3. Audit 规范遵循: env activation, step order, ponytail taste, test-script restraint.
4. Judge each deviation/特殊处理: reasonable or should be reverted, with why.
5. Verdict: 符合 / 部分符合 / 不符合, then concrete prioritized 修改意见 (minimal fixes, ponytail style).
6. Write the review to `docs/plans/YYYY-MM-DD-<slug>.review.md` (never edit the executor's report — it is their artifact) and print it in chat.
7. If fixes are needed, produce a new self-contained launcher prompt (Phase 5 rules) re-dispatching exactly the fix items to a fresh session.

## Hard boundary

When plan + prompt are delivered, the planning job is DONE for now. Do not execute the plan here. Do not spawn execution sub-agents. The user launches the fresh session themselves; this session's next role is reviewer (see Review loop).
