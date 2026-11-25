---
name: multi-agent
description: Coordinate optional native subagents for independent investigation or implementation, with clear write ownership and primary-session integration. Use for multi-agent, Swarm, 多 Agent, 联合开发, 并行开发, or when independent branches each change the deliverable. Ordinary development uses steady-do; project pstack adoption uses trust-pyramid.
---

# Multi Agent

Use the host's native subagents to deliver independent branches, not to simulate activity or promise a speedup. The primary Agent owns the goal, critical path, integration, and final verification. An explicit request activates this skill, not a quota of workers.

Read the complete [task decomposition and optional worktree guide](references/guide.md) before launching workers. It is the single rule source for branch eligibility, write ownership, isolation, briefs, failure handling, integration, and cleanup.

When asked to execute a [Plan Brief](../plan-brief/SKILL.md), start from its dependencies, candidate slices and acceptance checks. Recheck what has changed and keep the serial path where delegation adds no value. A planning-only request does not start execution workers.

## Enter and reduce

1. State the shared outcome, the primary-session critical path, each proposed branch, and the decision or artifact each branch will change. Include the budget and stopping condition in the existing session todo.
2. Start only branches that satisfy the guide's independence and useful-reduction tests. Two substantial independent branches are a reason to use this skill; a few lookups, coupled edits, sequential dependencies, or an unclear acceptance path are not.
3. Default to one Agent when no branch qualifies. If `quick-do` is active, preserve its single-session contract; resolve an explicit multi-agent request as a workflow conflict before launching workers. Other task workflows keep their own scope and verification rules while this skill governs delegation.

## Launch with explicit ownership

1. Choose sectioning, a candidate race, or only the independent stages of a pipeline. Start with at most two workers and no nested delegation; increase only under an explicit project budget with evidence that coordination remains useful.
2. Choose isolation separately from delegation. Read-only branches share the checkout. Writable branches need declared file ownership; use worktrees only when the guide's overlap, baseline, race, duration, or clean-diff conditions hold. Creating a worktree or copying uncommitted changes requires current user authorization.
   - Isolate ports, devices, dependencies, databases, and other shared runtime state separately.
3. Give every worker a self-contained brief: exact goal and slice, relevant paths and baseline, allowed write set and resources, forbidden actions, acceptance result or command, budget, stopping condition, and evidence to return. Do not dump the parent conversation or expand permissions.
   - For local source questions, put the route in the brief: `glob` for paths (`find` on Pi), `grep` for content, `read` for known files. Send independent searches in the same turn; once paths are known, send independent reads together as separate native calls when supported. Read short files whole and long files by complete relevant blocks (`offset`/`limit`).
   - Don't wrap those native calls in `execute`/Code Mode or use shell scripts to find and slice source. Keep shell for execution or a read-only fallback if a native tool is missing or fails; never bypass access denials. Use context correction only if an irrelevant result would get in the way of further work. Once the evidence answers the question, reply without a cleanup turn.
4. Launch independent workers together through the host's native subagent or documented background mechanism. Continue the primary critical path. Do not create a scheduler, mailbox, DAG runtime, task registry, or second memory system.

`Swarm` selects a parallel pattern here: collect evidence from every required slice, or agree how to choose a winner before racing candidates. Use the project's adapted pstack Swarm when available; otherwise use native workers. Delegation does not require installing pstack.

## Integrate and finish

1. Consume completion notifications without polling. Do not repeat delegated work; spot-check decisive or conflicting findings. If contracts, ownership, resources, or the baseline break, stop the affected branches and re-plan before any retry.
2. Inspect each actual diff and evidence, then integrate serially through the project's normal file or Git path. Worker completion and local `PASS` are branch evidence, not final acceptance. Git mutations and external actions require their own current authorization.
3. Run the project's relevant checks on the integrated result. Apply `verification` when its normal triggers apply; do not add a second Reviewer merely because several workers ran.
   - Run the agreed audit and delivery steps through the authorized endpoint. For “到 PR”, open and follow up on the task PR, leaving it unmerged; for “到合并”, check the current head, required approvals and final merged state. Neither Swarm nor plan approval grants those permissions by itself.
4. Stop fan-out when branches no longer change the result, coordination exceeds serial work, or the budget is exhausted. Preserve and report unfinished work, active sessions, uncommitted changes, and unmerged commits; never discard them during cleanup.
5. Deliver the integrated outcome, not a bundle of worker summaries. Report the branch mode, isolation used, checks actually run, unresolved gaps, and any worktrees or background work left active.
