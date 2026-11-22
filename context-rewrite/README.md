# 近期纠错

| 能力 | 时机 | 保留内容 |
| --- | --- | --- |
| `context_rewrite(ids, note)` | Agent 读过结果，判断无用 | 发送视图移除调用与结果，留下纠正记录；宿主原始历史不删除 |
| 宿主原生输出门控 | 新工具结果产生时 | 原生截断提示、输出文件与分页；本套件不再复制第二份快照 |

**都不回滚文件、命令、进程或外部服务的实际变化。** `context_rewrite` 只改变发送给模型的视图。

使用 [acp-kernel](https://github.com/ranxianglei/acp-kernel) **0.0.101** 的编号与局部吸收 API；相关项目：[billion-context](https://github.com/ranxianglei/billion-context)。许可证及产品出处标注条款见 [ACP-KERNEL-LICENSE](ACP-KERNEL-LICENSE)。不启动代理、全局压缩流水线或自动更新。

## Agent 用法

工具结果在模型上下文中带独立标记：

```text
[context_op id=42 tool=bash]
```

```json
{
  "ids": [42],
  "note": "该命令已执行，但使用了错误的 Python 环境。下一步用项目 .venv/bin/python 运行同一脚本；保留已确认的输入路径。"
}
```

- 适用：过大的无用读取、已定位原因的错误尝试、已经放弃的探索路径。
- note 写清：已经做过什么、应保留的事实、错误原因、下一步正确参数或工具。不要因为原记录消失就重做旧步骤。
- **不是 Magic Context 的 tag**；数字 ID 只对应当前会话分支中的顶层工具调用。codemode/batch 整批算一项，不单独撤内部子调用。
- 直接调用本工具；不要包进 codemode/batch，也不要和待观察结果的操作一起调用。
- 默认窗口：按发起顺序计，最近 **10 次已完成**的普通工具调用；纠错工具自身不占号。已撤下操作仍占原窗口位置，不能连续裁剪来追溯旧历史。
- 批量参数先全部校验；任一 ID 无效，整批不生效。未完成、未展示、已处理和超出窗口的操作不接受。
- 用户指令、未解决证据、仍在编辑的源码、重要的同批结果不要撤下。是否值得纠错由 Agent 判断，不按输出长度自动执行。

通过启动宿主前设置 `CONTEXT_REWRITE_WINDOW=20` 修改窗口；必须为正整数。工具描述会显示实际配置值。

## 大输出使用宿主原生能力

本次变更从新资产中移除自动外置和 `context_output_read`：Pi、OpenCode、DSH 已经各自提供截断提示、完整输出文件或 spill，以及带 offset/limit 的原生 Read。三宿主禁用自研外置后的真实模型验收均已通过，因此不再维护第二套阈值、快照和取回工具。**发布后重跑对应 setup 并重启宿主才生效；源码或候选包本身不改变 live。**

- 大文件或命令输出被截断时，按原生返回的 `offset`、`limit`、`fullOutputPath`、`outputPath` 或 spill 路径继续读取；不要为了恢复输出盲目重跑有副作用的命令。
- 编辑前读取应看当前源文件，不依赖历史快照。一次性聚合可用原生 Bash／Python 处理绝对路径，只打印结论；反复检索才显式 `ctxm_index(path)`。
- 主宿主仍关闭 context-mode 的自动结果替换和上游路由拦截，避免与原生门控竞争；Pi 子代理保留上游保护。ctxm 只承担显式执行、索引与检索。
- 原生落盘的完整性由宿主自身能力决定；本套件不再复制或声称补回宿主已经丢失的输出。

### 旧快照兼容

既有 `[context_output]` 指针中的路径是普通 UTF-8 文本文件。升级不会删除这些文件，也不会自动把正文塞回历史；需要时用原生 Read 的 offset/limit 读取，或用 Bash／Python 聚合。DSH 曾允许把快照自定义到受管 runtime 内：部署会按 `<64位SHA-256>.txt` 契约保留到新 runtime 的相同相对路径，显式遍历包含隐藏目录且不跟随符号链接；内容冲突在任何配置预置前停止，不用新资产覆盖，也不留下临时文件或备份。旧指针中的 `context_output_read` 提示已被新提示取代，不要求保留该工具。跨机器迁移会话时，如仍需这些历史文件，应一并迁移。

## 会话与 Magic Context

- `context_rewrite` 只变换发送视图，不删除原始会话。TUI 原始工具输出仍在；操作 ID 标记属于发送给模型的视图，不保证出现在原始工具面板。
- 成功记录存入工具结果的 `details`（Pi）或 `metadata`（OpenCode）；重开时重放，不另建数据库。
- 原工具的输入与结果一起撤下；仅剩 thinking 的对应消息也会移除。混合消息中的其他调用、正文保留。
- 纠错工具自身保留真实调用参数；后续请求把结果中的重复 note 去掉，保留机械标记。原始会话仍保存完整参数和结果。
- Pi 使用 `context_with_system`，晚于 Magic Context 的 `context`。OpenCode 须在 Magic Context 后加载本插件，且不可再叠加另一个重建完整历史的压缩插件。
- Magic Context 继续负责历史压缩、记忆、搜索与历史展开；本插件不修改其数据库、tag、调度和配置。
- 编辑位置之前的相同前缀仍可复用缓存，之后需要重新计算；不承诺零缓存失效。首次在已有会话启用时，会给可见工具结果添加 ID，可能产生一次更早位置的缓存失效；后续同一分支的编号与标记保持稳定。

## 安装与试用

### OpenCode V2

```bash
bash opencode-setup.sh --check
bash opencode-setup.sh --plugins-only
```

V2 预构建包包含 `context_rewrite`，旧散装入口备份到 `$CFG/.agent-skills-backups/` 后停用。更新会替换受管插件资产；已有历史快照文件不删除。重开宿主生效，不要叠加整包与独立纠错插件。

### Pi

根包 `pi.extensions` 已包含入口，`acp-kernel` 由根依赖声明：

```bash
bash pi-setup.sh
# 随后 /reload
```

setup 从本地源码树准备 `~/.pi/agent/vendor/agent-skills` 和锁定依赖，无需再登记单独扩展。开发调试可在仓库根运行：

```bash
npm --prefix context-rewrite ci --ignore-scripts
pi --no-extensions -e ./pi/extensions/context-rewrite.ts
```

不要同时加载已安装包与工作区入口。

## 运行边界

- Pi：每次请求读取内存中的当前分支；只拼接窗口内结果的文本。
- OpenCode v2：读取 `session.context` 返回的当前宿主上下文并重建索引，再过滤发送视图。
- DSH：同一 assistant 步的并行工具作为一个操作，只替换活动 surface，原始事件留日志。
- 各端仍需遍历调用索引，不是与会话长度无关的常数开销。
- Windows 实机与所有 provider、长会话压缩组合未完整覆盖。

最小核心检查：`node context-rewrite/demo.mjs`。实机试用可让 Agent 读取不存在的文件，随后纠错并改读正确路径；观察固定纠错记录、正确重试，以及重开后的结果。
