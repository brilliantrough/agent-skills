---
name: exp-campaign
description: Design research experiment matrices and staged campaigns for exploration, ablations, interactions, Pareto trade-offs and paper-quality evidence. Use for 实验矩阵、参数扫描、消融、帕累托前沿、论文实验 or multi-branch research. Choose proxy probes or direct matrices by information value and cost, preserve necessary coverage, and hand execution to exp-batch. A full matrix can be the right study; prevent purposeless expansion rather than matrices themselves. One bounded branch uses exp-batch; one check uses exp-probe; lifecycle coordination uses exp-workflow.
---

# Exp Campaign: research question → matrix/proxy design → evidence → review

Apply `goal-first`: **invest in the evidence the research needs.** Exploratory matrices can reveal the next question; ablation and Pareto matrices can be the main deliverable. A local proxy is optional, not a prerequisite or inherently superior evidence. Preserve necessary coverage while avoiding expansion with no learning or validation purpose.

## When this skill applies

- A direction that needs an exploratory sweep, ablations, interactions, Pareto fronts, paper validation or conditional staging. A matrix may be justified precisely because the next best configuration is unknown. One bounded execution branch is `exp-batch`; one missing datapoint is `exp-probe`; clarify an undefined research question with `exp-discuss`.
- The researcher's explicit choice wins; never switch silently. Judge by decision-tree depth and factor count, not by how long the experiments run (if unsure between probe and batch, use batch). Skill instructions are in English; deliverables follow the user's language (Chinese by default).

## 1. Observe before asking

- Read project memory, dashboards, past runs, logs, and previous conclusions. Establish what is already known, which baselines exist, which metrics are canonical, and what the current evidence does NOT cover.
- Restate the researcher's idea in 2-3 sentences: the claim to test, what a convincing final figure looks like, and what is out of scope. Separate explicit requirements from open questions.

## 2. Grill the researcher

Use bounded rounds of frontier questions — only what the settled decisions have already unblocked — each with a recommended answer; facts you can inspect are yours to find, never the researcher's. Recompute the frontier after each round of answers and ask the next round: the round count is not capped, and stopping is decided by whether a further question would still move scope, claim, or acceptance.

Ask about and surface, in frontier order:

- **The claim:** what exactly should the final plot/table show? Which comparison would change the researcher's mind?
- **The axes:** which factors matter (method, model, dataset, precision, seed, lr, …), and which levels per factor.
- **The matrix's purpose:** exploration, attribution or formal validation; for Pareto studies, define objectives, directions, constraints and comparable cost/quality measurements. Do not require a predicted winner or a separate decision for each cell.
- **Overlooked details the researcher may have missed:** evaluation split, calibration vs eval data leakage, callback-vs-reload metric consistency, seed variance, degenerate baselines (e.g., all-same-answer collapse), early/late checkpoint selection, and platform/numeric equivalence. Propose these explicitly; researchers under-specify them.
- **Budgets:** device hours, wall-clock deadline, storage; which runs are formal vs exploratory.
- **Acceptance:** what counts as success, tie, and negative result worth keeping.

Stop when execution-critical and acceptance-critical decisions are settled. Do not invent a question quota.

## 3. Design the study matrix and required coverage

Choose factors, levels, baselines and interactions for the learning question or paper claim. A complete matrix is legitimate when it reveals response patterns, estimates trade-offs or provides necessary coverage; a staged or reduced matrix is legitimate when it answers the same question. Judge the design as a whole, not by cell count. Label branches/cells:

- **must-run** — needed for exploration, ablation, Pareto coverage or the agreed formal claim, even if it cannot change today's implementation choice;
- **probe-decidable** — a cheap experiment can decide whether this whole row/column/branch is needed;
- **prunable** — already answered by existing evidence, or provably redundant (state the evidence).

Explain included coverage and material exclusions briefly. Do not prune a factor or interaction from one favorable proxy/point; formal baselines, repeatability and required curve coverage remain necessary even after finding a promising configuration.

## 4. Choose proxy observations or direct matrix evidence

Compare information value, validity and total cost. A bounded real-model matrix may provide clearer evidence than repeated ambiguous proxy studies; propose it directly when appropriate, with the researcher's agreed scope and the full-model code-readiness check:

- When a proxy can safely prune work, record the configuration, cost, observation and applicable scope of the pruning rule. A measured equivalence applies only to its supported conditions, not automatically the entire matrix.
- When the matrix is itself the study, record the patterns/trade-offs to inspect, analysis method, budget and stopping/confirmation rules; no preliminary proxy or per-cell predicted branch is required.
- Probes must themselves respect the project’s experiment conventions (preflight, run IDs, output layout). A probe that violates protocol teaches nothing safely.
- Borrow `exp-workflow` to co-design the evidence route. Small-dataset parameter/ablation matrices are valid pre-research; before batches through real-model evaluation, as well as costly runs, apply its PyTorch correctness/efficiency readiness check. Budget the whole batch and reuse valid evidence instead of retuning every cell.

## 5. Write the staged plan

One Markdown document, tables over prose:

1. **Claim and scope** — the scientific question, acceptance, budget and stopping conditions; table schema and requested figures. Every planned run must support the agreed claim or resolve a live decision, not merely occupy a cell or curve.
2. **Current evidence** — what is already measured, with pointers.
3. **Matrix and required coverage** from §3, including formal baselines, ranges, interactions and repeatability needed by the claim.
4. **Stages matched to the question:** after execution-path readiness, start with either a proxy or an exploratory matrix, then the necessary analysis/confirmatory matrix. A settled paper protocol may go directly to its scoped matrix. Specify commands, cost, observations, live-selected device resources and any real decision gates; do not fabricate preliminary studies. Every run still uses `exp-batch` preflight.
5. **Coverage and pruning ledger** — assumptions, included/omitted conditions, evidence and confidence; no requirement to prune a sound matrix.
6. **Failure handling** — what to do on OOM/NaN/inconclusive/**evicted** (a neighbour's job or the machine taking the card): capture evidence, isolate minimally, do not silently skip. Name these as the expected shapes, not the full space: unforeseen failures are decided on the spot and recorded as deviations, not escalated into a new process.
7. **Deliverables:** the plan file (project working-doc dir; default `docs/experiments/YYYY-MM-DD-<slug>.md`), one self-contained launcher prompt per stage (fenced in the plan AND printed in chat), the gate decisions recorded in the pruning ledger, the mandatory per-stage executor reports (`<slug>.stage<N>.report.md`, written by `exp-batch`), and a results-merge step into the shared dashboard/table.

## 6. Hand off and review

- **Execution happens in separate agent sessions, one per stage or branch.** Like plan-brief: the campaign delivers a self-contained launcher prompt per stage; a fresh session reads the plan, adopts `exp-batch`, and implements + runs that stage. Never execute the campaign inside the planning session.
- Each launcher prompt carries: the cells this stage must fill, exact configs/commands, the metric contract, stop conditions, and the gate observations to report back. The executor follows the plan rather than re-grilling settled decisions; it stops and asks when evidence invalidates the plan.
- **State the waiting arrangement in every launcher prompt.** Either the researcher has already delegated execution — say so explicitly ("you may launch runs and use the `later` tool to wait unattended") — or the executing agent must ask for delegation at stage start. With delegation and a host that provides the `later` tool, the executor runs long jobs in the background, schedules its own wake-up with ~10% margin (prompt written as a complete next-step instruction), and ends the turn; wake-ups chain until the stage's gate observations are collected, re-estimating from observed progress whenever a run overruns rather than trusting the original plan. This keeps multi-hour stages unattended; without it, the executor stops at every long run to wait for a human.
- **Who launches formal runs is the researcher's call**, not the plan's: the executing agent implements code and preflights; the researcher either runs formal commands themselves or grants execution permission explicitly. The plan must state which commands are formal.
- **When a stage's report returns, this session owns the next move** — the researcher is the courier, so do not wait for an automatic ping. Read `<slug>.stage<N>.report.md` (not chat memory), compare predicted vs observed at every gate, write the decision into the pruning ledger (`gate N: observed X → keep / skip cells …`), reopen the cells a failed probe assumption justified and say so loudly, then emit the stage N+1 launcher prompt, replacing the pre-written branch variant it supersedes.
- **Exit:** the campaign closes when every surviving cell has a row in the shared table and each figure in the figure list can be drawn from it. Then record `Status: done (stages: N)` at the top of the plan, state what was pruned and by which evidence, hand the negative results to the researcher, and stop opening branches. If a gate leaves the claim unresolved after the confirmatory stage, hand the open question back instead of adding stages.
- Route/gate changes that affect project understanding go through `save-mem` to the existing records and profile, linked to this plan and evidence rather than copied into a second ledger. Closing this campaign does not by itself resolve the whole research question or invalidate parallel routes.
- Final review: does the metrics table/figure set answer the original claim? Are negative results and config deviations visible? Publish to the shared dashboard with both callback and reload surfaces where they exist.
- For Pareto results, retain measured configurations and baselines, including dominated or unfavorable points; state metric directions and uncertainty where relevant. The empirical frontier supports claims within tested conditions, not guaranteed superiority everywhere. Use an appropriate confirmation protocol before treating an exploratory frontier as paper evidence.

## 7. Code organization (planned here, implemented by exp-batch)

The plan decides *where* code lives so every later branch lands consistently:

- **Module placement is a decision, name it:** which existing module each piece belongs in, what stays in the experiment's own directory. No new shared abstraction for a single consumer; but do separate concerns into separate modules when two branches would otherwise edit the same file in different ways.
- **Experiment directory isolation:** each experiment gets its own directory with a predictable layout, so a run can be found by name alone (scripts, configs, outputs mirror each other). Experiments never reach into another experiment's directory.
- **Loose coupling over convenience:** experiments consume stable shared libraries through their existing interfaces; an experiment must not modify shared internals to fit its needs, and shared libraries must not grow experiment-specific branches. If the shared interface genuinely lacks something, that gap is a plan-level decision, not a drive-by edit.
- **Ponytail research code:** the minimum code that runs the experiment correctly. **No defensive programming** — no speculative input validation, no "just in case" branches, no swallowed errors. On error, exit with the real error. Post-mortem decides whether the fix is code or environment (device contention, full disk, stale cache); often the code is already right.

## Hard boundaries

- Never present pruned space as "ran and failed"; pruned means "not run, because probe P showed X".
- Never let the plan claim equivalence of configurations without a measured comparison.
- A campaign plan is not permission to launch formal runs; follow the project's rules on who runs what.
