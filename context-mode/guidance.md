---
name: context-mode
description: On-demand code execution and FTS retrieval for large or noisy command output, local datasets, and repeatedly queried documents. Use native Read/Grep for exact source and edits, native Bash for short output and one-off local aggregation, and the host's native Code Mode for multi-tool/MCP orchestration. Not a default wrapper for every tool call.
---

# Context Mode：按下一步需要的信息选工具

目标是减少无关输入与无效往返，不是追求最高字节压缩率。

## 工具分工

| 本次需要什么 | 路径 |
|---|---|
| 编辑用原文、完整函数／配置块、已知位置的片段 | 原生 Read／Grep；不用索引摘要代替源码 |
| 短输出，或一次性的 Python／Node 过滤与聚合 | 原生 Bash，直接打印所需答案 |
| 组合多个宿主工具／MCP 工具并传递中间结果 | Pi／OpenCode 原生 Code Mode；context-mode 子进程不能调用宿主工具 |
| 一个本地命令或脚本产生的大日志／大输出 | `ctxm_execute(language, code)`，只打印行动所需的证据 |
| 分析一个本地大文件 | `ctxm_execute` 传 `file`，代码从 `CTX_FILE` 读取；精确原文仍用 Read |
| 多条命令的大输出，需要回答多个检索问题 | `ctxm_batch(commands, queries)`；命令按数组顺序串行执行 |
| 文档、目录或网页会被反复查询 | `ctxm_index` 后 `ctxm_search`；网页抓取是普通 HTTP，不执行 JS |
| 宿主压缩后恢复本 session 的证据 | `ctxm_resume`；记忆系统仍由 Magic Context 负责 |

多个独立的短读取用宿主并行调用。已在上下文中的结果直接复用，不重复索引或搜索。

## 自动输出外置只有一条链

本 fork 用 agent-skills 的 `context-rewrite/output-store` 处理自动大输出外置：保留无损文本快照、首尾预览和 `context_output_read` 精确取回。主宿主关闭 context-mode 的自动结果替换和上游路由拦截，避免两个占位符、重复检索以及 WebFetch／Bash 被强制改道。用户自己的 deny 规则仍然生效；Pi 子代理没有该 snapshot 扩展时保留上游保护。

- 要精确原文：用 `context_output_read` 分页或 `full: true`，不要重跑已完成的命令。
- 只需一次聚合：用原生 Bash／Python 处理指针里的绝对路径，直接打印结论。
- 同一资料需要反复检索：再显式 `ctxm_index(path)`，之后用返回的 `source` 查询；不要把每次读取都变成搜索任务。

## 一次返回足够行动的信息

调用前先确定下一步要做的决定。代码输出或 `queries` 至少给出需要的路径、符号／记录 ID、关键原文或实际值，以及失败状态和是否截断。未知结构先看目录、文件头部或相关逻辑单元；不要靠连续换关键词猜内容。

`ctxm_execute` 的 `intent` 是检索条件，不是任务备注：提供它就会索引并筛选输出；省略且整份回复不超过 16 KiB 时直接返回。大输出即使省略也会索引。因此代码已经能打印结论时不要加 `intent`，也不要大转储后再泛搜。

`ctxm_batch` 必须同时提供 `commands` 和非空 `queries`，适合检索而非原样消费几条短输出。索引命中是定位线索，不自动等于当前文件原文；单次分析直接打印答案，不必经过“索引 → 搜索”。

## 不使用的场景

| 工具 | 替代或限制 |
|---|---|
| `ctxm_execute` | 短输出／一次性内联脚本 → Bash；多个宿主工具编排 → 原生 Code Mode；编辑 → Edit／Write |
| `ctxm_batch` | 几条短结果直接消费 → 宿主并行；前项决定后项输入 → 分阶段调用；无 `concurrency` 参数 |
| `ctxm_index` | 单次分析 → 直接执行并打印答案；大文本不要内联进 `content`，用 `path` |
| `ctxm_search` | 已有足够证据 → 继续工作；未索引的资料 → 先读或先索引，不反复空搜 |
| `ctxm_stats` | 字节节省不等于整任务 token、轮数或时延；先核对返回范围 |
| `ctxm_purge` | 不是释放上下文或加速手段；范围不明先问，获授权后才 `confirm: true` |
| `ctxm_upgrade` | 本 fork 不调用；维护走 `context-mode/setup.sh`，目标机走套件 setup |

## 运行边界

- executor 在项目中运行子进程，不是安全隔离的文件系统；`file` 必须位于允许的项目根内。写项目文件仍用原生 Edit／Write。
- `timeoutMs` 默认及上限均为 600000。`background: true` 只用于已授权且确需的后台任务，用户长任务仍由其自行启动和观察。
- 清理部分注入型环境变量不等于隔离凭据；不要打印 secrets，不把大文本内联进 `code`。
- v2 不再提供 `ctxm_execute_file`、`ctxm_batch_execute` 或 `ctxm_fetch_and_index`：分别使用 `ctxm_execute(file=...)`、`ctxm_batch`、`ctxm_index(url=...)`。

具体参数以当前工具 schema 为准；无需为普通调用加载语言模板或旧 references。
