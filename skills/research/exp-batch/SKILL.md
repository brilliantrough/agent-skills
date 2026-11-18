---
name: exp-batch
description: Execute one bounded research experiment branch in the current session. Use when explicitly requested, or for a single coherent batch of runs with known configuration (one method × dataset × budget, or one ablation branch of a campaign). Prefer exp-discuss while the idea is fuzzy, exp-campaign for staged pruning across branches, exp-probe for a one-off check.
---

# Exp Batch: confirm necessity → clarify config → preflight → run → land metrics

Small but complete: one branch, done right, plottable. Stay inside this branch, and keep its rigor at full strength.

Apply `goal-first`: run what supports the learning question, Pareto/ablation coverage, agreed scientific claim or a live decision. Stop when that purpose and required coverage are satisfied; report incidental findings instead of expanding the batch for them. A scientifically needed matrix can be large.

## 1. Confirm the branch is still necessary

- Check project memory, the campaign plan, and existing results: has a probe already pruned this branch? Is the metric already measured under an equivalent configuration? If yes, say so and stop, or record why the earlier pruning does not apply.
- Restate in 2–3 sentences: what this batch adds to the final table/figure, which cells it fills, and its acceptance metric. No plan document.
- For a new algorithm branch, use `exp-workflow` to propose and agree the evidence route: an existing result, a proxy, or a direct exploratory/confirmatory matrix. Propose the route yourself rather than asking the researcher to invent the study. A costly full-model run needs code-readiness evidence; a prior proxy or positive result is optional.

## 2. Grill only unresolved config decisions

- Facts (paths, device availability, cache locations, prior configs) are yours to inspect. Ask the user only for choices that change the scientific meaning: hyperparameters not pinned by protocol, seed count, which split, callback-vs-reload coverage, formal vs exploratory status.
- Keep the batch's **metric contract identical to sibling runs**: same splits, same metric definitions, same surfaces. A batch measured differently cannot share a figure with the others, so flag any deviation explicitly in the record.
- Ask one round of structured questions; a second round is allowed only when an answer opened a new scientific choice. If config decisions multiply, the work is a campaign: propose `exp-campaign`.

## 3. Preflight: environment and resources

Run this pass before every launch, probe or formal, long or short. It takes seconds and needs no approval. Skipping ceremony means no scaffolding and no extra approval rounds; the live device read stays.

- **Environment:** interpreter/environment activation, working directory, the dependency versions that are importable now, input paths present, output and checkpoint directories writable.
- **Platform:** use the device platform that project memory, conventions, or the session already names (CUDA / Ascend / MUSA / PPU-class / …). If it is unknown, read it off the environment (installed toolkit, device files, what the project's own launcher sets) or ask once, then work in that platform's own tools and variables.
- **Live resources:** read the current device state with the platform's monitor (`nvidia-smi`, Ascend's `npu-smi`, MUSA's `mthreads-smi`, or the equivalent) for utilization, memory, and **which process owns each device**. Other people's jobs and this project's parallel branches both count. Choose from that read and pass the device explicitly through the platform's visible-device variable (`CUDA_VISIBLE_DEVICES`, `ASCEND_RT_VISIBLE_DEVICES`, `MUSA_VISIBLE_DEVICES`, …) so no run falls through to the default device. Check disk for checkpoints/logs, and RAM/CPU when the job is not device-bound, in the same look.
- **Collisions:** leftover jobs from earlier attempts and sibling branches are the usual hidden claim on a card; owner, name, and elapsed time in the process list settle it.
- **Cost:** estimate the whole batch (shared loading, per-configuration preparation/compilation/scoring, repeats), not one short run. A small dataset can still multiply costly loading or slow evaluation across many configurations.
- **Batch/model readiness:** before a batch through the real-model evaluation path (small-dataset exploratory matrices included) or any costly run, follow `exp-workflow`: inspect with `pytorch-perf-tuning`, preserve semantics, check numerics and a tiny real-model path, and assess aggregate cost. Reuse valid evidence instead of retuning every cell. A cheap local one-off probe needs only its relevant checks.
- **Then run** under the project's rules on who launches what. If the free resources do not fit the configuration, hold the launch and state what is short, then pick between waiting, another device, or an agreed config change. A silently shrunk config breaks the metric contract.

## 4. Implement in this session, run under project conventions

- Implementation happens **here, in the same session**, after the researcher gives the go-ahead (fresh-session handoff is `exp-campaign`'s model). The researcher drives execution timing, and formal runs follow the project's rules on who launches them: the researcher runs them or grants explicit permission.
- **Module placement:** put each piece in the module it belongs to, and keep experiment-specific code inside the experiment's own directory with its predictable layout, so the experiment is findable by name. One consumer does not justify a shared abstraction; split into separate modules when sibling branches would otherwise contend on one file.
- **Loose coupling:** consume stable shared libraries through their existing interfaces, and leave shared internals free of batch-specific changes or branches. If an interface lacks something this batch needs, stop and escalate it to the researcher as a campaign-level decision.
- **Ponytail research code:** the minimum code that runs the batch correctly, with no speculative validation, "just in case" branches, or swallowed errors. On error, exit with the real error.
- Watch for this project class's known failure modes: OOM (yours or the machine's), NaN, checkpoint serialization, degenerate metric collapse (e.g. all-same-answer), and eviction, where a neighbour's job or the kernel takes the device mid-run. On failure, preserve the failing artifact/log, isolate minimally, and keep a failure-status row; a failed cell stays empty rather than holding an invented metric or a zero.
- **Separate environment from code before acting:** the exit code, the log's last lines, and a fresh device read (is my process still alive? who owns the device now?) tell an evicted job apart from a real bug. Suspect the environment first (device contention, full disk, stale cache, conflicting job) and change code only when the evidence says the code is wrong. An evicted run keeps its evidence, gets a free device chosen from the live read, and is requeued with the deviation recorded. Flag any config changed to fit the resources: it can break the metric contract with sibling runs.
- These shapes are the common pattern. Unforeseen failures are yours to handle on the spot: decide, preserve the evidence, and say what you did. A failure is always recorded as a failure.
- Negative results are results: record them with the same schema as successes. Report process completion, data/numerical QC, and scientific support separately; exit code 0 establishes only the first. Preserve retries as separate attempts; they are neither independent scientific repeats nor replacements for failed evidence.

## 5. Wait on long runs with `later` (delegated execution)

Long runs (device hours) neither hold the turn nor get polled in a loop.

- **Delegation is explicit.** "Run it and check the results" delegates execution. If the researcher has not delegated, offer it before launching: "this needs ~Xh; I can run it in the background and resume automatically with the `later` tool — delegate to me?" State that each turn will end with a `later` schedule until the batch lands.
- **Launch in the background** per project conventions (nohup/tmux/launcher), then call `later`: estimate the duration, add ~10% margin (5h run → schedule 5.5h), and write the prompt as a complete instruction to your future self: what to check, what to decide, what to run next.
- **End the turn** after scheduling; the `later` call is the last action of the turn. The scheduled prompt arrives as a user message and resumes the session with no human present. Chain wake-ups across runs: each one checks, decides, launches the next run, and schedules the next `later`.
- **A timer is an estimate, not a completion signal.** On wake-up, verify the run finished and succeeded before recording metrics. If it is still running, re-estimate the remainder from observed progress (log/epoch counters, current throughput; contention can stretch a planned 5h run to 7h) and schedule another `later` for that remainder plus margin. Repeat until the run finishes; there is no wake-up budget.
- If the host has no `later` tool, tell the researcher the expected duration and when to return, or follow the project's own waiting convention.
- Use `later` for these chains even where background-task completion wakes exist: training and batch jobs need the custom next-step prompt and duration margin that `later` carries. Background tasks suit completion-driven shell work and read-only investigation.

## 6. Land the metrics where figures can use them

- Every run lands in the shared results table with: id, config, split, surface, metrics, status, evidence path. Include every epoch/point recorded, not only the chosen one, and retain sample/config identities, pairing, and the independent unit the analysis needs. Use the existing schema/notes; do not start a second registry.
- Interpret support, valid negatives, and inconclusive outcomes with [evidence interpretation](../exp-workflow/references/evidence-interpretation.md). Bind conclusions to the actual input/code/metric versions. Return execution/QC defects to repair, weak controls to design, and unresolved mechanisms to discussion; none of these extends the batch automatically. Data figures can use `research-evidence` over this same results table.
- Before finishing, check that the results support the learning question or agreed comparison with consistent axes/metrics. Add measurements when response trends, Pareto/ablation coverage, or formal claims need them; skip additions whose only purpose is visual symmetry.
- **The batch report is mandatory, including for partial, blocked, or aborted work.** Write `<batch-or-stage>.report.md` beside the campaign plan (default `docs/experiments/<slug>.stage<N>.report.md`; a standalone branch goes in the project's experiment area) with: 完成情况总表 (per planned run/cell: 完成 / 部分 / 搁置 / 未动 + evidence path), the exact configs and commands that ran, what was not run and why, metric-contract deviations, failures and how they were handled (eviction / OOM / NaN), and what the campaign should reconsider. Every planned run appears in the table, and every result row comes from a real run.
- When this batch changes route status or key understanding, use `save-mem` to update the existing route record/profile with the report as evidence. Batch completion shows the batch ran; the hypothesis and parallel routes keep their own status. Report concisely in chat. This batch does not wake the planning session: the researcher brings the report back, so the file is what gets reviewed.
