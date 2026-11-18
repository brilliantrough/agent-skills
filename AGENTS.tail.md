<!-- memory-system:start -->
## User Discipline (always applies)

- A root `AGENTS.md` block marked `<!-- user-discipline:start -->` is binding user instruction. Read it before planning or acting, and recheck it at stage transitions and final delivery. Among project records it outranks the profile, decisions, journal and database memories.
- Use `discipline` only when the user invokes it. Apply the rule to the current plan at once, write long-term rules into the managed block, and carry the short rule into current todos and stage checks. Session-only discipline stays in the session.
- Only the user adds, changes, demotes or retires active discipline; cleanup never removes it. Report conflicts and violations: "recorded" is not "followed".
- The Ponytail lifecycle preset is enabled only when the user asks `discipline` for it; setup never writes it.
- If a host does not inject `AGENTS.md`, use its native project-instruction entry. This protocol guides behavior; it enforces no permissions.

## Project Memory System

StrictDoc (`docs/`), Magic Context and claude-mem work together. Their content may overlap; choose storage, depth and timing by judgment.

- **Session start**: run `load-mem`. Read project instructions and any user-discipline block, then the project profile (default `docs/handbook/project-profile.sdoc`), then task-relevant memory and source. Without a profile, continue with targeted recall instead of surveying the whole repo.
- **Milestones and before ending work**: run `save-mem`. When the project's shape, major research routes or key understanding change, update the profile with `project-profile`. Initialize memory with `migrate-mem`.
- **Recall before asking**: for prior decisions, attempted solutions, recurring failures or cross-session work, search claude-mem, StrictDoc and Magic Context (`ctx_search`) before asking the user to repeat context. Injected memory is a partial view. Tool names differ per host; `load-mem` lists them.
- **Source of truth**: below live user instructions and the discipline block, current StrictDoc norms win when records disagree. `Active` decisions are current rules; proposals, retired decisions, journal entries and reports are history and stay distinguishable.
- **Read narrowly**: grep the StrictDoc tree, e.g. `grep -B1 -A1 '^STATUS: Active' docs/project_memory/decisions.sdoc`, then read only the matched node.
- **Norms change, history stays**: when the user changes a decision or a settled change is clear, add a successor, mark the old node `Superseded` and say so briefly. Guesses and one-off attempts do not change norms.
- **Saving is maintenance, not accumulation**: each save rewrites, merges or deletes repeated and stale wording in place. Record conclusions, real constraints, open risks and necessary evidence; leave out tool logs, hash/diff/manifest ledgers and disclaimers.
- **Reorganizing memory**: only when the user asks, with `consolidator`. Keep a recoverable baseline; facts, status, referenced IDs and evidence stay traceable.
- **Risks**: record open concerns, unproven assumptions, method weaknesses and the distance to the goal in `docs/project_memory/risks.sdoc` when it exists, including concerns the user voices before there is evidence.
- **Validate**: after changing `.sdoc` or StrictDoc config, run `strictdoc export .` from the docs root and fix failures before calling the update done.

### Technical writing and replies (always applies)

- Before writing or revising human-facing project text, or delivering an explanation, status update or final reply, load `readable-docs`. Do not wait for a style request.
- Write for scanning, in Chinese by default. Use lists and tables only when they help. Preserve facts, conditions, uncertainty, required structure and instruction strength.
- Before delivery, run its short pass: lead with the answer; remove staged openers, fake contrasts, repeated context, decorative formatting, empty closers and chat residue. For explicit polishing or pattern-heavy long text, apply its full reference.

### Context window (always applies)

- Choose the tool by the next action: exact source or a complete edit unit → native `Read`/`Grep`; short output used directly → native `Bash`; large-data aggregation → `ctxm_execute`/`ctxm_execute_file`; multi-command indexed research → `ctxm_batch_execute`. Return enough evidence to act on.
- Web: use the web MCP tools instead of host built-ins (WebSearch, WebFetch, web_search): `tavily_search`/`tavily_extract` for facts and news, `firecrawl_search` for ranked results, `firecrawl_scrape` for a known page. Call tools by the names the host actually exposes and find the rest through tool search or the MCP gateway. `ctxm_fetch_and_index` only for a page you will re-query.
- Magic Context: `ctx_search` recalls earlier decisions, `ctx_memory` stores durable knowledge, `ctx_note` holds reminders.
- Reuse loaded skills, confirmed facts and unchanged source. After an exact-match edit fails, reread the affected unit before patching again.

### Long-running work (always applies)

- Pi: unknown completion time → `pi-background-tasks` (`bg_run` for shell, `bg_delegate` for read-only investigation; Fusion only for an explicit multi-model review). Known duration plus a custom next-step prompt → `later`. OpenCode v2: native `shell`/`subagent` with `background: true`, or `Ctrl+B`; use `later` when the resumed turn needs instructions.
- Launch, then end the turn; do not sleep or poll. On wake-up, read the result, logs or exit state before continuing.
- Background shell is not sandboxed. Keep `bg_delegate` isolated unless an extension-registered provider requires `ambient`.

### Steering the agent (always applies)

- Steer agent choices with prompts, skills and tool descriptions rather than tool-level hard blocks. Project code contracts may be enforced by lint, types and dependency checks; permissions and runtime protection stay separate.
- `quick-do`, `steady-do` and `plan-brief` are user-selected modes. If none is named, load `steady-do` for most work, `quick-do` for a small bounded change, `plan-brief` only for a large project or major change.
- Adding an MCP server: use descriptive server and tool names with rich descriptions. Pi native MCP keeps its namespace prefix; use `exposure`/`toolExposure` for direct versus discoverable tools.
- When behavior goes wrong, fix the system that produced it (a line here, a skill, a fork patch), not only the machine where you noticed it.

### Code taste (always applies when writing or changing code)

- **Ponytail** is this suite's name for one trade-off: the smallest complete solution, reuse first, and only assets that keep working. No speculative abstraction, over-encapsulation or defensive scaffolding.
- Verify changed behavior through the smallest relevant real path and existing project checks; a clean exit says nothing about behavior. Add a test only when the change needs a focused regression. Report unverified behavior.
- Accept small, quickly recoverable rework instead of keeping maybe-useful files, branches or scaffolding; re-add a detail when a real need returns. At stage review, flag both defects and "should delete but remains".
- During authorized cleanup, delete pseudo-safety and disposable artifacts: one-off hash/byte-diff checks, Agent-made manifests and inventories, speculative defensive branches, scratch/probe/debug scripts, one-off tests and temporary outputs. Keep protections tied to real trust boundaries, correctness/integrity/authenticity, data-loss prevention, interoperability, accessibility, hardware calibration, current evidence or explicit byte-level contracts.
- **Repeat critical rules deliberately**: restate rules central to the task with costly failures at every relevant stage and decision point. Trim only task-irrelevant detail and wording that changes no action.
- Report results in one line.
- Comments carry what code cannot: contracts, external constraints, algorithm references, necessary reasons and license notices. Development history belongs in project memory.

**Placement**: paste this block at the tail of a project's own `AGENTS.md`; the project's own content stays on top. Setup offers to write it (opt-in, default no).
<!-- memory-system:end -->
