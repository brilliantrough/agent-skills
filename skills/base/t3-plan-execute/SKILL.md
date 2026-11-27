---
name: t3-plan-execute
description: "在 T3 Code 的 Antigravity 主会话启用“Gemini 规划与品味审查 + OpenCode (GPT) 执行与功能复核”双核开发。用户调用 t3-plan-execute，或要求在当前会话敲定方案后交给 OpenCode 实施、双核协作时使用。其他宿主主会话、脱离 T3 的独立会话或子代理不启用。"
---

# T3 Code 双核开发：Gemini 规划审查，OpenCode (GPT) 执行验证

仅在 T3 Code 的 Antigravity 主会话中，当用户调用本技能，或明确要求“在当前会话定方案、交给 OpenCode 实施／双核协作”时启用。OpenCode、Pi、DSH、Codex、Claude 主会话，脱离 T3 的独立 Antigravity，以及任何子代理均不启用；只读问答、仅讨论本模式或用户要求直接在当前会话完成的小改也不启用。

Antigravity（Gemini）负责前端需求对齐与后端结构、品味、观感审查；OpenCode（GPT）负责具体代码落地、去冗余与独立功能复核。**完整双核流程只是默认标准档，非强制门槛**：低风险小改可直接留在当前会话按 [`quick-do`](../quick-do/SKILL.md) 完成；即使用本模式，用户说“轻量档／简单来”时，OpenCode 端可省去单独 Unslop 与功能 Reviewer（安全边界与高风险改动除外），Antigravity 端也免拉独立审查子代理，由主会话快速复读核心差异后收口。

## 1. 对齐意图并收敛方案（Antigravity 主会话）

- 先用只读搜索、直接读取或已挂载的 `codegraph`／`claude-mem` 查清现有实现、真实调用链与 [`trust-pyramid`](../trust-pyramid/SKILL.md) 约束。事实自行查证，只向用户询问影响行为、范围、兼容性、风险或验收的未决选择，每项给出推荐方案与简短利弊。
- 按复杂度选择载体，不强加文档仪式：
  - 跨模块、多阶段或高风险改造：按 [`plan-brief`](../plan-brief/SKILL.md) 落盘计划文档；
  - 边界清晰的中等任务：直接在对话中收敛执行契约（目标与非目标、允许写入的文件与禁区、关键接口或状态约定、验收入口及质量档，默认标准档）。
- **完成判据与门禁**：方案边界、验收方式和质量档已明确，且获得用户明确执行指令（如“按这个做”“交给 OpenCode 跑”）。当前线程处于禁止写入的 T3 Plan 模式时，等待用户切换后再委派，不提升权限或新建顶层线程绕行。

## 2. 委派 OpenCode (GPT) 落地与功能复核

- **核对能力与默认模型**：当前线程首次委派前调用一次 `orchestrator_capabilities`（可带 `search: "gpt"`）核对 `opencode` 实例与模型参数：
  - 用户已指定模型或推理档时，严格按用户选择传参；
  - 用户未指定模型时，默认在 `target` 设 `providerInstanceId`（取 `orchestrator_capabilities` 返回的 `opencode` 实例，必要时附 `driverKind: "opencode"`）、`model: "codex-newapi/gpt-6.2-sol"`、`options: { "variant": "high" }`（复杂状态联动或高风险边界用 `"xhigh"`）；若无该模型则改查 `codex-newapi/gpt-6.2-astra`；仍无可用 OpenCode GPT 模型、缺权限或缺委派工具时直接报告阻塞，不静默换用其他模型家族或 CLI 旁路。
- **发起异步委派**：通过 T3 `delegate_task` 派单（Antigravity ACP 中若为懒加载工具，先读 `<appDataDir>/mcp/t3-code/delegate_task.json` 再经 `call_mcp_tool` 调用 `t3-code` 的 `delegate_task`）。设 `role: "implementation"`、`mode: "async"`、`interactionMode: "default"`，默认 `isolation: "shared"` 共用当前工作区；仅在用户授权隔离分支或并发写集冲突时设 `isolation: "worktree"`。发出后按 T3 唤醒通知或返回的 `next` 继续，不轮询 `task_status` 或 `sleep`。
- **自包含派单内容**（子任务无父会话历史，禁传凭据）：
  - 计划路径或对话执行契约、基线（当前 `HEAD` 与已有未提交改动，用户原有改动禁碰）、允许写入的文件集与禁区、Git／外部操作授权边界及中止条件；
  - 仅当本任务存在两个以上实质独立分片时，明确允许 OpenCode 按 [`multi-agent`](../multi-agent/SKILL.md) 调用末级原生子代理（`explore`／`general`），末级代理不得再向下委派；
  - **执行端必做流程**：默认标准档——完成实现后单独审视本次差异并执行 [`unslop-changes`](../unslop-changes/SKILL.md)，再跑项目静态检查与最小真实路径（新功能按 [`verification`](../verification/SKILL.md) 将最小可重复条目接入现有入口），最后调用 OpenCode 原生 `verification-reviewer`（`gpt-6.2-sol#max`）独立复核功能并快查相关旧条目。用户显式选轻量档时按项目规则裁剪，安全与高风险边界仍须复核。
- **完成判据**：OpenCode 回传改动文件与基线差异命令、实际执行的检查结果、`verification-reviewer` 结论，以及未验证项／SKIP；收到阻塞先排障或对齐，不重复发送同一派单。

## 3. 用原生 Gemini Sub Agent 审查结构、品味与观感

本轮审查与 OpenCode 的功能 `verification-reviewer` 正交互补，不代替也不重跑无关全量测试矩阵。

- **标准档默认拉起独立只读子代理**：收到 OpenCode 结果后先冻结相关文件。除用户显式选轻量档，或改动仅限几行纯配置／说明微调外，**必须通过 Antigravity 原生子代理启动一次干净上下文的只读审查**（用 `define_subagent` 定义 `EnableWriteTools: false` 的只读审查角色后调 `invoke_subagent` 且 `Model: "inherit"`，或直接调用内置只读 `research` 子代理；同 Provider 审查不走 `delegate_task`）。
- **审查输入与三项必查轴**：向子代理提供自包含材料（原定目标与计划摘要、基线与 `git diff` 命令及未跟踪新文件清单、OpenCode 验证摘要、项目 `AGENTS.md` 纪律；界面任务一并附上 [`personal-ui-taste`](../personal-ui-taste/SKILL.md) 要求），令其按严重度返回具体 `文件:行号`、后果与最小改法，聚焦三轴：
  1. **代码框架与模块边界**：职责拆分是否自然，状态归属与调用链是否清晰，有无跨层硬塞参数、散乱耦合或绕路补丁；
  2. **代码品味与 Ponytail 精简度**：命名、接口形状与控制流是否直白易读；有无 GPT 常见的机械堆砌、投机防御、透传包装或“该删未删”，同时核对真实信任边界、错误处理与防损校验未被误删；
  3. **人类观感与文本表达**：CLI／UI 交互层次与视觉细节、报错可定位性、注释及说明文档是否自然好读、无模板腔（面向人的文本按 [`readable-docs`](../readable-docs/SKILL.md) 短检查把关）。
- 仅在用户显式要求 [`consolidator`](../consolidator/SKILL.md) 整理时，才按其规范另走 `consolidation-reviewer`；日常开发不混用。
- **完成判据**：主会话核实子代理返回的发现，区分“值得改的结构／品味／功能问题”“纯文案微调”与“无实质收益的主观偏好”。

## 4. 定点返工与收敛交付

- **严守修改归属**：
  - 审查子代理始终只读，不修改任何文件；
  - 不改变代码逻辑、接口签名、配置键值或测试断言的**纯注释／说明文字微调**，可由 Antigravity 主会话在授权内直接完成，并跑对应文档或格式检查；
  - 凡涉及**代码结构重构、控制流、接口、UI 实现、校验逻辑或测试**的改动，**禁止 Antigravity 主会话亲手重写**，统一整理成聚焦的返工单（具体位置、原因、最小改法及必须保持的已通过行为），通过**新一次 `delegate_task`**（不向旧子线程发 `t3_thread_send`；首轮若用 `worktree`，先按授权合入当前工作区或在返工单以 `isolation: "shared"` 指明原 worktree 路径／分支）交回 OpenCode 定点实施。
- **返工验证与轮数护栏**：
  - 品味与结构调整服从真实行为契约和 Ponytail 原则：只做理顺职责或删减冗余的最小改动，不为形式对称引入新抽象层，也不削弱真实边界保护。
  - OpenCode 返工后必须补跑受影响检查与真实路径；触及行为、接口或安全边界时须重过 OpenCode 原生 `verification-reviewer`，再由 Antigravity 核对改动处。
  - **结构与品味返工最多 1 轮**（功能缺陷不在此限，须修通或将明确阻塞交回用户）；一轮返工后若功能与主干结构已稳妥、仅剩细枝末节的风格偏好，立即收口。
- **最终交付**：向用户集中交代完成结果、OpenCode 执行模型与功能复核结论、Gemini 结构与品味审查结论（含是否做过返工），以及仍需用户实机确认或未验证的事项。
