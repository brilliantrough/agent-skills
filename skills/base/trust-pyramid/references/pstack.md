# 项目级 pstack 接入与特化

pstack 是重度软件项目的可选实现，不是套件的全局依赖。`trust-pyramid` 继续维护五层语义、证据和权限边界；项目决定是否引入 pstack 的任务 playbook、子 Agent 和验证资产。套件不新增 pstack 注册器、overlay 引擎或第二套配置系统。

2026-11-24 核对的官方基线是 [`cursor/plugins` 的 pstack 0.15.48](https://github.com/cursor/plugins/tree/005d8f6e8ec057b738adcd08a08b30db0478402d/pstack)，MIT 许可。官方直接支持 Cursor，并提供 Claude Code 适配；OpenCode／Pi 需要另行适配。社区移植只作映射参考，不作为套件受管取源。

## 何时引入

长期维护、跨模块、具有真实测试／CI／PR 流程，且需要更强任务编排和项目验证资产的项目，可以评估 pstack。日常办公、一次性脚本、局部修补和多数探索性研究不需要完整框架。重度开发是评估触发条件，不是自动安装理由；项目已有成熟约束时只补实际缺口。

引入前先在当前任务记录中写清：现有流程缺少什么、pstack 哪个模块补齐、增加的运行与维护成本、怎样验收和退出。没有明确缺口的，不安装。

## 项目持有的接口

套件只约定语义接口，不在未采用的项目放置占位文件。实际采用时，在项目现有说明中记录：

- 上游来源和固定 commit／版本，宿主及适配层；
- 启用、禁用、删除和项目改写的模块及位置；
- 项目工具、模型、测试和真实应用入口；
- 权限边界、验证命令、上游更新和退出方式。

只调模型、角色和开关时优先使用上游配置。删改 playbook、原则、模块路由或分层含义时，由项目持有自己的副本和本地补丁；这不是简单配置能够覆盖的 overlay。更新采用固定基线、差异比较和本地修改重放，不自动跟随 latest，并保留上游版权与许可。

## 共存规则

本说明不是上游模块会自动加载的配置。项目必须把适配写进实际加载的 pstack 副本、Agent 定义或注册提示；只安装原版再阅读本说明，不会改变上游行为。

- **先改写冲突指令，再选择默认路由器**：`feature` playbook 在单一实现路径下也强制委派的规则，须改为本文的多 Agent 触发条件；`opening-a-pr` 从其他 playbook 的默认结尾解耦；`swarm` 的 cloud 默认值改为明确选择的本地 shared／worktree；`worktree-cleanup` 在未提交改动、未合并 commit 和活跃会话检查接入前禁用。完成这些实际补丁后，项目才可让合格任务默认进入 `poteto-mode`；用户显式选择的 `quick-do`／`steady-do`／`plan-brief` 优先。
- **权限不扩张**：用户纪律、项目 `AGENTS.md` 和现有安全机制优先。`poteto-mode` 中无需确认即可发送团队消息、更新工单和启动评测的条文必须改写；自动 commit／PR／merge／force-push 及上述外部动作仍需当次明确授权，`opening-a-pr`、`shipping`、`autopilot-*` 不得仅因进入 playbook 就获得写权限。
- **一份验证资产**：pstack 生成的应用驱动、feature map 或测试接入项目现有检查入口，不另建平行台账。`interrogate` 是可选对抗审查，不与 `verification-reviewer` 组成每次必跑的双重审查；它会复制未提交改动并在隔离 worktree 写复现，不能当作默认共享只读路径。
- **Reviewer 不替换**：pstack 负责产生候选和证据；`verification-reviewer` 按原触发条件独立验收最终集成结果。`consolidation-reviewer` 只在显式整理后审查语义保持、真实保护和简洁性。PR 评论和合并由主 Agent 在当次授权后执行，Reviewer 不直接写外部系统。
- **一份记忆与模型配置**：保留项目已有记忆、上下文和模型管理。`recall`、`automate-me`、`show-me-your-work` 不建立第二套长期记录；官方 `setup-pstack` 的全局 `alwaysApply` 模型规则须改成项目作用域或明确的 pstack 专用配置。
- **名称与工具先适配**：扁平安装处理 `tdd`、`teach` 重名；映射 Cursor `Task`、模型 slug、cloud agent 和 `cursor-team-kit` 依赖。OpenCode 的 `pstack-` 前缀可避开 skill ID 冲突，但不解决行为冲突。
- **并行与隔离分开决策**：默认仍由主 Agent 实现；准备并行写实现时读取 [多 Agent 任务拆解与可选 worktree](../../steady-do/references/multi-agent.md)。`swarm` 用于独立切片，`arena` 只在明确需要候选竞赛时使用，worktree 按写入与隔离需求选择，不作为启动仪式。

## `no-comments`：保留强默认，补丁实际加载文件

项目采用官方 [`no-comments`](https://github.com/cursor/plugins/blob/005d8f6e8ec057b738adcd08a08b30db0478402d/pstack/skills/no-comments/SKILL.md) 与 [`comment-sicko`](https://github.com/cursor/plugins/blob/005d8f6e8ec057b738adcd08a08b30db0478402d/pstack/agents/comment-sicko.md) 时，必须同时补丁这两个实际加载的文件。原版保留名单不承认 `shortcut:`，主流程在未获准编码时仍会删除约束；只安装原版不会自动遵守下面的窄例外。

保留上游强默认，不改写成“尽量精简注释”：**默认删除，保留必须命中例外并给出证据；无法证明该留时删除。** 限定调用方文件或 diff；Comment Sicko 只处理注释和标记重构对象，不写应用代码；主 Agent 审查报告与 diff，修复范围内的 `MUST KILL` 和临时绕路，再验证真实行为。`IMPORTANT`、`do not remove`、长篇辩解和“以后可能有用”都不是保留证据，删除数量只作报告，不作为目标。

项目必须落地以下补丁：

1. **补丁 Comment Sicko 的保留名单**：有效的既有 `shortcut: <限制>, <何时升级>` 是 `ponytail-debt` 的输入，不是普通注释。范围内解决债务并删除；确属范围外时保留并报告。不得为了躲过清理新写 `shortcut:`，也不把它当作免审理由。
2. **补丁主流程的恢复与约束分支**：第 2 步允许保留或恢复已举证、因本次范围外而不能解决的有效 `shortcut:`，不得被上游“只有无法改变的事项才可保留”再次删除。算法、单位、硬件、数据格式或正确性约束，优先编码进类型、API、测试或检查后删除；同一步也允许恢复已被源码、外部契约或可复现行为证明为真的此类约束。第 5 步在未获准编码且当前无法修复时，保留一条最小注释并报告 open，不再执行原版的“否则删除”。无法证明或表述模糊时仍删除，不得把实现麻烦说成 out of scope。
3. **保持 `quick-do` 单会话**：当前工作流为 `quick-do` 时不启动 Comment Sicko，由主会话按同一举证、删除和根因修复标准执行；需要独立审查时先按 `quick-do` 的切换规则说明原因并获准改用其他工作流。
4. **完成判据**：范围内的接受项已修复或有明确阻塞证据，合法例外和范围外债务可追踪，相关真实路径已验证。不能只交删除计数，也不能只删警告而留下已知风险。

官方 skill 带 `disable-model-invocation: true`，单独安装不会自动运行；项目可显式调用，或在已完成上述补丁的 `poteto-mode` review 步骤中接入。跨模块或高风险重构仍按 `verification` 委派独立复核；只有用户显式要求整理时才进入 `consolidator` 与其 Reviewer。

## 最小启用顺序

1. 固定基线并选择一个真实项目任务，先补丁实际加载文件中的默认委派、自动 PR／外部动作、cloud、worktree 清理和全局配置写入，未获授权的 Git 与外部动作保持关闭。
2. 完成宿主工具／模型映射和模块裁剪，补丁 `no-comments` 两个文件，保留现有 Reviewer、记忆和检查入口。
3. 运行一个真实开发任务及一条失败路径，再用临时补丁、真实约束、有效 `shortcut:` 和模糊 `IMPORTANT` 样本核对注释结果；检查任务路由、证据、权限和集成结果。
4. 验收后再决定是否设为项目默认；更新与退出同样走项目验证，不在其他项目复制未经验证的特化。
