---
name: verification-setup
description: "为新项目或已有项目扫描风险面、与用户对齐并搭建 Static Analysis、Verification 与 Evaluation 基座。用户要求搭建验证体系、构建 Verification/Eval/测试门禁、扫描项目缺哪些检查、补齐测试基座时使用。日常单次改动复核用 verification，规则配方查 trust-pyramid。"
---

# Verification Setup：从项目扫描到三层反馈基座

用于项目冷启动或阶段补课：先由 Agent 主动扫描代码与运行表面，整理出覆盖 **Static Analysis（静态检查）、Verification（确定性功能验证）与 Evaluation（质量／性能评测）** 的分层蓝图与用户对齐，获确认后再落地可自动运行的最小基座。

日常单次开发改动的增量回归与独立复核仍归 [`verification`](../verification/SKILL.md)；单项质量规则配方与工具配置查 [`trust-pyramid`](../trust-pyramid/SKILL.md)。本技能默认只读停在蓝图确认，不在第一轮擅自改项目代码。

## 1. 只读扫描现场（先做功课，不空手发问）

- 先读项目根 `AGENTS.md`（含 `user-discipline`）、README、依赖清单、已有检查／测试脚本与 CI 配置，建立对语言、运行时与命令入口的直接证据，不凭目录猜环境。
- 盘点全部用户可见表面（Surfaces）：例如 CLI／TUI、Web／桌面界面、HTTP／RPC API、库与脚本、插件／多宿主配置、PyTorch／算法或 Agent 管线，列出各自入口、启动方式与隔离难度。
- 根据命中的项目形态，读取 [领域风险探针与反伪绿灯清单](references/domain-probes.md) 的对应小节，结合当前仓库实际调用链初筛高代价失败面、已有防线缺口及是否需要 Evaluation 层。
- **完成判据**：输出一张简洁的项目验证现状快照（项目表面、已有检查、识别出的 P0／P1 风险缺口及当前缺失的隔离条件）。

## 2. 反例驱动对齐蓝图（默认停顿点）

- 基于扫描结果提出一份**分三层的推荐验证蓝图草案**，每项写清四件事：防什么具体事故、落在哪一层（Static Analysis／Verification／Evaluation）、运行耗时与隔离边界、优先级（P0 本轮必落／P1 后续按需）。
- 只向用户提 2–4 个会改变蓝图架构的未决问题，每项附推荐答案与简短取舍：
  1. **不可接受的 Top 3 事故**：哪些是绝对底线（防丢数据、安全边界、核心契约、数值等价），哪些本轮暂缓；
  2. **是否启用 Evaluation 层**：是否存在无法用布尔断言判对错的质量／指标／Agent 行为目标，还是静态检查加确定性 Verification 已足够；
  3. **离线快跑 vs 真实环境边界**：哪些必须做到离线隔离、Agent 改完代码可秒级自跑，哪些依赖真实服务、GPU、宿主机或密钥（按需触发或留给人工验收）；
  4. **本轮落点与执行方式**：先落最小可用骨架（单一门禁 + 黄金路径 + 核心反例），还是连同 Eval 基线一并落地。
- **默认停顿门禁**：若用户仅请求扫描、设计或未给出明确落地授权，停在蓝图草案并以“验证蓝图待确认，尚未修改项目”收尾，严禁提前新建测试文件或改配置。在 T3 Code 的 Antigravity 主会话中，若蓝图获批且落地跨模块，可按 [`t3-plan-execute`](../t3-plan-execute/SKILL.md) 委派 OpenCode (GPT) 实施并由原生 Gemini 子代理审阅测试结构与信噪比。

## 3. 按杠杆分配三层设计（Ponytail 护栏）

优先把问题拦截在成本最低、信号最硬的层级；不在项目里另造通用测试框架或平行平台，维护成本高于所拦风险的检查不建。

- **L1 Static Analysis（毫秒～秒级，零运行）**：承接类型、lint、依赖方向、配置 schema、敏感值扫描与入口资产闭包。工具选型直接复用 [`trust-pyramid/references/static-checks.md`](../trust-pyramid/references/static-checks.md)；给 Agent 看的报错必须自带“文件与位置、违背的约束、正确替代”。
- **L2 Verification（秒～分钟级，二值 Pass／Fail）**：
  - 统一收口到项目已有的单一检查入口（如 `scripts/check.sh`、`npm test`、`pytest`、`Makefile`），把快检与需要外部前置的慢检分开；
  - 为每个关键 Surface 提供最小可编程驱动与独立隔离沙箱（临时 `HOME`／数据库／配置／本地 stub，零污染 live 环境）；
  - 用 [`problem-framing`](../problem-framing/SKILL.md) 的反例思路定界：每条核心契约至少覆盖 1 个真实用户正例与 1 个高代价失败反例（如越界路径、非法输入、配置冲突、故障回滚、重复执行幂等）。
- **L3 Evaluation（按需，连续指标／质量对比）**：仅在输出无法靠布尔 `assert` 判对错时建立（如 LLM／Agent 行为、算法与模型精度、检索召回、性能与显存、UI 观感）。必须写齐四要素：代表性样例集（Golden + 边界／难例，区分调优集与留出验收集）、可复现采集脚本、分层打分（确定性检查优先，主观维度配清晰 rubric 或人工抽检锚点）、基线记录与退化阈值。

## 4. 最小落地与红灯证明

获得用户实施授权后，按蓝图最小完整落地，并按以下标准验收基座本身：

- **单一入口与诚实 SKIP**：所有新增静态检查与行为回归接入项目已有统一入口；缺外部前置（真机宿主、GPU、凭据、外部服务）时必须显式输出 `SKIP` 与原因，不得静默退出 0 冒充通过。同时核对 [反伪绿灯清单](references/domain-probes.md#反伪绿灯自检清单)，杜绝 mock 自洽或空跑绿灯。
- **红灯证明（Red-first／Mutation）**：每条新落地的核心静态规则或行为回归，交付前必须在对应的最小违规样例或临时故障注入上**实际运行并确认会 `FAIL`**，恢复后实跑 `PASS`；只见过绿灯、未证明能拦错的条目不得报验收通过。
- **单一证据文档**：在项目已有验证说明（如 `tests/README.md`；无则就近补在项目约定文档中）记录极简 Surface Map（每表面一行：入口、驱动手段、隔离方式、前置条件）以及“离线模拟覆盖什么、哪些必须由真实环境／用户验收”，不另建平行台账。
- **遵循项目质量档**：标准档落地后执行 [`unslop-changes`](../unslop-changes/SKILL.md) 清理本次改动，再跑通统一检查入口并按 [`verification`](../verification/SKILL.md) 完成独立复核。

## 5. 交棒给日常演化循环

验证基座验收后即收口，后续由现有技能接管日常演化：

- 后续每次新功能开发 → 按 [`verification`](../verification/SKILL.md) 沿本次搭好的入口增量沉淀单条最小回归，并由 `verification-reviewer` 默认快查相关旧条目；
- 后续同一类缺陷反复出现两次 → 按 [`trust-pyramid`](../trust-pyramid/SKILL.md) 升格到更硬的架构、类型或静态检查层；
- 项目演化导致检查或条目漂移 → 按 `verification` 的「维护：三分法与终局」翻新，产品缺陷不得通过放松断言来掩盖。
