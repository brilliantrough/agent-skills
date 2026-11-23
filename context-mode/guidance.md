---
name: context-mode
description: Run and filter noisy commands, analyze local datasets, or index documents for repeated queries. For file tasks use the host's native Glob, Grep, Read and editing tools; use native Code Mode to coordinate host or MCP tools.
---

# Context Mode：按下一步需要的信息选工具

目标是减少无关输入与无效往返，不是追求最高字节压缩率。

## 工具分工

| 本次需要什么 | 路径 |
|---|---|
| 按文件名找路径；按文本或符号找位置 | 分别调用宿主的 Glob、Grep 工具（Pi：find、grep） |
| 读已知路径或命中区间；修改文件 | 直接用 Read 读完整相关块；修改用宿主的 Patch／Edit，新建可用 Write |
| 运行程序、测试或一次性计算 | 原生 Bash，直接返回结果 |
| 组合多个宿主工具／MCP 工具并传递中间结果 | Pi／OpenCode 原生 Code Mode；context-mode 子进程不能调用宿主工具 |
| 一个本地命令或脚本产生的大日志／大输出 | `ctxm_execute(language, code)`，只打印行动所需的证据 |
| 分析一个本地大文件 | `ctxm_execute` 传 `file`，代码从 `CTX_FILE` 读取；精确原文仍用 Read |
| 多条命令的大输出，需要回答多个检索问题 | `ctxm_batch(commands, queries)`；命令按数组顺序串行执行 |
| 文档、目录或网页会被反复查询 | `ctxm_index` 后 `ctxm_search`；网页抓取是普通 HTTP，不执行 JS |
| 宿主压缩后恢复本 session 的证据 | `ctxm_resume`；记忆系统仍由 Magic Context 负责 |

多个独立的短读取用宿主并行调用。已在上下文中的结果直接复用，不重复索引或搜索。

## 使用宿主原生输出门控

主宿主由 Pi／OpenCode／DSH 各自处理大输出：模型看到原生截断提示、输出文件或 spill，再用原生 Read 的 offset/limit 继续读取。本 fork 关闭 context-mode 的自动结果替换和上游路由拦截，避免与宿主门控竞争；用户自己的 deny 规则仍生效，Pi 子代理保留上游保护。

- 按原生返回的 `fullOutputPath`、`outputPath` 或 spill 路径读取；一次性聚合可用原生 Bash／Python 处理该路径。
- 既有 `[context_output]` 指针是普通文本文件，升级不删除；同样用原生 Read 分页，不再使用 `context_output_read`。
- 只有需要跨轮重复检索时，才显式 `ctxm_index(path=绝对路径)` 后 `ctxm_search`。不要为了恢复正文盲目重跑有副作用的命令。

## 一次返回足够行动的信息

调用前先确定下一步要做的决定。代码输出或 `queries` 至少给出需要的路径、符号／记录 ID、关键原文或实际值，以及失败状态和是否截断。未知结构先看目录、文件头部或相关逻辑单元；不要靠连续换关键词猜内容。

`intent` 是检索条件，不是任务备注：提供非空 intent 才会索引并筛选输出；省略且整份回复不超过 16 KiB 时直接返回。大输出即使省略也会索引。因此代码已经能打印结论时不要加 `intent`，也不要大转储后再泛搜。

`ctxm_batch` 必须同时提供 `commands` 和非空 `queries`，适合检索而非原样消费几条短输出。索引命中是定位线索，不自动等于当前文件原文；单次分析直接打印答案，不必经过“索引 → 搜索”。

## 不使用的场景

| 工具 | 替代或限制 |
|---|---|
| `ctxm_execute` | 普通执行或一次性计算 → Bash；多个宿主工具编排 → 原生 Code Mode；文件操作见上表 |
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
