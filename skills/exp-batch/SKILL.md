---
name: exp-batch
description: Execute one bounded research experiment branch in the current session with ponytail-for-experiments taste. Use when explicitly requested, or for a single coherent batch of runs with known configuration (one method × dataset × budget, or one ablation branch of a campaign). First check the branch was not already pruned or answered, grill only unresolved config decisions, run per project conventions, and land metrics in the shared table in a shape the final figures can use directly. Prefer exp-discuss when the idea is still fuzzy and needs talking through; prefer exp-campaign when the work needs staged pruning across branches; prefer exp-probe for one-off spot checks.
---

# Exp Batch: confirm necessity → clarify config → run → land metrics

Small but complete: one branch, done right, plottable. Do not expand scope sideways into other branches; do not shrink rigor to save time.

## 1. Confirm the branch is still necessary

- Check project memory, the campaign plan, and existing results: has a probe already pruned this branch? Is the metric already measured under an equivalent configuration? If yes, say so and stop (or record why the earlier pruning does not apply).
- Restate in 2-3 sentences: what this batch adds to the final table/figure, which cells it fills, and its acceptance metric. No plan document.

## 2. Grill only unresolved config decisions

- Facts (paths, GPU availability, cache locations, prior configs) are yours to inspect. Ask the user only for choices that change the scientific meaning: hyperparameters not pinned by protocol, seed count, which split, callback-vs-reload coverage, formal vs exploratory status.
- Keep the batch's **metric contract identical to sibling runs**: same splits, same metric definitions, same surfaces. A batch measured differently cannot share a figure with the others — flag any deviation explicitly in the record.
- One round of structured questions max for a batch; if config decisions explode, the work is actually a campaign — propose `exp-campaign`.

## 3. Implement in this session, run under project conventions

- Implementation happens **here, in the same session**, after the researcher issues the go-ahead. No fresh-session handoff (that is exp-campaign's model); the researcher drives execution timing, and formal runs follow the project's rules on who launches them — the researcher runs them or grants explicit permission.
- **Module placement:** put each piece in the module it belongs to; keep experiment-specific code inside the experiment's own directory with its predictable layout, so the experiment is findable by name. Do not create a shared abstraction for one consumer; do split into separate modules when sibling branches would otherwise contend on one file.
- **Loose coupling:** consume stable shared libraries through their existing interfaces. Never modify shared internals to fit this batch, never add batch-specific branches to shared code. If an interface genuinely lacks something, stop and escalate — that is a campaign-level decision.
- **Ponytail research code:** the minimum code that runs the batch correctly. **No defensive programming:** no speculative validation, no "just in case" branches, no swallowed errors — on error, exit with the real error. When a run fails, first suspect the environment (GPU contention, full disk, stale cache, conflicting job) before the code; only change code when the evidence says the code is wrong.
- Watch for the known failure modes of this project class: OOM, NaN, checkpoint serialization, degenerate metric collapse (e.g., all-same-answer). On failure: preserve the failing artifact/log, isolate minimally, never report a failed run as a result row.
- Negative results are results: record them with the same schema as successes.

## 4. Wait on long runs with `later` (delegated execution)

Long runs (GPU hours) must not hold the turn and must not be polled in a loop. The unattended pattern:

- **Delegation is explicit.** "Run it and check the results" delegates execution. If the researcher has not delegated, offer it before launching: "this needs ~Xh; I can run it in the background and resume automatically with the `later` tool — delegate to me?" State that each turn will end with a `later` schedule until the batch lands.
- **Launch in the background** per project conventions (nohup/tmux/launcher), then call the `later` tool: estimate the duration, add ~10% margin (5h run → schedule 5.5h), and write the prompt as a complete instruction to your future self — what to check, what to decide, what to run next.
- **End the turn** after scheduling — the `later` call is the LAST action of the turn: no idling, no spinning, no token-burning polls while waiting. The scheduled prompt arrives as a user message and resumes the session with no human present. Chain wake-ups across runs: each wake-up checks, decides, launches the next run, schedules the next `later`.
- **A timer is an estimate, not a completion signal.** On wake-up, verify the run actually finished and succeeded before recording metrics. If it is still running, re-estimate the remainder from observed progress (log/epoch counters, current throughput — contention can stretch a planned 5h run to 7h), never from the original plan, and schedule another `later` for that remainder plus margin. Repeat until the run actually finishes; there is no wake-up budget.
- If the host has no `later` tool, degrade: tell the researcher the expected duration and when to return, or follow the project's own waiting convention.

## 5. Land the metrics where figures can use them

- Every run lands in the shared results table with: id, config, split, surface, metrics, status, evidence path. Include every epoch/point recorded, not only the chosen one.
- Before finishing, check plottability: does this batch slot into the final figure as its own curve family, with the anchors (baseline reference lines) it needs? If the data shape would force an awkward plot (isolated points, mixed axes), fix the data collection now, not at figure time.
- Report concisely: cells filled, key numbers (all epochs/surfaces, not cherry-picked), deviations from sibling runs, what the campaign should reconsider because of this batch — and, under delegated execution, which `later` wake-ups fired and what each one found.
