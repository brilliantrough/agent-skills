# 项目验证

本目录是项目的 Verification 层：用真实生产入口和固定输入验证行为，不用 Agent 当次编写的假设证明实现正确。静态检查仍归 `scripts/check.sh` 的公开体检；需求、取舍和宿主语义审查不能由测试全绿替代。

## 日常入口

```bash
bash scripts/check.sh              # 快速公开检查
bash scripts/check.sh --with-tests # 公开检查 + 全部可离线行为回归
```

`--with-tests` 是提交前的统一门禁。快速检查也执行交付静态契约：入口直接引用的测试与 Verification 资产必须存在且有普通 stage 0 索引条目（`git add -N` 不算，索引损坏必须失败）；本仓源码不得恢复 raw／archive／codeload 取源旁路，第三方来源与 Release 保留；`output-store`／`context_output_read` 不得恢复，`context_rewrite` 与原生门控说明必须保留。断言由 `tests/source-bench.py --static-contract` 统一提供，统一入口会清除调用者设置的 `PYTHONOPTIMIZE`。测试必须实际执行并输出 `PASS`；外部前置条件不满足时明确输出 `SKIP` 和原因。应由本仓提供的测试文件缺失、测试失败或运行器自身异常均为 `FAIL`，不能当成跳过。退出码为 0 只表示已执行部分没有失败，不消除 SKIP 的未验证范围；最终报告必须列出它们，需要完整覆盖时不得接受相关 SKIP。

需要定位单项时可直接运行对应脚本，但最终仍须回到统一入口验收。私有 selfcheck 检查本机 live 配置漂移，不属于这套可移植行为测试，按 `AGENTS.md` 的本机命令单独运行。

本机 Sub Agent 安装状态另有显式入口，不混入默认离线门禁：

```bash
bash scripts/verify-subagents.sh           # 只读检查，漏装或漂移返回非零
bash scripts/verify-subagents.sh --apply   # 调用现有 setup，集中确认后更新
```

`--apply --yes` 表示明确接受各 setup 的默认升级与共享 worker 副作用。Reviewer 不执行更新；安装后还要按下面的真实宿主入口复核，文件存在不等于加载或委派成功。

## 测试准入

新增行为回归必须接入 `--with-tests`，不能只留在命令记录、会话或 `/tmp`。临时探针可用于诊断，但不能作为最终验收证据。

### 条目随功能累积

- 新功能完成针对性验证后，主 Agent 把**一个最小可重复条目**并入现有测试和统一入口；优先在已有测试增加场景，不新建平行框架或独立清单。一个条目只验证一个关键行为，写清执行入口、明确预期和必要前置条件。条目从真实入口派生：先认定用户可见表面、启动方式和可编程驱动手段，未实跑过的不算条目。
- `verification-reviewer` 聚焦当前功能后，默认快查相关旧条目：低成本短回归优先，也可沿代码检查明显破坏；不要求每次全量重跑，未运行项必须披露。Reviewer 建议条目，主 Agent 负责落盘。
- 功能删除或语义变化时更新或退役旧条目。条目数量可以增长，单个条目不扩张成全量矩阵。系统性复查时区分文档漂移、harness 缺口和产品缺陷；产品缺陷记录给用户，不靠改登记掩盖。无法到达的条目标为 `verified-unreachable` 并写明缺的前置条件和尝试过的入口。

### 每条测试的默认约束

- 使用本地 fixture，不联网，不读取或修改真实 `HOME`、live 配置、凭据或共享运行时。Bun 测试显式使用 `--no-install`，缓存由统一入口放入临时目录，缺依赖明确 SKIP。仓库 `node_modules` 若链接到仓外 live runtime，相关测试明确 SKIP，不跟随执行；`PI_HOST_DIR` 只允许显式指定一次性隔离宿主。
- 写入只发生在独立临时目录；结束清理进程和文件，外部源保持不变。
- 调用真实生产函数、脚本或宿主官方接口，不复制生产实现做平行校验。
- 断言可观察行为、状态与必要的零写入条件，不以退出 0 或 `PASS` 文本代替行为断言。
- 失败返回非零并给出可定位原因；长进程必须有超时，不能留下后台工作。

修复重复出现或高代价缺陷时，先把最小复现固化为正式回归，再修实现。变异测试从当前源码生成并断言替换锚点存在，不维护生产文件的手工副本。

**安装简洁性条目**由 `tests/setup-preflight.py` 的 `check_setup_preferences()` 提供并已接入统一门禁：验证首次保存、二次摘要复用、`--choose`、`-y` 和新增模块默认值，确保用户确认一次配方后不被旧问题反复追问；同时覆盖凭据不写入、只读零保存及并发／链接保护。测试直接提取生产函数并在临时 HOME 运行，不读取真实偏好文件。

**公共规范块条目**由 `tests/setup-preflight.py` 的 `check_agents_tail()`、`check_agents_tail_old_cache()` 与 `check_agents_tail_migration()` 提供并已接入统一门禁：`check_agents_tail()` 在隔离 HOME 里跑真实的 `inject_agents_md`，验证公共块只写各已安装宿主的用户级文件、重跑幂等、`AGENTS_TAIL=0` 零写入、`AGENTS_TAIL_HOST` 显式目标，以及 Codex 非空 override 与 Pi 现有规则文件被保留、残缺标记不被吞；`check_agents_tail_old_cache()` 把新 setup 的委派块接到一个仍写回 `$PWD/AGENTS.md` 的旧缓存 `skills-sync.sh`，验证它被发现、报错并以 `AGENTS_TAIL=0` 拒绝，不往当前项目写；`check_agents_tail_migration()` 在隔离 Git 夹具仓库跑真实 `scripts/migrate-agents-tail.py`，验证默认只预览、无宿主或用户级规则未部署时不清项目块、只有与发行历史完全匹配的块才被清理并留备份、定制块原样保留。三者都必须清除宿主目录环境变量并重定向 `HOME`，否则会改写本机 live 指令文件。

**Multi-agent 主动发现条目**由 `tests/setup-preflight.py` 的 `check_multi_agent_auto_trigger()` 提供并已接入统一门禁：公共规则必须在实质独立线索出现时主动加载 `multi-agent`，`steady-do` 必须路由两个以上实质独立分支，skill description 必须包含非显式触发语义；同时锁定无合格分支、`quick-do` 和 skill 缺失时保持单会话。条目在隔离 HOME 运行真实 `inject_agents_md`，确认 OpenCode 和 Pi 的用户级文件都收到完整公共块。这验证分发，不验证模型执行。

Antigravity 的文件接入由 `tests/source-bench.py` 通过 `skills-sync.sh --antigravity base` 验证：清单路径能读到已安装的 Skill，重跑保留用户过滤条件，拒绝规则同步或遇到坏清单时保留原文。宿主实际发现另在 Customizations 或 `/skills` 核对。

统一入口的 `check_unified_update()` 在隔离 HOME 运行 `setup.sh`，核对多宿主只分发一次公共项、继承旧组选项、复用或更换名单及子进程错误传播。夹具只替换会联网或升级宿主的步骤；它不证明真实客户端升级成功。

该确定性条目保护引导契约，不证明模型每次都会委派。真实模型补充验收使用隔离配置，输入不出现 multi-agent、subagent、并行等提示词，例如：“只读调查：分别梳理 skills-sync.sh 的分组同步与 scripts/migrate-agents-tail.py 的规则迁移，各自给出入口、关键函数、失败路径和证据，最后汇总。”预期 `skill(multi-agent)` 先于任何 `subagent` 调用，主会话最终集成；记录宿主、模型、版本和事件序列。单次未触发应如实报告并调整引导，不得把静态通过写成行为通过。

同一条目也检查 `按计划执行` 和 `Swarm` 能从 skill 描述发现，且 Plan Brief 的执行段接到 Steady Do 和 Multi Agent。原会话续跑另用两条真实输入验收：在临时项目要求“先规划调用签名迁移”，确认只新增计划、旧调用仍能运行；向**同一会话**发送“按该计划执行到本地验证”，检查新签名生效、旧位置调用被拒、调用方输出不变、计划中有实测结果。单人即可完成，不以 worker 数量判定成功。

### DeepSeek Flash 源码派单（阶段性实机条目）

只在 OpenCode 子代理模型、派单指引变化或碎片化读取复现时运行。用隔离配置加载待验的 `multi-agent`，将题中的 `<角色>` 换成本次受影响的 `explore` 或 `general`；两者都受影响就分别跑。不在题里提示用哪些工具：

> 用 multi-agent 派一个 `<角色>`，只读查 `templates/`：Pi、Codex、Claude Code、OpenCode 的两种 Reviewer 各指向哪个规范文件？这四个宿主里谁把两种角色定义在同一个文件里？给出路径和行号。

核对答案：只有 OpenCode 把两种定义放在同一文件；Claude Code 引用 `~/.claude/skills/`，其余三者引用 `~/.agents/skills/`，分别指向 `verification/references/reviewer.md` 和 `consolidator/references/reviewer.md`。再看**实际发出的子任务和子会话工具轨迹**：父代理是否传入读法、实际模型是谁、独立查找或读取是否在同一助手回合发出。记录答复前的工具批次；逐轮用 shell 切片或在 `execute` 里尝试包装 shell 都算偏离。正常执行或读取工具故障后的只读回退不算。

决定能否退役时，固定宿主、角色、模型和源码，用两个新会话对照有、无专项读法的派单，核实实际子角色和提示。若无提示也能在这道题和实际源码调查中稳定答对、成批取证，不再反复补读，就撤下该角色的专项要求；所有适用角色都不再需要时，再删共用措辞和本条目。一次答对或零 shell 都不足以定论。此项不进离线门禁。

## 模拟与真实宿主的边界

DSH 安装期校验复用 rc.2 的官方 schema、表达式和配置接口时，结论只能是“拒绝”或“未发现拒绝”。它不能证明宿主已经加载，也不应为复杂 Group／Include 行为另造一套语义推断；无法确定的结果应保守拒绝或交给真实宿主。

OpenCode 的原生角色加载可用本机二进制单独验收，配置与缓存均在测试临时目录，`--standalone` 不连接或抢占 live 服务；默认明确报告 HOST SKIP：

```bash
OPENCODE_TEST_BIN=opencode node tests/verification-agent.mjs
```

DSH 的完整部署事务场景需要显式注入**一次性隔离运行时**，默认只跑离线场景并明确报告 HOST SKIP：

```bash
DSH_TEST_RUNTIME=/path/to/isolated-dsh-runtime bash scripts/check.sh --with-tests
```

不得把该变量指向 live runtime。测试只读引用其包内容，会把会打补丁的包复制到临时目录；隔离运行时不再使用后可整体删除。

同一个隔离 runtime 还应运行真实子代理验收；它使用本地 dummy SSE，不联网或发送真实模型请求：

```bash
DSH_TEST_RUNTIME=/path/to/isolated-dsh-runtime node tests/dsh-subagent-host.mjs
```

该测试实际启动 headless，验证 `verification_review` 的工具 schema、真实委派与子会话收尾、执行层权限和平台白名单；还验证 `read → context_rewrite → 下一次请求` 会撤下原读取内容并保留纠正记录，且退役的 `context_output_read` 不出现在真实工具表。`--dump-config` 只作为前置定位，不作为加载证据。web／tui 内委派和真实审查模型路由仍未覆盖。

以下结论需要真实宿主证据，不能由离线模拟替代：

- 异步插件挂载顺序和运行时 `cwd`；
- TUI／PTY 交互、web 启动及 HTTP 响应；
- headless 请求、流式响应和真实插件树加载；
- Pi／OpenCode 的实际加载与用户操作路径。

真实宿主验收按各宿主 README 的维护说明执行，使用隔离配置、虚拟凭据和本地 dummy 服务，不发真实模型请求。`--dump-config`、进程仍存在、帮助信息或静态导出都不是加载成功证据。

## 功能复核与整理审查分开

Verification 回答“用户要求的功能是否正确”。功能复核依据验收条件、真实使用路径、可复现证据和高风险场景；新功能及跨模块、高风险、发布或证据存疑时使用 `verification` 技能并委派 `verification-reviewer`，让它确认关键测试确实能因旧缺陷失败。角色未注册时必须披露；临时 `general` 审查不算角色安装验收。`consolidation-reviewer` 只服务显式整理任务，检查语义保持、简洁性及误删／该删未删，不作功能验收或发布签收。

本机专项检查、真实宿主验收和离线门禁分别报告，不能合并成一句“全部验证通过”。
