---
name: exp-campaign
description: Design research experiment matrices and staged campaigns for exploration, ablations, interactions, Pareto trade-offs and paper-quality evidence. Use for 实验矩阵、参数扫描、消融、帕累托前沿、论文实验 or multi-branch research. Hands execution to exp-batch. One bounded branch uses exp-batch; one check uses exp-probe; lifecycle coordination uses exp-workflow.
---

# Exp Campaign: research question → matrix/proxy design → evidence → review

Apply `goal-first`: **invest in the evidence the research needs.** Exploratory matrices can reveal the next question; ablation and Pareto matrices can be the main deliverable. A local proxy is one option among several. Preserve the coverage the question needs, and leave out expansion that serves no learning or validation purpose.

## When this skill applies

- A direction that needs an exploratory sweep, ablations, interactions, Pareto fronts, paper validation, or conditional staging.
  - A matrix may be justified precisely because the next best configuration is unknown.
  - One bounded execution branch is `exp-batch`; one missing datapoint is `exp-probe`; an undefined research question goes to `exp-discuss` first.
- The researcher's explicit choice wins; say so before switching skills. Judge by decision-tree depth and factor count, not by how long the experiments run (if unsure between probe and batch, use batch). Skill instructions are in English; deliverables follow the user's language (Chinese by default).

## 1. Observe before asking

- Read project memory, dashboards, past runs, logs, and previous conclusions. Establish what is already known, which baselines exist, which metrics are canonical, and what the current evidence does not cover.
- Restate the researcher's idea in 2–3 sentences: the claim to test, what a convincing final figure looks like, and what is out of scope. Separate explicit requirements from open questions.

## 2. Grill the researcher

Ask bounded rounds of frontier questions, meaning only what the settled decisions have already unblocked, each with a recommended answer. Facts you can inspect are yours to find. Recompute the frontier after each round and ask the next. There is no round cap or question quota: stop when a further question would no longer move scope, claim, or acceptance.

Ask about and surface, in frontier order:

- **The claim:** what exactly should the final plot/table show? Which comparison would change the researcher's mind? For explanatory claims, connect claim → competing explanation → discriminating control → interpretation; an ablation that also changes compute/data does not isolate a mechanism.
- **The axes:** which factors matter (method, model, dataset, precision, seed, lr, …), and which levels per factor.
- **Units and analysis:** define the experimental/observation units, pairing or clusters, and what counts as an independent repeat.
  - For confirmatory work, settle primary metrics, exclusions, stopping, and relevant multiplicity handling before inspecting outcomes, and label post-hoc changes.
  - Read [evidence interpretation](../exp-workflow/references/evidence-interpretation.md) when the design needs it.
- **The matrix's purpose:** exploration, attribution, or formal validation. For Pareto studies, define objectives, directions, constraints, and comparable cost/quality measurements. A matrix needs a purpose; it does not need a predicted winner or a separate decision per cell.
- **Details researchers under-specify:** evaluation split, calibration vs eval data leakage, callback-vs-reload metric consistency, seed variance, degenerate baselines (e.g. all-same-answer collapse), early/late checkpoint selection, and platform/numeric equivalence. Propose these explicitly.
- **Budgets:** device hours, wall-clock deadline, storage; which runs are formal vs exploratory.
- **Acceptance:** what counts as success, tie, and a negative result worth keeping.

## 3. Design the study matrix and required coverage

Choose factors, levels, baselines, and interactions for the learning question or paper claim. A complete matrix is legitimate when it reveals response patterns, estimates trade-offs, or provides necessary coverage; a staged or reduced matrix is legitimate when it answers the same question. Judge the design as a whole, not by cell count. Label branches/cells:

- **must-run**: needed for exploration, ablation, Pareto coverage, or the agreed formal claim, even if it cannot change today's implementation choice;
- **probe-decidable**: a cheap experiment can decide whether this whole row/column/branch is needed;
- **prunable**: already answered by existing evidence, or provably redundant (state the evidence).

Explain included coverage and material exclusions briefly. One favorable proxy or point is not enough to prune a factor or interaction; formal baselines, repeatability, and required curve coverage stay necessary after a promising configuration is found.

## 4. Choose proxy observations or direct matrix evidence

Compare information value, validity, and total cost. A bounded real-model matrix may give clearer evidence than repeated ambiguous proxy studies; propose it directly when appropriate, with the researcher's agreed scope and the full-model code-readiness check.

- When a proxy can safely prune work, record the configuration, cost, observation, and the scope the pruning rule applies to. A measured equivalence holds for its supported conditions only.
- When the matrix is itself the study, record the patterns/trade-offs to inspect, analysis method, budget, and stopping/confirmation rules. It needs no preliminary proxy and no per-cell predicted branch.
- Probes follow the project's experiment conventions (preflight, run IDs, output layout); a probe outside protocol cannot support a pruning decision.
- Use `exp-workflow` to co-design the evidence route.
  - Small-dataset parameter/ablation matrices are valid pre-research.
  - Before batches through real-model evaluation, and before costly runs, apply its PyTorch correctness/efficiency readiness check.
  - Budget the whole batch and reuse valid evidence instead of retuning every cell.

## 5. Write the staged plan

One Markdown document, tables over prose:

1. **Claim and scope:** the scientific question, acceptance, budget, and stopping conditions; table schema and requested figures. Every planned run supports the agreed claim or resolves a live decision.
2. **Current evidence:** what is already measured, with source/version pointers, conditions, and unresolved alternatives. Missing evidence is recorded as missing, not as a negative result.
3. **Matrix and required coverage** from §3, including the formal baselines, ranges, interactions, and repeatability the claim needs.
4. **Stages matched to the question:** after execution-path readiness, start with either a proxy or an exploratory matrix, then the necessary analysis/confirmatory matrix.
   - A settled paper protocol may go directly to its scoped matrix.
   - Specify commands, cost, observations, live-selected device resources, and the real decision gates; plan only the preliminary studies the question needs.
   - Every run still uses `exp-batch` preflight.
5. **Coverage and pruning ledger:** assumptions, included/omitted conditions, evidence, and confidence. A sound matrix may have nothing to prune.
6. **Failure handling:** what to do on OOM, NaN, inconclusive results, and eviction (a neighbour's job or the machine taking the card): capture evidence, isolate minimally, and record the run rather than skipping it.
   - These are the expected shapes; the executor decides unforeseen failures on the spot and records them as deviations.
7. **Deliverables:** the plan file (project working-doc dir; default `docs/experiments/YYYY-MM-DD-<slug>.md`), one self-contained launcher prompt per stage (fenced in the plan and printed in chat), the gate decisions recorded in the pruning ledger, the mandatory per-stage executor reports (`<slug>.stage<N>.report.md`, written by `exp-batch`), and a results-merge step into the shared dashboard/table.

## 6. Hand off and review

- Execution happens in separate agent sessions, one per stage or branch. As in `plan-brief`, the campaign delivers a self-contained launcher prompt per stage; a fresh session reads the plan, adopts `exp-batch`, and implements and runs that stage.
  - The planning session plans and reviews; it does not execute the campaign.
- Each launcher prompt carries: the cells this stage must fill, exact configs/commands, the metric contract, stop conditions, and the gate observations to report back. The executor follows the plan on settled decisions, and stops to ask when evidence invalidates the plan.
- State the waiting arrangement in every launcher prompt. Either the researcher has already delegated execution, in which case say so explicitly ("you may launch runs and use the `later` tool to wait unattended"), or the executing agent asks for delegation at stage start.
  - With delegation and a host that provides `later`, the executor runs long jobs in the background, schedules its own wake-up with ~10% margin (prompt written as a complete next-step instruction), and ends the turn.
  - Wake-ups chain until the stage's gate observations are collected, re-estimating from observed progress whenever a run overruns.
  - Without this arrangement the executor stops at every long run to wait for a human.
- Who launches formal runs is the researcher's call. The executing agent implements code and preflights; the researcher either runs formal commands or grants execution permission explicitly. The plan states which commands are formal.
- When a stage's report returns, this session owns the next move. The researcher is the courier and no automatic ping arrives.
  - Read `<slug>.stage<N>.report.md` rather than relying on chat memory, compare predicted vs observed at every gate, write the decision into the pruning ledger (`gate N: observed X → keep / skip cells …`), reopen the cells that a failed probe assumption had pruned and say so prominently, then emit the stage N+1 launcher prompt, replacing the pre-written branch variant it supersedes.
- **Exit:** the campaign closes when every surviving cell has a row in the shared table and each figure in the figure list can be drawn from it.
  - Then record `Status: done (stages: N)` at the top of the plan, state what was pruned and by which evidence, hand the negative results to the researcher, and stop opening branches.
  - If a gate leaves the claim unresolved after the confirmatory stage, hand the open question back instead of adding stages.
- Route/gate changes that affect project understanding go through `save-mem` into the existing records and profile, linked to this plan and its evidence rather than copied into a second ledger.
  - Closing the campaign settles this plan's scope; the wider research question and parallel routes keep their own status.
- Final review: does the metrics table/figure set answer the original claim? Are negative results and config deviations visible? Publish to the shared dashboard with both callback and reload surfaces where they exist.
- For Pareto results, retain measured configurations and baselines, including dominated or unfavorable points, and state metric directions and uncertainty where relevant.
  - The empirical frontier supports claims within the tested conditions.
  - Run an appropriate confirmation protocol before treating an exploratory frontier as paper evidence.

## 7. Code organization (planned here, implemented by exp-batch)

The plan decides where code lives so every later branch lands consistently:

- **Module placement:** name which existing module each piece belongs in and what stays in the experiment's own directory. One consumer does not justify a new shared abstraction; split concerns into separate modules when two branches would otherwise edit the same file in different ways.
- **Experiment directory isolation:** each experiment gets its own directory with a predictable layout (scripts, configs, outputs mirror each other), so a run can be found by name alone. Experiments stay out of each other's directories.
- **Loose coupling:** experiments consume stable shared libraries through their existing interfaces. Shared internals stay free of experiment-specific changes and branches; when the shared interface lacks something, that gap is a plan-level decision made here.
- **Ponytail research code:** the minimum code that runs the experiment correctly, with no speculative input validation, "just in case" branches, or swallowed errors.
  - On error, exit with the real error.
  - The post-mortem decides whether the fix is code or environment (device contention, full disk, stale cache); often the code is already right.

## Hard boundaries

- Pruned means "not run, because probe P showed X". Never present pruned space as "ran and failed".
- The plan claims two configurations equivalent only with a measured comparison.
- A campaign plan is not permission to launch formal runs; follow the project's rules on who runs what.
