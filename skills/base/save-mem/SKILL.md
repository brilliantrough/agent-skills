---
name: save-mem
description: Preserve useful project knowledge with StrictDoc, Magic Context and claude-mem. Use at milestones, after a resolved failure or settled decision, when a feasibility concern or user worry surfaces, and before ending work. Each save cleans up in place instead of appending, and records open risks alongside outcomes.
---

# Save Memory

## Intent

Leave memory that helps both the next Agent and the human reader understand **what applies now, why, and how the project got here**. Preserve useful knowledge rather than reproducing the conversation. **Saving is maintenance, not accumulation:** every save includes obvious local cleanup; directly rewrite, merge, or remove repeated and stale wording instead of waiting for `consolidator`. Decide what deserves saving and where; the sections below are guidance to apply with judgment.

## Route explicit discipline out of ordinary memory

When the user explicitly invokes `discipline`, use that skill: immediately activate the rule in the current task and write long-term discipline to the root AGENTS `user-discipline` block. A StrictDoc node, database entry or journal note does not activate discipline. `save-mem` may additionally preserve the reason or history; only explicit user instruction may change the active block.

## Use the stores together

| Store | Useful capabilities |
|---|---|
| StrictDoc `docs/` | Readable current rules and decisions, rationale, project history, specs, and runbooks |
| Magic Context `ctx_memory` | Persistent facts, rules, decisions, lessons, and context available across sessions |
| Magic Context `ctx_search` / `ctx_expand` | Find existing knowledge and recover the discussion behind it |
| Magic Context `ctx_note` | Reminders and follow-ups for later |
| claude-mem | Searchable cross-session observations; explicit durable notes when a write tool is available |

- Storing the same knowledge in StrictDoc and Magic Context is reasonable and often useful. Database entries can contain substantive knowledge as well as document pointers.
- Choose the amount of overlap and detail that helps future work. A memory may exist without a document counterpart, and a document without a database mirror.
- Check existing memories and relevant source files first to avoid accidental duplicates and stale claims. `ctx_memory` supports writing, updating, merging, and archiving; use the operation that fits. Paths and UIDs are useful cross-references and are optional.
- When a tool is missing, keep using the other stores, and state any important knowledge that remains unsaved or unverified.
- A project's **vocabulary and domain model** are memory too: `domain-modeling` is the skill for changing them (challenging terms, glossary entries, hard-to-reverse decisions).
  - Land its output in this project's own layers — the glossary in StrictDoc's handbook (or a `CONTEXT.md` where the project already uses one), hard-to-reverse decisions as `project_memory/decisions.sdoc` nodes, so there is one decision tree.

## Preserve key outcomes in claude-mem

- Automatic capture can preserve work history, but tool availability or a successful host turn does not prove a key conclusion was stored.
  - When a claude-mem write tool is available, explicitly save important decisions, corrections, resolved failures, and handoff facts; inspect the result before claiming persistence.
- Search relevant existing observations before adding a note, reusing evidence already retrieved. Save useful conclusions and their scope; leave out full transcripts and secrets. Overlap with StrictDoc and Magic Context is welcome and optional.
- Tool identity follows the integration: Pi's native `mem_search` / `mem_timeline` / `mem_get_observations` and OpenCode's `claude_mem_search` are **claude-mem recall tools** and cannot write. See `load-mem` for the host-specific naming and parameter differences.
- With claude-mem MCP, `save_memory` (`text`, optional `title`/`project`) saves a local-worker note.
  - In OpenCode v2 Code Mode, for server key `claude-mem`, that is `tools["claude-mem"].save_memory(...)`; direct exposure can be `claude-mem_save_memory`.
  - An additionally configured Pi MCP can expose `mcp__claude_mem__save_memory`.
  - Use the name the actual catalog shows.
- In server runtime, use `observation_add` only when exposed for the intended server/project; `save_memory` does not write server notes.
  - Native Pi alone has no explicit write tool in the verified 13.39.0 interface (2026-10-14): continue with the available stores; `mem_save` does not exist, and a save is no reason to install extra integrations.

## Keep the current project profile useful

When the project’s overall shape, major research routes or key understanding changes, use `project-profile` to update the affected parts of its existing profile (StrictDoc default: `docs/handbook/project-profile.sdoc`). Check the related implementation or research evidence and state the verification scope. Ordinary saves, local edits and single experiments leave the profile alone. If the profile is missing, suggest establishing one; a save does not start a repository-wide survey. The profile explains what exists and is understood now; decisions and history retain the fuller reasoning and evidence.

## 设计知识与记录分工

按读者要回答的问题组织知识。同一事实可以存在多处，也不必为每类信息新建文件。画像是当前整体视图；决策、经历与风险各有职责；`consolidator`／reviewer 负责维护与检查，不产生新的记录类别。

| 现有载体 | 保存什么 |
| --- | --- |
| 项目画像 | 当前形态、必要设计理由、研究路线与证据概况；内容规则归 `project-profile` |
| handbook／专题说明 | 当前机制、跨模块约束、接口、运行方法及研究思路／推导，按主题解释，不按日期追加 |
| decisions | 重要选择的背景、理由、实际取舍、正负后果及适用／重议条件；普通实现动作不单列决策 |
| journal | 重要经历、转折、失败与验证证据；当前设计的说明另有归属，见下 |
| 现有风险记录位置 | 仍影响判断的未知、假设和技术债，按下文状态字段维护；普通待办另记 |

- 仍指导开发的理由若只埋在 journal，将有依据的当前解释补入画像或现有专题，保留历史来由与证据引用。短说明与详细记录可以交叠，但不复制整份文档；局部技巧留在原处，无需升格为架构决策。
- 代码／配置／真实运行证据说明实现事实，有效决策说明意图与约束；两者不一致时明确写出偏差，实现事实要靠实现验证。API 参考、操作手册、需求和实验原始产物沿用专业载体，记忆只保留必要结论与入口。

### 科研记录：按路线关联，不把方案选择当科学结论

- 沿用项目的路线名称或标识，在已有记录中关联问题／假设、推导或实验条件、证据与结论边界；`project-profile` 维护全景，专题解释方法，journal 按路线和阶段记关键转折。没有代码的思路也能保存，沿用已有记录位置即可。
- decisions 记录研究协议、预算与路线取舍等已确认选择；“决定研究 A”不证明 A 正确。风险标清影响单条路线还是共享前提；推进状态与认识状态按 `project-profile` 分开写，决策的 Active／Proposed 不表示科学可信度。
- 保留矛盾、反例、暂停原因和重开条件；证据只支持它所属的路线，跨路线综合需说明依据。共用结果引用同一来源，原始产物留原处；画像更新按 `project-profile` 的触发条件局部进行。
- 关键主张关联实际依据及版本（原文锚点、run ID、源码／数据／评分协议等现有标识）。依据被更正、撤回或换版时，标出受影响的结论／图／稿件与待复核范围，保留历史成立条件；先核对影响范围，再决定复核哪些部分。

## Keep current truth distinguishable from history

**Below live user instructions and any user-discipline block, StrictDoc is the source of truth among other project records when records disagree.** Magic Context and claude-mem may legitimately contain earlier or conflicting accounts; treat them as history unless StrictDoc agrees.

- Keep current rules and their scope easy to identify. In the bundled grammar, decisions use `Active`, `Proposed`, `Deprecated`, or `Superseded`; dated journal entries describe experience rather than policy.
- **Active norms are maintainable; historical facts and decision meaning must survive.** When the user changes a decision, or a settled change is clear from the conversation and evidence, add a successor when useful, mark the old node `Superseded`, and briefly tell the user.
  - Guesses, temporary experiments and routine tasks do not change the canon.
  - Ordinary explanatory docs and non-normative memories may be revised more freely.
- Keep meaningful decision changes understandable. A journal note, revision context, or successor decision may preserve what mattered about the previous approach; choose the lightest suitable form. Follow any project-specific history-preservation rules.
- Capture the reason when known: evidence, constraints, alternatives, or the user's intent. When the reason is unknown, say so.
- Distinguish accepted decisions, observed behavior, pending work, and unverified claims. A working implementation may still differ from the intended rule.
- Research and experiment records must identify the route and evidence stage (e.g. derivation under stated assumptions, proxy study, single-model iteration, multi-model validation).
  - Stages answer different questions and support different claims.
  - Keep conditions, observations, inferences and conclusions distinguishable; a cross-stage synthesis compares explicitly attributed evidence and keeps local support labelled as local.
- Harvest living negative knowledge as well as outcomes.
  - At milestones — and after any feasibility discussion, including side sessions — record open concerns, unproven feasibility assumptions, known method weaknesses, shortcuts and the risks they carry, dead ends and why they were abandoned, and one line on the remaining distance to the goal.
  - A concern discussed but never recorded is lost; a worry the user voices is worth recording even before there is evidence for it.
- Use the risk lenses as prompts and record only real items:
  - algorithm mechanism: do the premises hold?
  - real execution: does the trick survive a real implementation; any disallowed cost?
  - data and scale: is the dataset available and extensible; can the model scale up?
  - training process: convergence preconditions, generalization.
  - value placement: is this the real bottleneck of the actual task? Judge that with the `goal-first` skill and record only its outcome here.
- Field semantics are fixed, organization is free.
  - Every risk or concern entry carries its status (Open/Mitigated/Resolved/Accepted), stage, the decision it blocks, current evidence, and the condition that would resolve it; the prose layout is the writer's choice.
  - Where the project keeps a risk register (e.g. `docs/project_memory/risks.sdoc`), update entries in place as they evolve; add a journal entry only for an independently meaningful event or turning point.
  - Otherwise record the same fields in StrictDoc prose or a database entry.
- Where useful, reconcile known stale database claims and link related records; a save does not require auditing every store.

## Human-readable writing

Before drafting or revising memory prose, load `readable-docs` and follow its writing contract; it applies to all human-facing technical records, memory included.

- **每次保存先做轻整理**：找到应承担该知识的现有位置，直接改写、合并、重排或删除重复／失效表达；能更新旧句就不新增，能并入同主题就不加新日期段。普通说明与非规范记忆的这类整理直接做，无需请示或等待 `consolidator`；历史事实、有效决策状态、独有证据和未闭合风险在精简后必须还在。
- **关键纪律不因轻整理去重**：任务核心、违背代价高的规则在不同决策点的重复提醒要保留；精简重复内容时，只清理与任务无关的细节、失效表达和不改变动作的同义复述。
- **去掉防御性编程风味**：工具调用流水、hash／字节 diff／manifest 台账、逐文件核对账，以及“保险起见”“暂不敢改”这类套话都不写。验证只留结论与必要证据入口；真实风险直接写影响与重开条件。
- 跨主题、长周期或需要完整原文对照的阶段重组交给用户显式调用的 `consolidator`，它按 **Ponytail** 风格保持主线、压缩次要过程并保留可恢复基线；保存不会自动启动它。纯表达整理无需 successor decisions。

## Practical StrictDoc reference

- The bundled layout is one project under `docs/`: `strictdoc_config.py`, `project_memory/{decisions,journal}.sdoc`, and `handbook/`. In an existing project, adapt to the layout that is already there.
- `assets/docs-skeleton/`, relative to this skill, provides a starting point. Add missing pieces and leave existing docs and config intact. `migrate-mem` covers onboarding an already-developed project.
- The decision grammar supports `UID`, `STATUS`, `TITLE`, `STATEMENT`, optional `RATIONALE`, and relations. Plain journal `[TEXT]` nodes do not automatically support decision fields such as `STATUS`.
- When a successor decision is useful, it can carry the relation below, pointing to the old UID; mark the old decision `Superseded`. The reverse relation is `SupersededBy`:

  ```text
  RELATIONS:
  - TYPE: Parent
    VALUE: DEC-TOPIC-001
    ROLE: Supersedes
  ```

- Markdown rendering is enabled by `OPTIONS:` followed by indented `MARKUP: Markdown`. Sections use `[[SECTION]]` / `[[/SECTION]]`; stable UIDs belong on content nodes, not `[DOCUMENT]` headers. Inspect the project's actual grammar when adding fields.
- Validate `.sdoc`, grammar, or config changes with `strictdoc export .` from the docs root, using the available executable or project environment. If the validator is missing or the export fails, report it and resolve it before calling the document update complete.
- Keep secrets out of stored/exported content; names and references to secret locations usually suffice. Respect the project's existing rules for version control and preservation of historical nodes.
