# 近期纠错与大输出外置

| 能力 | 时机 | 保留内容 |
| --- | --- | --- |
| `context_rewrite(ids, note)` | Agent 读过结果，判断无用 | 发送视图移除调用与结果，留下纠正记录；宿主原始历史不删除 |
| 自动外置＋`context_output_read` | 新工具结果产生时 | 原文存入持久文件；会话及模型先看到预览、大小、状态与指针 |

**都不回滚文件、命令、进程或外部服务的实际变化。** 外置不要求 Agent 放弃全文：显式取回支持完整源码；无用的指针或取回结果仍可用 `context_rewrite` 撤下。

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

## 大输出外置与原文取回

默认：普通工具文本 **≥16 KiB（UTF-8 字节）**时外置；原生已经截断并留有输出文件时也会保存副本。不追溯处理旧结果，不按 token 猜大小。

- 占位符：`[context_output]`、SHA-256 id、绝对路径、保存范围、字节数、行数、执行状态、首尾预览。预览不等于全文；不要仅为取回内容重跑命令。
- 长源码：原生 `read` 触发外置时，保存**外置时完整源文件快照**，不是仅保存宿主返回的 50 KiB 或指定行片段。后续源文件修改不影响这个快照。
- 命令输出：有可信的宿主落盘路径时，复制到持久目录；否则只保存实际收到的文本，明确标注它可能已被宿主截断。
- MCP 多个文本块合并保存，图片及其他非文本内容保留。记忆控制、问卷、`context_rewrite`、`context_output_read` 不自动外置；OpenCode `read` 携带项目指令时保持原样。
- codemode 内部子调用不外置，脚本继续获得原数据；只对最终给模型看的大文本处理。
- OpenCode v1 未经过 `tool.execute.after` 的抛出异常保持原样；普通 shell 非零退出码仍会进入外置流程。保留的错误可再用 `context_rewrite` 处理。
- 写文件失败：不返回空指针，保留原始输出并报告错误。

取回使用占位符中的完整 id：

```json
{"id":"<64位SHA-256>","full":true}
```

这是 `context_output_read` 的参数。**显式全文取回不再自动外置，也不再次套宿主 50 KiB 截断**；源码、命令结果均可取回。它不突破模型上下文窗口：特别大的文件应分页读取，仍可覆盖全部内容。

```json
{"id":"<64位SHA-256>"}
{"id":"<同一id>","offset":32768}
```

默认每页最多 **32 KiB**；`offset` 是字节偏移，必须使用上一页给出的 `next_offset`，不是行号。UTF-8 字符不拆断；读到 `eof=true` 表示到达快照末尾。`full=true` 不接受非零 offset。

分析不必把原文送回模型：可用 `ctxm_execute` 直接处理指针绝对路径，仅输出所需结论；`ctxm_execute_file` 限工作区内路径，不能直接读取默认外置目录。

### 存储与开关

| 项 | 取值 |
| --- | --- |
| `CONTEXT_OUTPUT_BYTES` | 默认 `16384`；`0` 停用新输出自动外置，不影响原文取回 |
| `CONTEXT_OUTPUT_DIR` | 可指定绝对目录；默认用户数据目录下的 `agent-skills/context-output/` |
| Linux 默认目录 | `~/.local/share/agent-skills/context-output/`；遵循 `XDG_DATA_HOME` |
| Windows 默认根 | `LOCALAPPDATA`；未设置时使用用户目录 `.local/share` |
| 文件 | `<SHA-256>.txt`，相同字节共用同一文件；流式保存，临时文件完成后原子替换 |
| 隐私 | 新建目录 `0700`、文件 `0600`（权限语义依宿主文件系统）；可能包含私密日志，不上传、不入仓库 |
| 生存期 | 持久保留，不自动清理；手动删除会使历史指针失效。迁移会话时需同时迁移这些文件 |

启动宿主前设置环境变量，修改后重启。若停用插件，既有指针仍是普通文件路径，可用原生读取工具访问；不会自动把外置正文塞回历史。

### OpenCode 原生输出的已知边界

OpenCode 1.18.35 的 shell 大量快速输出可能在原生落盘前丢失，见 [上游 #40728](https://github.com/anomalyco/opencode/issues/40728)。因此其原生溢出文件标为 `host_saved_output_completeness_unverified`，不承诺补回宿主已丢的数据。完整性敏感的命令应在首次执行时自行重定向到日志文件，再读取该文件；不要未经判断重跑已完成的有副作用命令。完整源码快照不走这条 shell 输出链路。

OpenCode 2.0.26 已改为等待输出流完成。v2 适配通过进度事件保留原生 Shell 文件 ID，再持久复制完整输出；1,120,030 字节、40,002 行、退出码 7 的真实模型调用已逐字节核对一致。该结果不等于所有命令和异常终止场景都已覆盖；v1 的上述警告仍有效。

## 会话与 Magic Context

- `context_rewrite` 只变换发送视图，不删除原始会话。TUI 原始工具输出仍在；操作 ID 标记属于发送给模型的视图，不保证出现在原始工具面板。自动外置则在新结果到达时落盘，会话从一开始保存指针；不改写已有历史。
- 成功记录存入工具结果的 `details`（Pi）或 `metadata`（OpenCode）；重开时重放，不另建数据库。
- 原工具的输入与结果一起撤下；仅剩 thinking 的对应消息也会移除。混合消息中的其他调用、正文保留。
- 纠错工具自身保留真实调用参数；后续请求把结果中的重复 note 去掉，保留机械标记。原始会话仍保存完整参数和结果。
- Pi 使用 `context_with_system`，晚于 Magic Context 的 `context`。OpenCode 须在 Magic Context 后加载本插件，且不可再叠加另一个重建完整历史的压缩插件。
- Magic Context 继续负责历史压缩、记忆、搜索与历史展开；本插件不修改其数据库、tag、调度和配置。
- 编辑位置之前的相同前缀仍可复用缓存，之后需要重新计算；不承诺零缓存失效。首次在已有会话启用时，会给可见工具结果添加 ID，可能产生一次更早位置的缓存失效；后续同一分支的编号与标记保持稳定。

## 安装与试用

### OpenCode：随套装安装

v1/v2 均已接入 `opencode-setup.sh`；先退出 TUI 和后台服务，再按需运行：

```bash
bash opencode-setup.sh --check         # 预检管理路径、旧入口与配置
bash opencode-setup.sh --plugins-only  # 更新插件，不更新通用 skills／模型／Python
# 新机器安装完整套装：bash opencode-setup.sh
```

脚本获取方式与迁移边界见 [OpenCode 分发说明](../opencode/README.md)。旧散装或旧 v1 入口备份到 `$CFG/.agent-skills-backups/` 后停用，不需手工删除；重启宿主生效。**不要叠加整包与独立纠错插件。**

| 层 | 源码与分发 |
| --- | --- |
| 公共核心 | `core.mjs`、`output-store.mjs`，Pi／OpenCode 共用 |
| OpenCode v1 | `opencode/plugins/context-rewrite.js`，打进 v1 bundle |
| OpenCode v2 | `opencode/v2/context-rewrite.js`，打进 v2 目录包 |

当前是共用核心、两套宿主适配与分发资产，不是单一双入口包。setup 只迁移插件／配置；宿主会话库由 OpenCode 管理，已有外置正文不因插件升级而删除。跨机器迁移会话时仍需同时迁移正文文件。

### Pi：本机试用

Pi 尚未接入根包清单，仍可在仓库根目录试用：

```bash
npm --prefix context-rewrite ci --ignore-scripts
pi -e ./pi/extensions/context-rewrite.ts
```

Pi 长期本机试用：把该文件的绝对路径加入 `~/.pi/agent/settings.json` 的 `extensions` 数组，保留其他条目，随后 `/reload`。不要同时以两种方式加载。

### OpenCode v1：仅开发调试

单独调试 OpenCode 1.18.35 时，可构建独立入口（不能与 setup 的整包同时加载）：

```bash
bun build opencode/plugins/context-rewrite.js --target=bun \
  --external @opencode-ai/plugin --outfile /tmp/context-rewrite.js
```

比较并备份已有文件后，将产物部署到 `~/.config/opencode/plugins/zz-context-rewrite.js`。将本 README 和许可证一并放入 `~/.config/opencode/context-rewrite/`。保持 Magic Context 配置插件先加载、此本地插件后加载；重开 OpenCode 生效。

OpenCode v2 使用独立适配入口，见 [`opencode/v2/README.md`](../opencode/v2/README.md)；不要向 v2 自动发现目录部署上述 v1 插件。

撤回试用：Pi 只移除新增的扩展路径；OpenCode 移除相应插件登记或自动发现入口。`context_rewrite` 撤下的记录会重新出现；外置过的正文仍在文件里，不自动展开。不要用旧备份整块覆盖其他配置。

## 运行边界

- Pi：每次请求读取内存中的当前分支；只拼接窗口内结果的文本。
- OpenCode v1：每个会话首次请求读取原始历史，之后通常只读取最近 `窗口 + 1` 条消息；发现历史回退或分页断层才重新读取全部。缓存只留调用索引、纠错记录和窗口内文本。
- OpenCode v2：读取 `session.context` 返回的当前宿主上下文并重建索引，再过滤发送视图；旧历史迁移、普通重开已验收，长期压缩交错仍待实用观察。
- 两端仍需遍历调用索引；不是与会话长度无关的常数开销。
- 验收基线：Pi 1.1.0、OpenCode v1 1.18.35／v2 2.0.26、Magic Context 0.45.0。短链路共存不等于所有 provider、长会话压缩和 TUI 场景均已验收；Windows 实机未覆盖。

最小核心检查：`node context-rewrite/demo.mjs`。实机试用可让 Agent 读取不存在的文件，随后纠错并改读正确路径；观察固定纠错记录、正确重试，以及重开后的结果。
