# Multi-agent task decomposition and optional worktrees

Read this before delegating implementation writes. The default remains one primary Agent. Multi-agent execution is for independent delivery, evidence coverage, or isolation; it is not a presumed speedup. The primary session owns the goal, critical path, integration, and final verification.

Do not add a scheduler, global DAG, task registry, or second memory system. Use native subagents, the existing session todo, and the project's normal checks. Start with at most two independent workers; increase only with an explicit project budget and evidence that coordination remains useful. Delegation and isolation never expand the user's current write, resource, or compute authorization; project documentation alone does not authorize Git mutations or external writes.

## 1. Split only after a useful reduction

A branch is worth delegating only when all of these hold:

- it answers a distinct question or produces an independently checkable artifact;
- it can start without waiting for another branch's decision or implementation;
- it contains enough work to justify a fresh context and coordination;
- its scope, resources, acceptance, and stopping condition can be stated before launch;
- its result will change the parent task rather than merely add activity.

Resolve shared data shapes, API contracts, and ownership before parallel writes. A few known files or assertions need parallel tool calls, not subagents. Tightly coupled edits, sequential migrations, an unclear acceptance path, or repeated main-session work stay single-agent.

Choose the mode explicitly:

| Mode | Use | Aggregation |
| --- | --- | --- |
| Sectioning | Different modules, evidence sources, or independently deliverable slices | Collect evidence for every required slice. A missing or blocked slice leaves a gap, not a pass. |
| Race | Independent candidates for the same question | Choose first passing candidate, rank all, or best-of before launch. State the common baseline and acceptance criteria. Majority opinion is not verification. |
| Pipeline | Later steps depend on earlier outputs | Run the dependent steps serially; parallelize only independent stages |

## 2. Decide isolation separately from delegation

A worktree is one isolation option, not a requirement for multi-agent work.

| Situation | Default isolation |
| --- | --- |
| Read-only investigation, review, or evidence gathering | Shared checkout; no worktree |
| Only the primary Agent writes, or one worker writes while others only read | No additional worktree |
| Small concurrent writes with proven disjoint files, no shared generated outputs, and no interfering tests | Shared checkout is allowed; freeze each write set and integrate after all writes finish |
| Overlapping or uncertain write sets, competing implementations, different baselines, long tasks, or a clean per-task diff is needed | One worktree per writable task branch |
| Different dependencies, runtime state, ports, databases, devices, or large generated outputs | Worktree plus explicit runtime/resource isolation; a worktree alone is insufficient |
| Disposable prototypes or document-only candidates | An isolated temporary/output directory may be simpler than a Git worktree |

A worktree isolates the working directory and branch state. Create one only with the user's current authorization; creation is a Git mutation, not a side-effect-free default. It does not isolate devices, ports, databases, external services, global caches, or every project configuration. It is not a security sandbox: shell commands and external processes can still write outside it, so path and permission checks still apply. Record the baseline commit and any approved uncommitted snapshot. Do not assume ignored files, `.env`, dependencies, or local data appear in a new worktree; use the project's setup path and do not copy secrets or user changes without authorization.

In a shared checkout, each worker owns only its declared write set. No worker edits another branch's files, runs broad formatters, switches branches, or performs other Git mutations. Serialize tests that observe changing shared files or runtime state. If ownership becomes uncertain, stop and move the affected work to separate worktrees or back to the primary session.

## 3. Give every worker a complete brief

Use the existing task record or a self-contained kickoff with:

- goal and the exact slice or candidate;
- relevant source paths, baseline, and necessary context;
- allowed write set, output location, resources, and forbidden actions;
- acceptance command or observable result, budget, and stopping condition;
- the evidence and unresolved gaps to return.

A worktree belongs to a task branch, not to an Agent persona. Reuse its state for a fix round when relocation would be wasteful; otherwise use a fresh worker with the original brief and prior result. Workers stay within their scope and do not delegate again except for the explicit T3 handoff below. They do not commit, push, merge, or contact external systems unless the user explicitly authorizes that exact action for the current run; project documentation alone does not grant it.

## 4. Integrate and verify in the primary session

1. Launch independent branches together and keep the primary critical path moving. Do not repeat delegated searches or edits; spot-check only decisive or conflicting findings.
2. Consume completion notifications without polling. A slow branch blocks only work that actually depends on it. Replan when a shared contract, overlapping write set, resource conflict, or broken baseline appears. On failure, inspect output and actual process state; retry only after a confirmed stop and a changed hypothesis or fix, as another attempt of the same task rather than a duplicate task or worktree. Silence or timeout is not proof of exit.
3. Inspect each actual diff and evidence. Integrate serially through the project's normal file or Git path. Uncommitted worktree changes require an explicit integration step; branch commits, cherry-picks, and merges require their own authorization.
4. Run the project's relevant checks on the integrated result. A worker's `PASS` covers only its local scope and does not raise the evidence level. Apply [`verification`](../../verification/SKILL.md) to the final result when its normal triggers apply; use `consolidation-reviewer` only for explicit consolidation.
5. Before worktree removal, check for active sessions, uncommitted changes, and unmerged commits; preserve the worktree and report when any remain. Never discard uncommitted work or force-remove a worktree without explicit user confirmation; leave pre-existing worktrees alone.

Stop fan-out when the remaining branches no longer change a decision, coordination exceeds serial work, or the agreed budget is exhausted. Incomplete branches report their gaps; they are not silently converted into success.

## 5. Map to existing entries

- **T3 Code**: `delegate_task` defaults to the parent checkout and offers explicit `worktree` isolation from the parent commit; uncommitted edits stay out. Its self-contained task brief, async wake-up, and lack of automatic child-branch merge match this contract.
  - **Explicit handoff only**: When [`t3-plan-execute`](../../t3-plan-execute/SKILL.md) is active, the Antigravity brief may authorize its OpenCode execution session to use leaf native subagents within the existing scope, and Antigravity runs a native read-only subagent afterwards to review structure, code taste, and presentation. Leaf workers and reviewers never delegate further; normal worker limits, `quick-do`, and review rules still apply.
- **Orca**: orchestration is optional and its worker recipe defaults to `--worktree current`, using a new worktree only on request or conflict. Keep its distinction between task outcome, dispatch attempt, and process liveness; do not import the DAG/mailbox runtime for ordinary delegation.
- **Claude Code**: subagents can opt into `isolation: worktree`; agent teams instead rely on file ownership. Agent teams and scripted dynamic workflows serve long-lived peers and batch-scale stages, not the default two-worker case.
- **Codex**: subagents inherit the parent turn's cwd, sandbox, and approval settings; a session-level worktree is not per-subagent isolation. Use explicit write ownership and a separately isolated session when a task needs it.
- **OpenCode**: native subagents provide fresh foreground/background child sessions. Native worktree operations provide creation, inventory, and safe removal; Git is the built-in strategy and creation may run project setup. Creating a worktree does not create an Agent, and a subagent does not require a worktree.
- **pstack**: use the project's adapted `swarm` for slices or races and `arena` for candidate comparison and synthesis. Follow the [project adoption contract](../../trust-pyramid/references/pstack.md). Unrequested cloud execution and nested fan-out stay off. `interrogate` copies uncommitted changes into worktrees and writes repros there; authorize the copy and isolation first.
- **Antigravity**: use its [shared-board Swarm](https://antigravity.google/docs/swarm) only when explicitly requested and supported by the host. With ordinary native workers, route findings through the primary Agent.
- **Specialized workers**: existing entries such as `kernel-worker` keep their own workload, resource, and evidence contracts. Do not route them through a new generic orchestrator.
- **Long-running jobs**: background execution is process management, not automatically a multi-agent task. Add a model worker only when its independent judgment or artifact is needed.

Scripted dynamic workflows are a later option for repeated, stable, batch-scale stages, not a prerequisite for ordinary delegation. Evaluate them only when native briefs and the existing todo repeatedly become the bottleneck.

## Sources checked on 2026-11-24

- [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) — sectioning versus voting, orchestrator-workers, and when added complexity is warranted.
- [Anthropic: Multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) — complete delegation contracts and the cost of duplicated work.
- Claude Code: [subagents](https://code.claude.com/docs/en/sub-agents), [agent teams](https://code.claude.com/docs/en/agent-teams), [dynamic workflows](https://code.claude.com/docs/en/workflows), and [worktrees](https://code.claude.com/docs/en/worktrees) — separate orchestration levels and optional isolation.
- [Codex: Subagents](https://developers.openai.com/codex/agent-configuration/subagents) and [worktrees](https://developers.openai.com/codex/environments/git-worktrees) — read-heavy delegation, inherited permissions, and session-level isolation.
- [OpenCode: Agents](https://opencode.ai/docs/agents/), [configuration](https://opencode.ai/docs/config), and [SDK](https://opencode.ai/docs/sdk) — native child sessions and separate worktree lifecycle operations.
- [`pingdotgg/t3code@26f4c755`](https://github.com/pingdotgg/t3code/tree/26f4c7550e7ac954f63b9583a1905373aa07039c) — shared-by-default delegation, explicit worktree isolation, and wake-up-based completion.
- [`stablyai/orca@7daf01d9`](https://github.com/stablyai/orca/tree/7daf01d99f3d3301bf3c867e293ebb9d1f9a324e) — optional orchestration, current-workspace default, and evidence-based worker lifecycle.
