---
name: context-mode
description: Derive focused answers from large logs, datasets, command output, or file collections without loading the raw bulk into context. Use for counts, filters, aggregation, noisy builds, and multi-command research with indexed retrieval. Use native Read/Grep for exact source or editing, native Bash for bounded output consumed directly. Not a default wrapper for every tool call.
---

# Context Mode：按下一步需要的信息选工具

目标：在质量不变的前提下，减少无关输入与无效往返；不是追求最高压缩率。原文阅读与聚合分析是不同任务，没有固定工具优先级。

## 选择工具

| 本次需要什么 | 优先路径 |
|---|---|
| 编辑用原文、理解完整函数／配置块、已知位置的短片段 | 原生 Read／Grep，保留当前逻辑单元；不先摘要再猜补丁 |
| 短输出，马上逐字消费 | 原生 Bash／Read；不为索引而包装 |
| 大日志／数据集中的计数、过滤、聚合 | `ctx_execute`；本地单文件用 `ctx_execute_file` |
| 多条命令，需要从大输出中组合结论并保留可检索记录 | `ctx_batch_execute`，本次问题一起放进 `queries` |
| 多个独立的短读取 | 宿主批量／并行调用；无需额外索引 |
| 已经索引、确实还缺的信息 | `ctx_search`，相关问题合成一个 `queries` 数组 |
| 资料会被多次查询 | 本地 `ctx_index(path)`；网页 `ctx_fetch_and_index` |
| 一次性网页检索／阅读 | 已配置的 MCP 搜索／抓取工具，如 firecrawl／tavily |

- 批量不等于并行：`ctx_batch_execute` 默认 `concurrency: 1`。仅独立且资源允许的命令并行；依赖前项输出、同文件写入、共享端口或浏览器的操作串行。
- 看完整逻辑时读取完整单元，不把每几行拆成一轮；超大生成文件先定位生成源和同步入口，不盲读整份产物。
- 已在上下文中的结果直接使用；源文件改变、证据缺失或上下文丢失才定向补读。索引命中是定位线索，不自动等于当前文件原文。

## 一次返回足够行动的信息

调用前想清楚下一步要做的决定，再设计代码输出或 `queries`：

- 定位：文件路径、符号／记录 ID、可用时的行号。
- 证据：关键原文、实际值、适用条件；失败时保留错误及退出状态。
- 完整性：匹配范围、是否截断、还缺什么；不只给计数或标题让下一轮猜。

单次分析直接打印答案即可，不必经过“索引 → 搜索”。需要后续多次查询时才保留完整可检索输出。`ctx_batch_execute` 的查询数随实际问题，不凑固定数量，也不保证一轮回答所有问题。

## `intent` 是检索条件，不是任务备注

适用于 `ctx_execute`／`ctx_execute_file`：

- `intent` 非空且**程序输出**超过 **5,000 字节**时，输出会被索引，返回匹配标题和短预览，而非完整答案；阈值不是输入文件大小。
- 代码已打印所需结论时，通常省略 `intent`，避免二次检索把关键值藏掉。只有需要从较大输出中检索时才填，使用输出中实际出现的符号、错误串或字段名。
- 不填 `intent` 也不意味着无限输出：超过 **102,400 字节**仍可能自动索引。应在代码里控制结果范围，而非大转储。
- `No sections matched` 只表示检索未命中，不证明文件没有该内容。需要聚合时改提取代码；需要原文时直接定向 Read；需要索引资料时按返回词汇与 `source` 搜索。不要反复换泛词，也不要据预览编辑。

示例：统计错误并返回定位，而不是仅输出“发现 8 个错误”。

```javascript
const lines = FILE_CONTENT.split("\n");
const matches = lines.flatMap((line, i) => /ERROR|Exception/.test(line) ? [{ line: i + 1, text: line }] : []);
console.log(JSON.stringify({ path: "<input path>", total: matches.length, matches: matches.slice(0, 20), truncated: matches.length > 20 }));
```

## When NOT to Use

| 工具 | 不适用的情况／替代 |
|---|---|
| `ctx_execute` | 只需短输出 → 原生 Bash；文件修改 → 原生 Edit／Write |
| `ctx_execute_file` | 要编辑、要完整逻辑、要精确原文 → 原生 Read；路径在工作区外也用宿主允许的读取工具，不绕过边界 |
| `ctx_batch_execute` | 几条短结果即可直接消费 → 宿主批量；前项决定后项输入 → 分阶段调用 |
| `ctx_index` | 单次分析 → execute／execute_file；大文本不要放 `content:`，用 `path:` |
| `ctx_search` | 已有足够证据 → 继续工作；资料未索引 → 先取所需信息，不反复空搜 |
| `ctx_fetch_and_index` | 一次性查网页 → MCP 搜索／抓取；本地已有 → index；依赖 JS 渲染 → 浏览器工具 |
| `ctx_stats` | 字节节省不等于任务提速；先看返回的会话／项目／累计范围，不能代替任务级耗时统计 |
| `ctx_purge` | 不是释放上下文或加速手段；用户未指定删除范围时先问，明确范围及不可逆性并获授权后才 `confirm: true` |
| `ctx_upgrade` | 本机 fork 不调用；维护使用套件的 `context-mode/setup.sh`，目标机通过套件 setup 更新 |

## Sandbox vs native tools

- 子进程不是安全隔离的文件系统。当前 executor 的各语言默认项目 cwd；`ctx_execute` 可传 `cwd`。临时脚本目录会清理，但对宿主文件的写入可能持久化；修改项目仍用原生 Edit／Write。
- 注入类环境变量（如 `NODE_OPTIONS`、`PYTHONSTARTUP`、`BASH_ENV`）被清理，不代表凭据已隔离。不要打印 secrets。
- 只打印有用结果；传入代码也会回显一部分，不把大数据内联进 `code`。不指定 timeout 时仍受宿主 RPC 生命周期约束。
- `background: true` 可在超时后保留进程；只有确需且已获授权的后台任务才用。尊重用户自行启动／观察长任务的约定。

## 检索、网页与浏览器

- `ctx_search` 使用实际技术词与适当的 `source` 范围；把当前独立问题放进同一 `queries` 数组。结果不足才继续，不做仪式化搜索。
- `ctx_fetch_and_index` 是普通 HTTP 抓取，不是浏览器；缓存默认 24 小时，需新鲜内容可用 `ttl: 0` 或 `force: true`。
- 大型浏览器快照、控制台或网络记录：工具支持时保存到可访问的文件，再一次提取；会反复查阅才索引。小型已返回快照直接使用，不为相同信息再抓一次。
- 外部 MCP 返回值已进上下文时，重新 `ctx_index(content: ...)` 不能撤销输入开销。需要减少原始返回时，使用工具自身过滤／落盘或宿主提供的编排能力；子进程不能凭空调用宿主 MCP 工具。
- 同一 Playwright 浏览器状态不并行修改；独立 session／实例确认隔离后才并行。子进程隔离本身不保证浏览器隔离。
- 子代理是否自动收到路由引导取决于宿主；委派提供目标、证据入口和验收边界，不假定 hook 会补齐任务上下文。

## 按需参考

不为每次调用重载本 skill；具体语言实现需要时再读：

- [JavaScript／TypeScript](./references/patterns-javascript.md)
- [Python](./references/patterns-python.md)
- [Shell](./references/patterns-shell.md)
