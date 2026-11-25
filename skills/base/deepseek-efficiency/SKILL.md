---
name: deepseek-efficiency
description: Optimize file inspection when explicitly invoked for DeepSeek as a primary or subagent. Use only when the user asks for deepseek-efficiency or explicitly requests this DeepSeek file-reading workflow. Combine with the task's normal workflow; subagent dispatch remains with multi-agent.
---

# DeepSeek 文件读取效率

用户显式调用本 skill 时，在当前任务中使用以下读法；主 Agent 和子 Agent 都适用。它不切换模型、不改变任务范围，也不代替 `quick-do`、`steady-do` 或项目的验证要求。

## 按动作选工具

- 找路径用宿主原生 `Glob`，找内容用 `Grep`；已知文件或命中位置直接用 `Read`。Pi 对应 `find`、`grep`、`read`，以当前宿主实际工具表为准。
- 读短文件直接读完整内容；长文件先定位，再读足以理解的完整相关块。已有源码或结果仍适用时复用，不反复搜索和小片切读。
- 有多个互不依赖的查找或已知文件时，在宿主支持的情况下同一回合发出独立原生调用；依赖前一步结果的操作再接着做。不为凑并行扩大读取范围。
- 文件查找和读取直接调用原生工具，不用 Shell 的 `find`、`grep`、`cat`、`sed`、`head` 等代替，也不通过 Shell 或 Code Mode 包装原生调用。输出少不是改用 Shell 的理由。
- 编辑使用宿主原生编辑工具。Shell 留给运行程序、测试、构建、Git、环境探测和确实需要的聚合计算；已有更合适的专用索引或文档工具时，遵循项目约定使用。

原生工具不存在或实际失败时，可以使用只读 Shell 回退；权限拒绝不是绕过权限的理由。证据足以完成任务时停止查找，继续实现和验证，不为整理工具轨迹增加额外轮次；临时文件和进程仍按任务要求清理。

## 演化

按实际 DeepSeek 任务的工具轨迹修订本 skill：记录宿主、模型、任务与误用，再将可迁移的修正回流源码；不把一次成功当成稳定提速的证明。`multi-agent` 保留对子任务的简短交接要求，不要求所有任务加载本 skill。
