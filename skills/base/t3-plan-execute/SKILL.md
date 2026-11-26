---
name: t3-plan-execute
description: 仅当用户在 T3 Code 的 Antigravity 会话中明确调用 t3-plan-execute 时使用。Antigravity 负责规划和审阅，获授权后由 T3 委派 OpenCode 实施。普通开发、提及本模式或执行子任务时不启用。
disable-model-invocation: true
---

# T3 Code：Antigravity 规划，OpenCode 执行

只有用户明确要求使用本 Skill（例如 `/t3-plan-execute`），且当前确为 T3 Code 的 Antigravity 主会话，才启用本模式。不能确认宿主或 Provider 时不启用；只讨论本模式不算调用。一次启用仅用于当前任务，不改变其他会话的默认流程。

这是当前的宿主组合；分工可随工具能力调整，交接与验收仍以项目为准。

## 1. 规划并等执行授权

- 在 Antigravity 主会话澄清需求，复杂任务用 [`plan-brief`](../plan-brief/SKILL.md) 写计划。明确用户可见行为、须保留的契约、依赖顺序、禁改范围、验收正反例和停止条件。用 [`trust-pyramid`](../trust-pyramid/SKILL.md) 先找已有 API、静态检查和可复现的行为证据。
- 只有用户明确要求实施或确认可以执行，才进入下一步。当前线程处于禁止写入的 T3 Plan 模式时，等用户切换；不提升权限或另建线程绕行。

## 2. 把计划交给 OpenCode

- 首次委派前用 `orchestrator_capabilities` 核对目标 Provider、用户选定的模型及选项。用 T3 `delegate_task` 指定 OpenCode 实例和已确认的 `target.model`。模型未定则请用户选择；无对应模型、权限或委派工具就说明阻塞，不静默换模型或走 CLI 旁路。
- 默认共用当前工作区。派单自包含：计划位置、工作区与基线、允许写入的文件和禁区、验收入口、质量档、Git／外部操作授权和中止条件。子任务不继承完整对话；不要发送凭据。只有本任务许可时，才在派单里明确允许按 [`multi-agent`](../multi-agent/SKILL.md) 调用 OpenCode 的末级原生子代理。
- OpenCode 负责实施和集成。标准档先完成实现，再单独检查本次差异并做 [`unslop-changes`](../unslop-changes/SKILL.md)，然后跑项目检查和真实路径，最后用 [`verification`](../verification/SKILL.md) 调用其原生 `verification-reviewer`。轻量档和强制复核沿用项目规则。回传最终差异、实际结果、复核结论和未验证项。
- 按 T3 的完成通知或返回的 `next` 继续，不轮询。核对实际目标与模型；收到阻塞先处理原因，不重复派单。

## 3. 审阅最终差异并处理返工

- 由 Antigravity 对照计划、冻结差异和验证结果，检查实现是否绕路、有无多余抽象或防御、真实保护是否保留。值得独立判断时，用 Antigravity 原生 `define_subagent`／`invoke_subagent` 派临时只读审查，给它同一份材料；要求返回具体位置、后果和最小修法。
- 这轮审阅不替代 OpenCode 的独立功能复核。只有用户明确要求 [`consolidator`](../consolidator/SKILL.md) 整理时，才按其规范安排 `consolidation-reviewer`；普通 Unslop 不启动该角色。
- Reviewer 不编辑。Antigravity 主会话可在授权内小修不影响行为的说明；逻辑、接口、校验和断言问题交回 OpenCode 定点修。返工后补跑受影响检查并复核最终版本。向用户交付结果和仍未验证的事项。
