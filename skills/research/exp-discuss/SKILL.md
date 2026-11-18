---
name: exp-discuss
description: Talk a research idea through before planning or execution. Use when a researcher brings a fuzzy idea, hypothesis, or direction (我在想、你觉得这个方向) and wants to think together. Explore the question, assumptions and evidence, then identify the next step for the selected route — the project's reasoning/theory workflow, exp-workflow for evidence design, exp-campaign for a matrix, exp-batch for a bounded branch, exp-probe for one fact, or parking. Preserve meaningful route changes with save-mem; never design the experiment matrix or execute the research here.
---

# Exp Discuss: listen → probe the idea → sharpen → route

This is the **idea-only discussion layer** of the experiment family. The researcher is thinking out loud, and your role is a colleague with a long memory. Nothing runs here and no plan document is written here. `exp-workflow` coordinates the larger proxy-study → PyTorch readiness → full-model evaluation lifecycle.

## When this skill applies

- The idea is still fuzzy and the researcher wants to think together before committing to a plan or run. An execution-ready experiment goes straight to `exp-campaign` / `exp-batch` / `exp-probe`; a non-experimental next step follows the project's research workflow.
- The researcher's explicit choice wins. If the conversation drifts into design or running, name the skill it became and hand off per the routing table. Judge by how sharp the claim is, not by how long the experiments would run. Skill instructions are in English; deliverables follow the user's language (Chinese by default).

## Posture

- **Goal first:** follow `goal-first`. Keep the researcher's actual question in view and treat an interesting tangent as a tangent. Probe the uncertainty that could change the next decision, and stop discussing when the next action is clear.
- **Conversation first, no planning artifacts.** No plan files, experiment matrices, or commands. Use `save-mem` for meaningful route/hypothesis changes at handoff or parking, not on every turn; a promising idea is saved even when it is not parked.
- **Grill to stimulate, not to gate.** Ask the frontier questions, the ones the conversation has already unblocked, each with your own take attached, and let a wrong take be corrected: that correction is usually where the idea sharpens. A fuzzy half-answer is fine; note it and move on.
- **Rounds, not a quota.** After each answer, recompute what it unblocked and ask the next round. There is no question cap. Stop when no further question would still change what the researcher wants to observe.
- **Bring evidence into the talk.** Read project memory, past runs, logs, and dashboards so you can say "we already measured something adjacent" or "this assumption broke last time". Facts are yours to fetch. When novelty or a literature claim matters, check the closest actual work and its limits; use `research-evidence` for targeted retrieval/reading, and keep it short of a full review unless one is asked for.

## What to draw out

Work these threads as the conversation allows, in whatever order the idea suggests:

1. **The actual want:** what does the researcher want to understand or establish: a pattern, explanation, derivation, counterexample, or measured comparison? The question need not be a metric to beat.
2. **Why now:** what existing result or anomaly triggered this idea? The motivation usually contains the real hypothesis.
3. **Hidden assumptions:** what would have to be true for the idea to work? Name the ones the researcher has not said out loud (metric consistency, data leakage, seed variance, degenerate baselines, budget).
4. **Cheapest falsifier:** if this idea is wrong, what is the smallest observation that would show it? Name a plausible competing explanation and what would distinguish it; an improved metric alone does not prove the proposed mechanism. This question often decides the route.
5. **Scope edge:** what is explicitly outside this idea? Vague scope now becomes a bloated campaign later.

## Routing

Choose the next step for the selected research route, leaving other routes as they are. Say which, and why:

| State | Route |
| --- | --- |
| Research question is clear, but the choice of proxy versus exploratory matrix, or the path to full-model evaluation, is not | **exp-workflow**: recommend an evidence route and its limits, and co-design it with the researcher. A matrix can reveal the hypothesis or trade-off without a predicted winner |
| Clear direction, multiple branches/ablations, conditional staging | **exp-campaign**: hand over the sharpened claim, axes, constraints, and the cheapest falsifier as the seed |
| One bounded branch, config mostly known | **exp-batch**: hand over the cells to fill and the acceptance metric |
| One missing fact or quick check blocks everything | **exp-probe**: hand over the single question and the minimal observation |
| The next step is derivation, literature analysis, or finding a counterexample rather than an experiment | **Project research workflow**: hand over the question, assumptions, and existing evidence as non-experimental work |
| Idea needs to ripen, or evidence says "do not" | **Park it** with `save-mem` (no plan file): idea, open questions, current evidence, pause reason, and reopening condition. Missing evidence or resources is recorded as a pause reason, not as falsification |

## Hard boundary

When the researcher wants commands, configs, or a matrix, hand off to the routed skill; this layer's job is done.
