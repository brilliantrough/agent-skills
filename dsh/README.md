# DeepSeek Harness 接入

入口：仓库根 `dsh-setup.sh`；配置模板在本仓 `templates/dsh/cordis.patch.json`。

## 安装与启动

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/dsh-setup.sh)" -- -y

dsh tui
dsh --profile headless "任务"
dsh web
```

- 运行环境：Node ≥24.15；缺失时安装独立 Node，不更改 Pi 或系统 Node
- 固定组合：DSH `0.2.1-rc.2`、`@xmoon76/dsh-pi-tui` `0.5.3`、`pi2dsh` `0.27.1`；配套 DSH 服务也固定 `rc.2`
- 安装目录：`${XDG_DATA_HOME:-~/.local/share}/agent-skills/dsh/`；运行目录 `runtime/`，配置及会话 `home/`
- 已有 alpha：保留包与 `~/.dsh` 数据；替换 npm 入口时将旧链接保存为 `dsh-alpha`
- 直接运行 `dsh` 默认进入 TUI；`dsh cli` 会寻找名为 `cli` 的 profile，本套件未创建该 profile
- TUI、headless、web 共用套件数据目录；headless 显式启用官方本地凭据服务
- `DSH_HOME` 可显式指定其它目录；启动器绑定可用 Node，外层 shell 仍可使用原 Node
- 更新前退出 DSH；安装过程不迁移旧 alpha 会话或共享记忆库

## 模型与凭据

默认模型走原生 `llm-deepseek`：`deepseek-official/deepseek-flash`，原生发送 `x-deepseek-harness-session-id`。其它模型通过 `llm-pi-ai` 注册：

| Provider | 协议 | 配置来源 |
|---|---|---|
| `claude-newapi` | `anthropic-messages` | 与 Pi 模型表对应 |
| `codex-newapi` | `openai-responses` | 与 Pi 模型表对应 |
| `anthropic-newapi` | `anthropic-messages` | 与 Pi 模型表对应 |
| `google` | 内建 Google 目录，继承 `google-generative-ai` | DSH 目录路由；地址与 key 仍读 Pi 的 `gemini-newapi` |
| `zai-coding-cn` | 内建智谱 Coding 目录 | 4 个模型，窗口覆盖与 Pi 一致 |
| `kimi-coding` | 内建 Kimi Coding 目录 | 4 个模型，窗口覆盖与 Pi 一致 |

共 6 个 pi-ai provider、20 个模型，另保留默认原生 DeepSeek 通道。固定 rc.2 不允许自定义路由显式使用 `google-generative-ai`；重跑会把旧 DSH `gemini-newapi` 改名为 `google`，删除显式 `api`，并保留 URL、key 与自定义模型。部署按宿主最终合成结果校验 pi-ai 与 DeepSeek；`--dump-config` 不算加载验收。

安装在开头统一选择并优先读取本机 Pi 的地址与密钥；只复用非空实值。四个 `*-newapi` 的必需地址或 key 缺失、仍为占位符、URL 非法时都不追问：脚本在写入 DSH 配置前报出 provider、字段或安全序号并以非零码退出。已有 `cordis.patch.yml` 按真实 YAML 结构查询，支持带引号的键、flow mapping、仅有 `apiKeyEnv` 的 provider 与表达式节点，不再逐行猜缩进；地址仍按“补丁 → 环境变量 → Pi 配置”的部署优先级解析。URL 一律由 Node 的 `URL` 校验，避免 Python 与宿主接受域不同；无系统 Node 时先把独立 Node 解到临时目录，校验通过后才创建正式 ROOT。合并时旧的空值或占位符可由有效回退补齐，有效本机值不被覆盖；凭据库已有文件仍优先。也可设置 `CLAUDE_NEWAPI_BASE_URL/API_KEY`、`CODEX_NEWAPI_BASE_URL/API_KEY`、`ANTHROPIC_NEWAPI_BASE_URL/API_KEY`、`GEMINI_NEWAPI_BASE_URL/API_KEY`。AGENTS 注入需要可运行的 Python 3，选择 ppt 时前置要求 Python 3.10+。

已有补丁按真实 YAML 的最后一个同 id 条目读取，逐项核对现有凭据引用、同名环境变量和 Pi 回退；`config`／`providers`／provider／叶子表达式留到部署求值，home patch 存在时 headless 静态值也留到最终合成，pi-ai 静态禁用或 `disabled` 为表达式时也不在前置强制收集凭据，空白或缺 key 时只报告 provider 和 `apiKeyEnv` 字段，不回显引用名。运行资产先在暂存区准备，依赖不变时只读复用现有 `node_modules`，包内链接不写穿；外部 `file:` 链接先在暂存可解析状态校验，提交前再按最终 runtime 位置重建验证。部署按宿主剔除退役 bundle，写盘清单中的重复 bundle 逐项加载并计入 `startedBundles`，并执行官方兼容性／豁免过滤，先在空树合成 bundle／profile／home，再插入 `cordis.yml` 根树，统一在 profile 的 `baseUrl` 与宿主 `profileContext` 作用域求值，只校验最终启用的 pi-ai、DeepSeek 和凭据；同 ID 每层先取最后整行，再只展开生效 Group，按 BFS 跨层覆盖，Group 类型只按短名与官方全名判断，truthy 的 `group` 只豁免已创建条目自身的 disabled（含父级继承），不会让 provider 变成 Group；无此标记且自身／继承禁用的命名 Group 不展开，容器仍展开时禁用状态继续向下传，普通 group 共享 store；同 scope 整行去重后所有可能启用的 provider 实例都验收，不按深度或全局 winner 排除；跨 EntryGroup 的同 truthy ID provider 或 Include 若有多个配置不同的启用候选，保守拒绝且不猜异步挂载顺序，配置相同才验一份；这会拒绝部分宿主可运行配置；嵌套 Include 按独立 store 与链接路径所在目录的 `baseUrl` 递归，循环只按宿主解析的绝对路径检测，同文件的不同 ID、补丁或继承状态各自验收，不按路径去重，`ENOENT` 时仅在父目录已存在且可写、固定 `.tmp` 路径仅允许 `nlink === 1` 的可写普通文件（符号链接和多硬链接拒绝）时按 `config.initial` 验收，不预建或修改目录与文件，缺省／`null` ID 的匿名 Include 不去重，`""`／`0`／`false` 先在各自 EntryGroup 内字符串化去重，跨组为独立实例；每个 EntryGroup 按 JS 对象键顺序处理，array-index 键先按数值升序，CLI 每次重写根 `cordis.yml`，部署始终从 `[]` 合成且不读取旧根；嵌套 YAML／JSON 必须是条目数组，JSON 严格解析，无法读取、循环或模块型 Include 不得报通过；省略 `disabled` 即删除旧状态；无效补丁会 WARN。`disabled` 按宿主求值和继承。凭据文件值优先且必须 owner-only，空环境变量不得遮住 Pi 有效回退，环境只补文件不存在的引用。配置临时文件与备份先备好并在写后显式 `chmod`，普通配置保留原 mode，runtime、受管资产、解析器、watch、凭据和 profile 统一提交／回滚；恢复失败列出备份位置。旧 `gemini-newapi` 与 `google` 双键并存时明确拒绝自动拼接，需先手工合并。

智谱、Kimi Coding 密钥优先读取 Pi 的 `auth.json`，也可分别设置 `ZAI_CODING_CN_API_KEY`、`KIMI_CODING_API_KEY`。这两项订阅可选；未填时仍登记模型，使用前需补齐凭据。

- 私密值留在本机，`home/.credentials.yaml` 权限 `0600`；日志不输出 key，前置、配置解析／schema 与 bundle 警告只报序号位置，不回显引用名、bundle 名、自定义路由键、文件路径、URL、配置值或源行
- 配置写入 `home/profiles/<profile>/cordis.patch.yml`，按插件及模型 ID 合并
- 已有敏感值、本地独有项、自加 provider/model 与扩展包保留；修改前备份 `.bak-YYYYmmddHHMMSS`
- 原生 DeepSeek 通道的流解析器附带一个兼容改动：只在内容尚未开始时容忍重复 `message_start`；内容已开始后仍拒绝重复开始帧。此改动不负责发送亲和头

## 工具与记忆

| 能力 | 接入方式 | 数据与边界 |
|---|---|---|
| TUI、模型切换、会话浏览、任务及子代理 | `dsh-pi-tui` 与 DSH 原生服务 | 复用现成功能 |
| Ponytail | `pi2dsh` 运行原版 `@dietrichgebert/ponytail` `5.3.2` | 默认 full；6 个技能、等级切换和命令别名 |
| later | `pi2dsh` 运行仓库 `pi/extensions/later.ts` | 安装时复制唯一源文件；定时器随进程退出丢失 |
| 画图 | `pi2dsh` 运行仓库 `pi/extensions/image-gen.ts` + `image-gen/core.mjs` | 与 Pi、OpenCode 共用 `~/.local/share/agent-skills/image-gen.json`；图片走 DSH 原生附件 |
| context rewrite | 本仓 DSH 原生插件 | 用 surface replacement 替换近期完整工具操作；原始事件仍保留在会话日志 |
| 原生输出门控 | DSH 原生截断提示、spill 与 Read offset/limit；不再注册 `context_output_read`。受管 runtime 内的旧 `<64位SHA-256>.txt` 快照含隐藏目录保留原路径，不跟随链接；冲突在配置预置前停止 |
| context-mode fork | 官方 DSH MCP 客户端，复用本仓 release | `ctxm_*` 工具；配套 skills 自动挂载 |
| Magic Context | `wk544863858/dsh-plugin-magic-context` 固定源码构建 | DSH 专属 `home/magic-context/`；不打开 Pi/OpenCode 的共享库 |
| claude-mem | 已安装的官方 `@claude-mem/dsh` | 复用现有 worker，官方 recall 工具；转录采集通过官方 schema |
| skills、项目指令 | DSH 原生发现 | `~/.agents/skills`、项目 `.agents/skills`、`AGENTS.md`；`dsh-setup.sh` 每次运行都询问是否装 `base`（默认 Y）与 `research`/`accel`/`kb`/`ppt` 组（默认 N），并可询问安装 `agent-reach` |

Ponytail 使用[上游原版](https://github.com/DietrichGebert/ponytail)，通过现有 `pi2dsh` 扩展桥加载；TUI、Web、headless 共用这一份包，默认启用 full。TUI 常用命令：

```text
/ponytail lite
/ponytail full
/ponytail ultra
/ponytail off
/ponytail default full
```

`/ponytail <等级>` 调整当前会话；`default <等级>` 写入上游的 `~/.config/ponytail/config.json`（或 `$XDG_CONFIG_HOME/ponytail/config.json`），与同机 Pi 共享默认值，`PONYTAIL_DEFAULT_MODE` 环境变量优先。附带 `ponytail`、`ponytail-review`、`ponytail-audit`、`ponytail-debt`、`ponytail-gain`、`ponytail-help` 六个技能。Ponytail 与 later 均直接加载原文件，不另行维护 DSH 移植实现。

claude-mem 已有官方运行目录时直接挂载。新登记的 transcript watch 在 worker 下次启动后生效；安装过程不重启共享 worker。尚未安装官方运行目录时，脚本给出官方安装命令，避免拉起另一套自维护 worker。已有自定义或禁用的转录设置保留。

Magic Context 使用自己的 DSH 语料库，`memory: {}` 启用记忆车道；现有 Pi/OpenCode 记忆不会自动迁入。固定源码基于 Magic Context `v0.46.0`，与 Pi/OpenCode 当前版本独立维护。仍保留宿主 `compaction-basic`，不启用独立压缩引擎接管。官方 claude-mem worker 可继续跨宿主检索已有记忆。

## 原生功能与可选扩展

专用 `verification_review` 与 `consolidation_review` 分别用于独立功能复核和整理审查，通过各自 `tool-*.config.agentOptions` 固定审查模型与 `reasoningEffort`，不改父会话或其它子代理；具体字段见[功能 Verification 与整理审查](../README.md#功能-verification-与整理审查)。外层 `config.provider: spawn` 是委派后端，内层 `agentOptions.provider` 才是 LLM provider。其它入口选择同一 preset 不会自动继承这组固定值。

`verification-reviewer` 的 policy 只开放读取、搜索和当前平台的 `bash`／`pwsh`，不把另一平台的未注册工具写进 allow 列表。DSH 子会话继承 `workspace-write` 时无法同时强制“仓库只读、临时目录可写”；仓库禁写与隔离目录约束由提示词执行，不冒充沙箱保证。

基础组合已有子代理 spawn/fork、todo、goal、计划模式；TUI 提供模型切换、会话浏览及任务视图。

| 需求 | 官方能力 | 接入状态 |
|---|---|---|
| 搜索 DSH 历史会话 | `dsh-experimental-session-search` | 官方可选 bundle；按需启用，和项目记忆检索互补 |
| 多任务隔离工作目录 | `dsh-experimental-tool-worktree` | 官方可选 bundle；需要创建 worktree 时再启用 |
| 重启后仍有效的周期提醒 | `dsh-schedule` 及其持久化、工具组合 | 与本套件进程内 `later` 分开；需要周期或持久排程时再配置 |
| Office 文档处理 | `dsh-skill-office` | 按需挂载技能提供器与文档依赖；不预装办公运行环境 |

这些原生能力按需选择，不随套件开启全部实验插件。

社区可选参考：[dsh-lsp-actions](https://github.com/PerryLink/dsh-lsp-actions) 提供诊断、符号与重命名等 LSP 能力，需自行配置语言服务器，未默认安装。界面装饰与计时优先使用现有 TUI，不为对齐 Pi 另写适配。

## 更新与维护

重跑同一安装命令。版本和 Magic Context 源提交固定在安装文件中；升级前核对 TUI、扩展桥及 DSH 服务兼容范围，再走真实加载验收。

- `pi2dsh` 对历史改写有限制，因此 context rewrite、Magic Context 使用 DSH 原生接口
- 第三方源码在安装目录构建，许可证随包保留；不复制进本仓维护
- `--dump-config --profile tui` 仅查看合成配置，不证明插件能挂载；输出可能含本机连接信息，不公开粘贴
- 部署校验提供宿主的 `profileContext` 字段；其中 `cwd` 只能取安装期工作目录，依赖运行时 cwd 的表达式仍需真实启动验收
- Web 使用 `@deepseek-ai/dsh-web-app` 组合包；`@deepseek-ai/dsh-web` 是服务依赖，不能作为 profile bundle
- Web 服务由使用者自行启动；默认不留下后台服务
