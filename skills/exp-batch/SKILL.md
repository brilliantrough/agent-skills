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

## 4. Land the metrics where figures can use them

- Every run lands in the shared results table with: id, config, split, surface, metrics, status, evidence path. Include every epoch/point recorded, not only the chosen one.
- Before finishing, check plottability: does this batch slot into the final figure as its own curve family, with the anchors (baseline reference lines) it needs? If the data shape would force an awkward plot (isolated points, mixed axes), fix the data collection now, not at figure time.
- Report concisely: cells filled, key numbers (all epochs/surfaces, not cherry-picked), deviations from sibling runs, and what the campaign should reconsider because of this batch.
