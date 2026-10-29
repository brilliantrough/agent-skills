# DeepSeek Harness 接入

入口：仓库根 `dsh-setup.sh`；配置模板在 `dot_file/dsh/cordis.patch.json`。

## 安装与启动

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/dsh-setup.sh)" -- -y

dsh tui
dsh --profile headless "任务"
dsh web
```

- 运行环境：Node ≥24.9；缺失时安装独立 Node，不更改 Pi 或系统 Node
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
| `zai-coding-cn` | 内建智谱 Coding 目录 | 4 个模型，窗口覆盖与 Pi 一致 |
| `kimi-coding` | 内建 Kimi Coding 目录 | 4 个模型，窗口覆盖与 Pi 一致 |

共 5 个 pi-ai provider、17 个模型，另保留默认原生 DeepSeek 通道。

首次安装优先读取本机 Pi 的地址与密钥；也可设置 `CLAUDE_NEWAPI_BASE_URL/API_KEY`、`CODEX_NEWAPI_BASE_URL/API_KEY`、`ANTHROPIC_NEWAPI_BASE_URL/API_KEY`。缺少时交互询问；`-y` 下缺失则停止。

智谱、Kimi Coding 密钥优先读取 Pi 的 `auth.json`，也可分别设置 `ZAI_CODING_CN_API_KEY`、`KIMI_CODING_API_KEY`。这两项订阅可选；未填时仍登记模型，使用前需补齐凭据。

- 私密值留在本机，`home/.credentials.yaml` 权限 `0600`；日志不输出 key
- 配置写入 `home/profiles/<profile>/cordis.patch.yml`，按插件及模型 ID 合并
- 已有敏感值、本地独有项、自加 provider/model 与扩展包保留；修改前备份 `.bak-YYYYmmddHHMMSS`
- 原生 DeepSeek 通道的流解析器附带一个兼容改动：只在内容尚未开始时容忍重复 `message_start`；内容已开始后仍拒绝重复开始帧。此改动不负责发送亲和头

## 工具与记忆

| 能力 | 接入方式 | 数据与边界 |
|---|---|---|
| TUI、模型切换、会话浏览、任务及子代理 | `dsh-pi-tui` 与 DSH 原生服务 | 复用现成功能 |
| later | `pi2dsh` 运行仓库 `pi/extensions/later.ts` | 安装时复制唯一源文件；定时器随进程退出丢失 |
| context rewrite | 本仓 DSH 原生插件 | 用 surface replacement 替换近期完整工具操作；原始事件仍保留在会话日志 |
| 大输出外置 | 与 Pi/OpenCode 共用 `context-rewrite/output-store.mjs` | `context_output_read` 取回；受管制品目录内保存全文 |
| context-mode fork | 官方 DSH MCP 客户端，复用本仓 release | `ctxm_*` 工具；配套 skills 自动挂载 |
| Magic Context | `wk544863858/dsh-plugin-magic-context` 固定源码构建 | DSH 专属 `home/magic-context/`；不打开 Pi/OpenCode 的共享库 |
| claude-mem | 已安装的官方 `@claude-mem/dsh` | 复用现有 worker，官方 recall 工具；转录采集通过官方 schema |
| skills、项目指令 | DSH 原生发现 | `~/.agents/skills`、项目 `.agents/skills`、`AGENTS.md` |

claude-mem 已有官方运行目录时直接挂载。新登记的 transcript watch 在 worker 下次启动后生效；安装过程不重启共享 worker。尚未安装官方运行目录时，脚本给出官方安装命令，避免拉起另一套自维护 worker。已有自定义或禁用的转录设置保留。

Magic Context 使用自己的 DSH 语料库，`memory: {}` 启用记忆车道；现有 Pi/OpenCode 记忆不会自动迁入。固定源码基于 Magic Context `v0.46.0`，与 Pi/OpenCode 当前版本独立维护。仍保留宿主 `compaction-basic`，不启用独立压缩引擎接管。官方 claude-mem worker 可继续跨宿主检索已有记忆。

## 原生功能与可选扩展

基础组合已有子代理 spawn/fork、todo、goal、计划模式；TUI 提供模型切换、会话浏览及任务视图。

| 需求 | 官方能力 | 接入状态 |
|---|---|---|
| 搜索 DSH 历史会话 | `dsh-experimental-session-search` | 官方可选 bundle；按需启用，和项目记忆检索互补 |
| 多任务隔离工作目录 | `dsh-experimental-tool-worktree` | 官方可选 bundle；需要创建 worktree 时再启用 |
| 重启后仍有效的周期提醒 | `dsh-schedule` 及其持久化、工具组合 | 与本套件进程内 `later` 分开；需要周期或持久排程时再配置 |
| Office 文档处理 | `dsh-skill-office` | 按需挂载技能提供器与文档依赖；不预装办公运行环境 |

这些原生能力按需选择，不随套件开启全部实验插件。

## 更新与维护

重跑同一安装命令。版本和 Magic Context 源提交固定在安装文件中；升级前核对 TUI、扩展桥及 DSH 服务兼容范围，再走真实加载验收。

- `pi2dsh` 对历史改写有限制，因此 context rewrite、Magic Context 使用 DSH 原生接口
- 第三方源码在安装目录构建，许可证随包保留；不复制进本仓维护
- `--dump-config --profile tui` 可检查合成配置；输出可能含本机连接信息，不公开粘贴
- Web 使用 `@deepseek-ai/dsh-web-app` 组合包；`@deepseek-ai/dsh-web` 是服务依赖，不能作为 profile bundle
- Web 服务由使用者自行启动；默认不留下后台服务
