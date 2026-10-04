# agent-skills

个人 agent 环境分发源：三层记忆（Magic Context + StrictDoc + claude-mem）、任务工作流、前端品味。一条命令安装 skills、配置插件。

| 宿主 | 定位 |
|---|---|
| OpenCode | 主目标 |
| Pi | 与 OpenCode 共享记忆配置 |
| Codex | best effort；复用 skills 原文，不改工作流 |

[快速安装](#快速安装) · [Skills](#skills18-个) · [首次部署](#首次部署只需要网关--5-个-key) · [Windows](#windowsgit-bash) · [Codex](#codex-插件配置best-effort) · [Pi](#pi-配置) · [OpenCode](#opencode-插件配置手工步骤) · [更新](#更新)

## 快速安装

**Windows 首次使用**：先安装 [Git for Windows](https://git-scm.com/download/win)（自带 Git Bash；无需安装 `gh`）。若有 `winget`，也可以在 PowerShell 中运行：

```powershell
winget install --id Git.Git -e --source winget
```

安装完成后，从开始菜单打开 **Git Bash**，在其中运行下面的安装命令。配置完成后，若 `pi` 或 `opencode` 已在其他终端的 PATH 中，也可从 PowerShell、Windows Terminal 等终端直接启动；无需每次手动打开 Git Bash，但请保留 Git for Windows，供 Bash 命令与插件使用。

### 默认安装（`-y`，幂等）

仅问一轮凭据：统一网关 + 5 个 key，见[首次部署](#首次部署只需要网关--5-个-key)。

**OpenCode**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)" -- -y
```

**Pi**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/pi-setup.sh)" -- -y
```

**只装 skills，不配插件**

```bash
npx skills@latest add brilliantrough/agent-skills --all -g -y
```

安装位置：`~/.agents/skills/`；重开 agent session 生效。

**Codex（best effort）**

```bash
bash -c "$(curl -fsSL --connect-timeout 8 -m 60 https://raw.githubusercontent.com/brilliantrough/agent-skills/main/codex-setup.sh)"
```

### `-y` 与逐项确认

`-y` 取各项默认值，不再逐项确认：

| 默认值 | 行为 | 项目 |
|---|---|---|
| Y | 执行 | 装缺件、字段级合并配置（保留本地敏感值）、刷新 skills |
| N | 跳过 | notify、覆盖插件缓存、升级 Pi 本体、无代理继续、AGENTS.md 注入 |
| 凭据 | 仍询问 | 无终端则跳过，保留占位符；无人值守可用环境变量预填 |

等价写法：`--yes`、`ASSUME_YES=1`、`curl -fsSL <脚本 URL> | bash -s -- -y`。

**逐项确认：不传 `-y`。** 写前列出变更（含模型名 / `models`），可逐项拒绝。

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/pi-setup.sh)"
```

## Skills（18 个）

### 工程技能

来自 [mattpocock/skills](https://github.com/mattpocock/skills)，MIT；归属见 [NOTICE](NOTICE.md)。

| Skill | 用途 |
|---|---|
| `grilling` | 计划/设计访谈，逐分支追问至有结论 |
| `domain-modeling` | 领域模型、术语表 |
| `tdd` | 红-绿-重构 |
| `diagnosing-bugs` | bug 诊断：先建反馈回路，再假设原因 |
| `code-review` | 双轴审查：规范符合度 + spec 忠实度 |

### 三层记忆（自制）

| Skill | 用途 |
|---|---|
| `load-mem` | 启动/接续时恢复记忆；并用三层记忆与代码证据，区分现行规范与历史 |
| `save-mem` | 保存知识；Agent 自选位置、粒度与时机，允许多处保存；短语、列表、表格优先 |
| `migrate-mem` | 为已有项目建立/补全记忆，初始化可读的 StrictDoc 文档；不假定旧工作流、不搬原文件 |

- 三层互补、允许交叠；决策可同时存入 StrictDoc 与 Magic Context，不强制分流
- 冲突以 **StrictDoc 当前有效规范**为准
- 明确决策后更新规范并简短告知；不因猜测或每次任务频繁改动
- 文档默认中文；调查、存取路径由 Agent 判断

### 技术写作（自制）

| Skill | 用途 |
|---|---|
| [`readable-docs`](skills/readable-docs/SKILL.md) | 面向人的技术文本：短语、分点、紧凑对比表；保留事实、条件与约束强度 |

- **范围**：README、设计、计划、报告、runbook、变更记录、记忆文档；不限目录
- **风格**：PPT 要点式扫读；单元格不塞长文，复杂因果留短段落；见[中文改写示例](skills/readable-docs/references/examples.md)
- **接入**：安装 skill，将 [AGENTS.tail.md](AGENTS.tail.md) 规范块合入项目 `AGENTS.md`；已有项目也需更新
- **边界**：不批量重写旧文档，不改模板、规范强度、代码或原始证据

### 任务工作流（自制）

手动指定优先；未指定时由 Agent 按任务意图选择。

| Skill | 适用任务 | 流程 |
|---|---|---|
| `quick-do` | 行为明确的小修小补 | 读代码 → 当前会话修改、验证；不 grilling、不写计划 |
| `steady-do` | 日常功能、插件、扩展 | 理解项目 → 分轮澄清 → 当前会话实现、验证；不写交接文档 |
| `plan-brief` | 长程多阶段任务 | 澄清 → 计划 `docs/plans/<slug>.md` + 启动 prompt → 新会话执行 → 报告 → 原会话审查 |

按不确定性、耦合、风险与交接需求选择，不按字数分档：

- quick/steady 难判：用 `steady-do`
- 适合交接但用户未要求：先建议 `plan-brief` 并确认，不擅自把“现在实现”改成“只交计划”

共同要求：

- 事实自己查，只问未决关键选择；遵循 ponytail 简洁品味
- 最小真实运行 + 代码复读；默认不加测试/TDD，用户明确要求与项目强制检查除外
- 检查通过 ≠ 真实交互已验收；必须说明未验证项
- skill 指令统一英文，回复跟随用户语言（默认中文）

使用示例：“用 steady-do，先问清楚再做”。

### 个人领域知识（自制）

| Skill | 用途 |
|---|---|
| `personal-ui-taste` | 浅色信息密集界面、多系列图表焦点联动、密集图表就近悬浮、症状索引与反馈演化协议 |

### 科研实验（自制）

ponytail for experiments：规模随证据收缩，完整性满足论点。

| Skill | 适用场景 | 流程与边界 |
|---|---|---|
| `exp-discuss` | 模糊想法 | 带证据分轮追问、指出遗漏、找最便宜的证伪观测；不设计矩阵、不运行 |
| `exp-campaign` | 分阶段、可剪枝的实验战役 | 观察已有结果 → 枚举最大空间 → 廉价探针剪枝 → 带观察门限的决策树计划；分阶段交给 exp-batch |
| `exp-batch` | 一条有界分支：方法×数据×预算，或消融分支 | 确认未被剪枝 → 预检环境/资源、显式指定可见设备 → 按项目惯例运行 → 指标落共享表格 |
| `exp-probe` | 补数据点、失败重跑、sanity check、最小复现 | 一次性抽查；至多一个聚焦问题，一行汇报 |

### 科研图件（自制）

| Skill | 用途 |
|---|---|
| `editable-vector-slides` | SVG/PDF 科研图 → 可编辑矢量 PDF + 原生 PPTX；保留路径/文字/渐变/阴影，非截图；含依赖安装、验收与踩坑清单 |

## 依赖

| 类别 | 依赖 |
|---|---|
| Matt 的 6 个 skill | 无 |
| 记忆 skill | Magic Context、claude-mem、`docs/` StrictDoc；缺一层仍可用其余层 |
| 工作流 / 品味 / 技术写作 | 无硬依赖 |

- `.sdoc` 校验需要 `strictdoc`：脚本末尾检查 `uv`，缺则安装；可选全局安装 `uv tool install strictdoc==0.28.1`，升级用 `uv tool upgrade strictdoc`
- 项目接入记忆系统：使用 [AGENTS.tail.md](AGENTS.tail.md) 中 `memory-system:start/end` 引导块

## 首次部署：只需要网关 + 5 个 key

三个 setup 脚本统一收集、填入凭据；目标文件均无 `<YOUR_*>` 占位符则跳过。

| 输入 | 回车行为 |
|---|---|
| 网关 | 使用默认 `https://api.pezayo.com/v1`；输入 `-` 则保留占位符 |
| 各 key | 跳过、保留占位符；重跑可补 |
| mcphub MCP host | 可选，回车跳过；Codex 侧不问 |

### 填写位置

统一网关写入：

- `pi/models.json`：anthropic 协议用根域，openai 协议带 `/v1`
- `opencode.json`：各 provider 的 `baseURL`
- `~/.claude-mem/settings.json`
- magic-context：embedding `endpoint`

前三个 key 写入 `opencode.json` / `pi/models.json`：

| 配置键 | 协议 / 模型 | 网关分组 |
|---|---|---|
| `claude-newapi.apiKey` | anthropic / claude | claude code |
| `codex-newapi.apiKey` | openai responses / gpt | codex |
| `anthropic-newapi.apiKey` | anthropic / 国产模型 | coding anthropic |

| 其余输入 | 协议 / 分组 | 写入位置 |
|---|---|---|
| magic-context embedding key | openai / 嵌入模型 / 任意分组 | `magic-context.jsonc` → `embedding.api_key` |
| claude-mem key | openai chat completions / 任意模型 / 建议 coding openai 分组 | `~/.claude-mem/settings.json` → `CLAUDE_MEM_OPENROUTER_API_KEY` |
| mcphub MCP host | — | `~/.agents/mcp.json`、`opencode.json` → `mcp.mcphub-web.url` |

同一模板的三处 `<YOUR_NEWAPI_API_KEY>` 按 provider 名就近替换，不串位。

### 无人值守与手工补填

| 环境变量 | 用途 |
|---|---|
| `PI_GATEWAY_BASE_URL` | 统一网关 |
| `PI_GATEWAY_API_KEY` | 未单独指定 key 的槽位兜底 |
| `PI_CLAUDE_NEWAPI_API_KEY` | claude-newapi |
| `PI_CODEX_NEWAPI_API_KEY` | codex-newapi |
| `PI_ANTHROPIC_NEWAPI_API_KEY` | anthropic-newapi |
| `PI_EMBEDDING_API_KEY` | embedding |
| `PI_CLAUDE_MEM_API_KEY` | claude-mem |
| `MCPHUB_HOST` | mcphub MCP host |

- 跳过的占位符：按脚本末尾“文件 / 缺失项”清单手工补，或重跑脚本
- 非 `/v1` 风格网关：填完核对 `pi/models.json` 的 anthropic 根域与 claude-mem 的 BASE_URL
- 仍需手工配置：
  - `pi/auth.json`：zai/kimi 等内置 provider 的 coding-plan key
  - `~/.func`：由 dot_file 的 `linux-setup.sh` 部署
  - `NOTIFY_*` 环境变量：仅安装 notify 时需要

> **凭据不覆盖，模型名跟模板走。** `-y` 直接覆盖模型名，交互模式先列变更再确认；要保留自定义后端模型，不要用 `-y`。字段范围见[配置合并](#配置合并)。

## Windows（Git Bash）

同一份 `*-setup.sh`、同一组顶部命令，在 **Git Bash** 运行；WSL 按 Linux 处理。Windows 不保证自带 Git：首次安装请按[快速安装](#快速安装)先安装 Git for Windows，然后新开 Git Bash。不要在 PowerShell 中直接运行 `bash` 来启动本脚本：部分电脑上的 `bash.exe` 指向 WSL，而不是 Git Bash。

仅需预装 **Git for Windows**（含 bash / curl / git / cygpath），其余缺件由脚本安装或提示：

| 缺件 | 处理方式 |
|---|---|
| Python 3 | 询问后用 uv 自管理的 3.12 兜底；或 `winget install Python.Python.3.12` |
| Node LTS | fnm 官方脚本；失败则 `winget install OpenJS.NodeJS.LTS` |
| bun / uv | 各自官方脚本（支持 MinGW）；失败时提示手工命令 |

PS：上游 `install.ps1` / winget 面向零前提用户；本项目约定 Git Bash，三个脚本均用 bash。

### 脚本处理的系统差异

| 项目 | Windows 行为 |
|---|---|
| 本机路径 | `mcp.json` / `opencode.json` 写 `C:/...`，不用宿主无法识别的 `/c/...`；可执行文件补 `.exe` |
| claude-mem 端口 | 无 uid 时取 77 → `37777`；与 worker / 桥的 `process.getuid?.() ?? 77` 一致 |
| codegraph | 官方 `install.sh` 仅支持 Darwin/Linux；改用 `npm i -g @colbymchenry/codegraph@latest` |
| Pi 本体 | 官方 `install.sh` 仅支持 Darwin/Linux；改用 `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` |
| uv 镜像 | 写 `%APPDATA%\uv\uv.toml`；uv 不读 `~/.config` |
| 开发用类型软链 | 跳过；`ln -s` 需开发者模式，否则退化成整目录拷贝 |
| 配置目录 | 与 Linux 一致；Git Bash 的 `$HOME` 即 `%USERPROFILE%` |

### Pi 的 Git Bash / mintty 适配

以下首次安装与重复执行的终端适配**仅限 `pi-setup.sh`**；不修改 Codex/OpenCode 安装脚本的行为：

| 范围 | 行为 |
| --- | --- |
| Pi setup 的 Bun | 优先复用 `BUN_INSTALL` 或 `~/.bun` 中已有的 Bun；实际执行版本检查与 `bun:sqlite` 内存查询，不能运行就报错，不把“命令存在”当作成功 |
| Git Bash 启动文件 | Bun 可用后询问补齐（`-y` 默认执行）：缺 `.bashrc` 就创建；已有文件只追加/更新带标记的受管块，改前备份；不覆盖代理、别名等原文，不穿透符号链接 |
| 登录加载链 | 使用现有 `.bash_profile` / `.bash_login` / `.profile` 中优先级最高的文件；均不存在才创建 `.bash_profile`，不会遮蔽已有 `.profile`；已经加载 `.bashrc` 时不重复加载 |
| Bun PATH | 持久化实际可执行文件所在目录，支持空格/中文/自定义安装位置；受管块不重复添加 PATH，重复执行不产生无效改写或备份 |
| mintty 复制粘贴 | 仅 `TERM_PROGRAM=mintty` 时补缺失的 `CtrlShiftShortcuts=yes`、`CopyOnSelect=yes`；已有显式值与 `KeyFunctions` 保留。不重映射 Ctrl+C/V，也不启用 `CtrlExchangeShift` 或 OSC 52 权限 |
| Pi 滚轮 | Windows mintty 首次设置默认 `tuiMode: regular`，使用终端原生 scrollback/拖选；已有 `tuiMode` 在重跑时保留（包括显式 fullscreen）。侧栏/分栏仍需自行选择 fullscreen，脚本不修改 Pi 的滚轮实现 |

- 改启动文件或 `.minttyrc` 后**新开 Git Bash 窗口**；改 Pi 的模式后**重启 Pi**。子安装脚本的 `export` 不会反向修改当前父终端。
- 发现 `CtrlExchangeShift` 已启用时，不自动补 `CtrlShiftShortcuts`，避免把 Ctrl+W/Ctrl+R 等快捷键切换成关闭窗口/重置终端。
- Windows Terminal、VS Code、Linux、macOS、WSL 不会被这段 mintty 配置逻辑接管。
- 隔离验证（不下载/升级包，不修改真实 HOME）：`python tests/pi-setup-windows-git-bash.py`。Windows 可加 `BASH="$(cygpath -m /bin/bash.exe)" BUN_TEST_BIN="$(cygpath -m "${BUN_INSTALL:-$HOME/.bun}/bin/bun.exe")"` 验证真实 Bun、SQLite 与原生子进程启动；未提供 Bun 或系统不允许创建符号链接时会明确报告对应测试跳过。

### 宿主成熟度

脚本不改变宿主的官方支持状态。

| 宿主 | 官方立场 |
|---|---|
| Pi | 原生 Windows + Git Bash 为官方路径；见 [Run Pi on Windows](https://pi.dev/docs/latest/windows) |
| OpenCode | 可原生运行，仍推荐 WSL |
| Codex | 原生 Windows 为 experimental，推荐 WSL；脚本 best effort 并提示 |

## Codex 插件配置（best effort）

### 前置与安装范围

- 已装 Codex ≥0.128.0，支持 `codex plugin marketplace`；Python ≥3.11、curl、git
- 不升级系统 Python / Codex；已有 Node 需 ≥20
- 缺 Node LTS / Bun / uv 时询问安装；可选用 `uv` 安装 strictdoc==0.28.1

| 项目 | `codex-setup.sh` 的行为 |
|---|---|
| claude-mem | 优先复用 `~/.claude/plugins/marketplaces/thedotmack` runtime；缺失/过旧时询问官方 `--ide codex-cli` 安装器 |
| 本地记忆插件 | 注册 `claude-mem@claude-mem-local`，自带 MCP、skills、hooks |
| Ponytail | 官方 `ponytail@ponytail`；Node 须在启动 Codex 的 PATH 中 |
| CodeGraph | 缺则装 CLI，以 `codex mcp add` 注册；保留现有 `mcp_servers.codegraph`，各项目运行 `codegraph init` |
| skills | 仅安装缺失的本仓库 skills（`--agent codex`）；不覆盖已有共享 skills |
| Magic Context / notify | 不安装；不动原生压缩；缺 `ctx_*` 的记忆技能仅 best effort |

### 配置与共享资产安全

- 写前列待添加项、确认并备份；TOML 由 Codex CLI 写入
- 不管理模型/认证；保留已安装或显式禁用项，重跑不自动升级
- `~/.claude-mem/settings.json` 原样保留（含 provider/URL/key）；官方安装器临时改写后也恢复
- 首次创建 OpenAI 兼容后端占位符，需手填

| 路径配置 | 行为 |
|---|---|
| `${CODEX_HOME:-~/.codex}/config.toml` | Codex 配置位置 |
| 自定义 `CODEX_HOME` | 官方首次安装器写死 `~/.codex`；脚本仅复用已有 runtime，缺失则提示手工安装 |
| `CLAUDE_CONFIG_DIR` / `CLAUDE_MEM_DATA_DIR` | 指定共享资产 / 记忆目录 |

**claude-mem 安装器会更新共享资产、注册 Claude 插件、停止 worker**，即使传 `--no-auto-start` 也会停机。已有 runtime 默认不升级。

### 安装后验收

1. 填记忆后端配置，运行 `npx claude-mem@latest start`
2. Codex **`/hooks` 审阅并信任 hooks，再开新会话**
3. `/mcp` 确认连接，实际调用查询工具

失败时脚本告警并返回非零，不误报完成。

### 手工安装与更新

首次安装 claude-mem 同样影响上述共享配置。

```bash
npx claude-mem@latest install --ide codex-cli
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail
codex mcp add codegraph -- codegraph serve --mcp
npx skills@latest add brilliantrough/agent-skills --skill '*' --agent codex -g -y
```

更新命令（setup 不自动执行）：

```bash
codex plugin marketplace upgrade ponytail
codex plugin add ponytail@ponytail
# claude-mem runtime 更新后,重新装入其本地插件快照:
codex plugin add claude-mem@claude-mem-local
npx skills@latest update -g
```

skills 共享，更新也影响 OpenCode。claude-mem runtime 按官方文档更新，先备份共享配置。

官方参考：[Codex MCP](https://developers.openai.com/codex/mcp) · [Codex hooks](https://developers.openai.com/codex/hooks) · [claude-mem 安装器](https://github.com/thedotmack/claude-mem/blob/main/src/services/integrations/CodexCliInstaller.ts) · [Ponytail](https://github.com/DietrichGebert/ponytail#codex) · [CodeGraph](https://github.com/colbymchenry/codegraph#quick-start)

## Pi 配置

[Pi](https://pi.dev) 原生读 `~/.agents/skills/`；MCP/subagent 靠 npm 包与扩展提供。模板见 [dot_file/pi](https://github.com/brilliantrough/dot_file/tree/master/pi)。

与 OpenCode 共享配置，均按字段合并、幂等、不破坏本地值：

- `~/.claude-mem/settings.json`
- `~/.config/cortexkit/magic-context.jsonc`

### 模型、设置与凭据

| 文件 | 内容 |
|---|---|
| `~/.pi/agent/models.json` | claude-newapi（anthropic）、codex-newapi（openai-responses）、anthropic-newapi |
| `~/.pi/agent/settings.json` | 默认 provider/model/thinking；`defaultTools` 补 `grep/find/ls`（默认仅 read/bash/edit/write）；`packages` 由 `pi install` 维护 |
| `~/.pi/agent/auth.json` | 内置 coding-plan provider 的 key；权限 600；模板含 `zai-coding-cn` / `kimi-coding` 占位符 |

- **anthropic `baseUrl` 填根域**：Pi 自动补 `/v1/messages`，填 `/v1` 会 404；openai 带 `/v1`
- 兼容项：`compat.supportsStore:false`、`thinkingLevelMap`（xhigh/max，对应 OpenCode variants）
- 不写 Pi `compaction` 开关：magic-context 在 `session_before_compact` cancel 原生压缩，与官方 `setup --harness pi` 一致
- `auth.json`：字段级合并，已填 key 不覆盖，仅初始化缺失文件
- 智谱 coding plan、Kimi For Coding、qwen/xiaomi token plan、opencode-go 等内置 provider 无需写 `models.json`

### 运行默认值

| 项目 | 默认值 |
|---|---|
| `modelThinkingLevels` | `codex-newapi/gpt-6-astra`、`codex-newapi/gpt-6-sol` 用 `xhigh`；其余全局 `high` |
| agent 级 `retry` | `maxRetries:8`、`baseDelayMs:4000`；原生指数退避，不开 provider 内层重试 |
| 退避间隔 | 4/8/16/32/64/128/256/512 秒，累计 17 分钟；含首发最多 9 次请求 |

**自动命名**

- `pi-autoname@0.6.8`；配置 `~/.pi/agent/pi-autoname.json`
- 任务结束后用 `codex-newapi/gpt-6-sol` 命名；冷却 1440 分钟，尊重手工名称；`/autoname` 手动触发
- 最近对话片段发送给命名模型；失败回退当前会话模型 / 文本提取
- 配置路径固定 `~/.pi/agent`；自定义 `PI_CODING_AGENT_DIR` 时跳过

**任务耗时**

- 源码：`pi/extensions/message-timing.ts`；仅 TUI
- `agent_start` → `agent_settled` 计秒，包含工具、重试、排队后续消息
- custom entry 持久保存，不进模型上下文、不高频刷新

### 插件与主题

通过 `pi install npm:...` 安装：

| 包 | 用途 / 说明 |
|---|---|
| `pi-mcp-adapter` | MCP |
| `@dietrichgebert/ponytail` | 官方自带 pi-extension |
| `pi-subagents-j0k3r` | subagent |
| `pi-lens` | 实时诊断、符号检索 |
| `@juicesharp/rpiv-ask-user-question` | `ask_user_question` 结构化提问；Pi 核心没有，plan-brief/grilling 需要 |
| `@cortexkit/pi-magic-context` | Magic Context |
| `pi-autoname@0.6.8` | 自动命名 |

**本仓库也是 Pi 包：** `pi install git:github.com/brilliantrough/agent-skills`。

- 提供个性化 UI（`/ui`）、pretty-tui 工具/思考折叠块与代码块复制、claude-mem 桥、`/later`、任务耗时、one-dark 主题
- 自动清理旧散装文件
- 步骤 2 逐包更新后明确显示：`本仓库 Pi 插件已更新: <旧> -> <新>(N 个提交)`

主题：`pi/themes/onedark.json`（One Dark，56 色 token，支持热重载）；`settings.json` 中设 `theme: one-dark`。可修改 `theme`、在 `/settings` 中选择，或安装主题包：`awesome-pi-themes`（65 款）、`@inobit/pi-themes`。

### MCP 与 subagent

MCP 配置：共享的 `~/.agents/mcp.json`，由 pi-mcp-adapter 读取。

| MCP | 连接方式 |
|---|---|
| mcphub-web | 远程 URL |
| codegraph / claude-mem | 本地命令；部署时替换为本机 `codegraph` / `bun` 绝对路径 |

- mcphub-web `directTools`：5 个直连工具——tavily search/extract、firecrawl scrape/search/research_search_github；首调自动 lazyConnect
- 其余走 `mcp` 网关：`mcp({search/describe/connect})`；内部调用名带 `mcphub-web_` 前缀
- subagent 定义：`~/.pi/agent/agents/{explore,general}.md`，对应 OpenCode 的 explore/general
- frontmatter **必须显式写 `tools`**：默认值引用了不存在的工具

### 个性化 UI

统一入口 `pi/extensions/ui/index.ts`，不再安装两套 UI 包；见[源码与许可证说明](pi/extensions/ui/README.md)。

| 部分 | 内容 |
|---|---|
| 布局 / 侧栏 | 纳管的 Atelier 0.10.1 |
| 编辑器 / 消息视觉 | Zentui 0.24.0 |
| 功能 | LF 提交修复、TPS、HΣ/H₁、R/W、Magic Context `todowrite` 侧栏 |
| 配置 | `agent-skills-ui.json`、`agent-skills-editor.json` |
| 命令 | `/ui`、`/ui sidebar` |

**配置部署**

- 整文件覆盖 `~/.pi/agent/{agent-skills-ui,agent-skills-editor,keybindings}.json`；有差异先存 `.bak`，符号链接跳过；不做一次性迁移
- 模板已验证：`sidebarPanelLayout`、侧栏自定义面板、`clearSelectionOnRelease` 默认、`tmuxMouseMotion` 默认开、Enter 发送 / Shift+Enter 换行
- 旧 `pi-zentui` / `pi-atelier` / `atelier-bridge` 从 `packages` 摘除，先存 `.bak`，避免两套 UI 同时加载

### 记忆桥与版本守卫

**claude-mem 桥**

官方无 Pi 适配；本仓库桥镜像 OpenCode 插件契约：

- POST worker `/api/sessions/init|observations|summarize`，`platformSource:"pi"`
- 采集工具调用、助手消息、**用户 prompt**；支持 `前缀*` 跳过
- `claude_mem_search` 直连 worker，不走 MCP

**magic-context 版本守卫**

OpenCode 缓存钉住下载时版本，重启不自动升级。与 Pi 版本不一致时，共享 `context.db` 会使新宿主 fail-closed、拒绝主回合。

检测到不一致时，脚本默认不启用 Pi 版，并提示：

1. 清除 `~/.cache/opencode/packages/@cortexkit/opencode-magic-context@latest`
2. 重启 OpenCode
3. 重跑 `pi-setup.sh`

升级须选两边均无人使用的时段，见[更新](#更新)。

### context-mode fork

**不要装上游 `npm:context-mode`。** 它与 magic-context 都注册 `ctx_search`，Pi 会因同名工具 `process.exit(1)`；脚本检测到会提示卸载。

本仓库 fork：

- 构建后将 11 个工具改名为 `ctxm_*`，另做三项口径修正
- 产物走 GitHub release，不进 git 历史
- 目标机无需 bun / clone；开发机发布：`bash context-mode/setup.sh --publish`

| 宿主 | 部署方式 |
|---|---|
| Pi | curl 最新 release → 解到 `~/.pi/agent/vendor/context-mode` → `pi install`；内容未变则跳过 |
| OpenCode | `opencode-context-mode-vendor.tar.gz` → `~/.config/opencode/plugins/context-mode/`；再放一层 `entry.js` 入口 |

- Pi：摘除旧 clone 路径条目；同时登记两份会无法启动
- OpenCode：不改 `opencode.json` 的 `plugin` 字段；7 个 skill 装到 `~/.config/opencode/skill/`

### later：延迟发送 prompt

源码：`pi/extensions/later.ts`。

| 命令 | 用途 |
|---|---|
| `/later 5h <prompt>` | 5 小时后注入用户消息 |
| `/later list` | 查看排程 |
| `/later cancel <id/all>` | 取消排程 |

- `sendUserMessage` + `deliverAs:followUp`：空闲即发，忙时排队等本轮结束
- 排程仅存于当前 Pi 进程；退出、重启、切换会话即丢。挂机用 tmux 保持 Pi 常驻

### 手工配置与开发

不用脚本时：

1. 对照[插件清单](#插件与主题)，用 `pi install npm:<包名>` 逐个安装七个 npm 包，再用 `pi install git:github.com/brilliantrough/agent-skills` 安装本仓库包
2. 可选安装 context-mode fork：
   - Pi：`curl -fsSL https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz | tar -xz -C ~/.pi/agent/vendor/context-mode`，再 `pi install ~/.pi/agent/vendor/context-mode`
   - OpenCode：取 `opencode-context-mode-vendor.tar.gz` 解到 `~/.config/opencode/plugins/context-mode`，将包内 `entry.js` 用 `cp` 复制到 `plugins/context-mode.js`
3. 将 dot_file 的 `pi/{models,settings,mcp,auth,pi-autoname}.json`、`pi/agents/*.md` 放到对应位置
4. 填好 `models.json` 网关占位符、`auth.json` coding plan key；用 `pi auth check --provider <p>` 验证

管理包：`pi remove <source>` 卸载，`pi list` 查看。uv/strictdoc 处理同 `opencode-setup.sh`。

PS：开发时，脚本最后将本机 Pi 包软链到仓库 `node_modules/`（`.gitignore` 已排除），供编辑器/pi-lens 解析 `@earendil-works/pi-*`、`node:*` 类型。缺软链会报 `Cannot find module`，但运行时由 Pi 提供，不影响使用。

## OpenCode 插件配置（手工步骤）

一键安装见顶部；以下为手工配置。

### 1. claude-mem

```bash
npx claude-mem install --ide opencode
```

安装后配置 wrapper、MCP、settings 三部分。

#### ① wrapper 修复

上游 bug [thedotmack/claude-mem#2854/#3328](https://github.com/thedotmack/claude-mem/issues/2854)：bundle 导出非函数常量。

- bundle 移至 `~/.config/opencode/lib/claude-mem.js`
- `opencode-setup.sh` 生成 `~/.config/opencode/plugins/claude-mem-wrapper.js`
- plugin 条目设为 `./plugins/claude-mem-wrapper.js`
- 升级 claude-mem 后重跑脚本，重新生成 wrapper

| 修复 | 行为 |
|---|---|
| 导出 | 仅 re-export 插件函数，绕过非函数常量 bug |
| 用户 prompt | 每条输入经 `/api/sessions/init` 写入；统一 contentSessionId，与插件观测落在同一会话行；不增加模型请求 |
| 助手回复 | `experimental.text.complete` 暂存每回合最后文本；`session.idle` 时发送 1 条 `assistant_message` |
| 工具跳过 | `CLAUDE_MEM_SKIP_TOOLS` 中以 `*` 结尾的条目，在 POST 前按前缀过滤，如 `mcphub-web_*`、`ctx_*` |

- 用户漏采集：上游 `chat.message` 只认 `assistant`，实际收到 `UserMessage`。wrapper 走 Claude Code 同一路径：`user_prompts` + FTS + Chroma + observer 的 `<user_request>`
- 助手分支原为死代码；修复后 **每回合 1 次** observer 请求，而非每个模型 step 一次
- worker 仅精确匹配；前缀通配仅在两个自研 shim 生效，包括 Pi 桥

#### ② MCP 查询工具

插件 hook 不含 `claude_mem_search` 等查询工具，需另配 MCP。`mcp-server.cjs` 依赖 `bun:sqlite`，**必须用 bun 运行**。

```jsonc
"mcp": {
  "claude-mem": {
    "type": "local",
    "command": ["<YOUR_BUN_PATH>", "<HOME>/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"],
    "enabled": true
  }
}
```

安装 bun：`curl -fsSL https://bun.sh/install | bash`。

#### ③ settings 与 worker

配置文件：`~/.claude-mem/settings.json`。

```json
{
  "CLAUDE_MEM_RUNTIME": "worker",
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "<YOUR_NEWAPI_BASE_URL>",
  "CLAUDE_MEM_OPENROUTER_MODEL": "<YOUR_MODEL_NAME>",
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "20",
  "CLAUDE_MEM_LLM_TIMEOUT_MS": "120000",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>"
}
```

`CLAUDE_MEM_PROVIDER=openrouter` 使用 **OpenAI Chat Completions**，不是 Anthropic：

| 项目 | OpenAI（此处使用） | Anthropic（此处不用） |
|---|---|---|
| 请求 | `POST <BASE_URL>/chat/completions` | `/v1/messages` |
| 认证 | `Authorization: Bearer <key>` | `x-api-key` |

`..._BASE_URL` 填 OpenAI 兼容网关，`..._API_KEY` 填 OpenAI 协议 key；同一网关若两套协议 key 不同，用 OpenAI 那个。

填好占位符后：

```bash
cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart
curl 127.0.0.1:37700/api/health     # 端口见 $SETTINGS 的 CLAUDE_MEM_WORKER_PORT
```

**worker 地址规则**

| 项目 | 规则 |
|---|---|
| 默认 host | `CLAUDE_MEM_WORKER_HOST=127.0.0.1` |
| 默认 port | `CLAUDE_MEM_WORKER_PORT=37700 + uid%100`；按 uid 偏移，避免同服务器用户冲突 |
| 写入 | 默认值显式写入 `~/.claude-mem/settings.json`，仅便于查询，不改变取值；保留已有自定义 host/port |
| 解析优先级 | 环境变量 > `settings.json` > 默认公式；三处一致 |

- Pi 桥、wrapper 均按上述优先级；上游 OpenCode 插件仅读 env + 公式，wrapper 在 import 前将 settings 的 host/port 写入 `process.env`
- 换端口：改 `CLAUDE_MEM_WORKER_PORT` → **重启 worker + 宿主**；否则 worker 仍监听旧端口
- 所有消费者跟随该键；redis 队列前缀 `claude_mem_<port>` 也随之改变

### 2. magic-context

添加 plugin，关闭 OpenCode 内置 compaction，由 magic-context 接管（manual setup 要求）：

```jsonc
"plugin": [
  "@cortexkit/opencode-magic-context@latest"
],
"compaction": { "auto": false, "prune": false }
```

配置 `~/.config/cortexkit/magic-context.jsonc`；**`historian.opencode.model` 必填**，缺失会导致 historian 失败并反复提示。

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/cortexkit/magic-context/master/assets/magic-context.schema.json",
  "historian": {
    "opencode": {
      "model": "<YOUR_PROVIDER>/<YOUR_MODEL>"
    }
  },
  "embedding": {
    "provider": "openai-compatible",
    "model": "text-embedding-3-large",
    "endpoint": "<YOUR_NEWAPI_BASE_URL>",
    "api_key": "<YOUR_API_KEY>"
  },
  "dreamer": {
    "opencode": {
      "model": "<YOUR_PROVIDER>/<YOUR_MODEL>"
    }
  }
}
```

故障自检：`npx @cortexkit/magic-context@latest doctor`。

**右侧可视化侧边栏**显示占比 / historian / compartment 状态，属于独立 TUI 插件。注册到 `~/.config/opencode/tui.jsonc`：

```jsonc
{ "plugin": ["@cortexkit/opencode-magic-context@latest"] }
```

- OpenCode 同时加载 `tui.json` 与 `tui.jsonc`，后者优先
- magic-context 仅在自身安装向导 / `doctor` 时写入，侧边栏为显式 opt-in
- `opencode-setup.sh` 自动补齐，只增不删；关闭需手动删除条目

### 3. ponytail

```jsonc
"plugin": [
  "@dietrichgebert/ponytail"
]
```

### 4. notify

来源：[brilliantrough/opencode-notify-hub](https://github.com/brilliantrough/opencode-notify-hub)。

1. 下载 release 资产 `opencode-notify-plugin-*.zip`
2. 解出 `session-notify.js`，放到 `~/.config/opencode/plugins/`；目录插件自动加载，无需 config 条目
3. 在启动 OpenCode 的 shell 配置中 export 环境变量：

| 变量 | 要求 |
|---|---|
| `NOTIFY_GATEWAY_URL`、`NOTIFY_INGEST_KEY` | 必填 |
| `NOTIFY_MACHINE`、`NOTIFY_HEARTBEAT_MS` 等 | 可选；见仓库 `packages/plugin/src/config.ts` |

### 5. codegraph（代码知识图谱 MCP）

来源：[colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)。

- 预索引代码知识图谱，查询一次取回符号源码与调用路径，含 grep 难以跟踪的动态分派
- 随文件变更自动增量同步，100% 本地

```bash
curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh   # CLI 装到 ~/.local/bin
```

```jsonc
"mcp": {
  "codegraph": {
    "type": "local",
    "command": ["codegraph", "serve", "--mcp"],
    "enabled": true
  }
}
```

全局配一次，各项目各建一次索引；未 init 时 MCP 无内容可查。

```bash
cd your-project && codegraph init
```

### 6. later（延迟发送 prompt）

挂机等实验结果：**直接在输入框输入，不是 slash 命令。**

```text
later 5h 查看当前实验的运行结果
```

| 输入 | 行为 |
|---|---|
| `later 5h <prompt>` | 回车只排程，不发给模型；到点以用户消息注入 |
| `later list` | 查看排程 |
| `later cancel 2` | 取消第 2 条 |
| `later cancel all` | 取消全部 |

- **零模型开销**：TUI 拦 Enter；命中关键字后排程、清空输入、`ctx.consume()`，不发请求
- **到点发送**：`session.promptAsync` 注入会话，等同本人输入回车；agent 忙时入队，本轮 step 结束后处理
- 实测：`bash sleep 25` 期间注入，工具返回后同一回合回复
- **仅进程内有效**：退出/重启丢失未触发排程；挂机用 tmux

**必须安装为 TUI 插件：**

- server 插件的 `chat.message` / `command.execute.before` 拦不住模型调用；清空 `parts` 仍会建 session、走模型，官方 issue #30268 同结论
- TUI 插件才有 `command.register` / `keymap` / prompt ref
- 放到 `~/.config/opencode/tui-plugins/`，在 `tui.jsonc` 引用；**不能放 `plugins/`**，该目录只认 server 签名，否则启动即崩

```jsonc
{ "plugin": ["@cortexkit/opencode-magic-context@latest", "./tui-plugins/later"] }
```

`opencode-setup.sh` 自动部署并补条目，只增不删。

### 7. 按键（Enter 发送 / Shift+Enter 换行）

OpenCode 的 `tui.jsonc`：

```jsonc
"keybinds": {
  "input_submit": "return",
  "input_newline": "shift+return",
  "prompt_submit": "none"
}
```

| 宿主 | 配置与生效方式 |
|---|---|
| OpenCode | 脚本确认后更新这三个 action、迁移旧发送绑定；先显示差异并备份，保留其它按键/插件/凭据；重启生效 |
| Pi | `dot_file/pi/keybindings.json`：`tui.input.submit: [enter]`、`tui.input.newLine: [shift+enter]`，保留自定义 `app.*`；脚本按模板部署，本机修改后 `/reload` 生效 |

- Enter 发送，Shift+Enter 换行；不绑定 Ctrl+Enter，不再把 Ctrl+J 设为发送
- Pi 旧 LF 提交兼容逻辑仅在 Ctrl+J 绑定为 submit 时启用，此配置不触发
- `later` 只拦普通 Enter，修饰键 + Enter 不触发排程
- 不修改 tmux、Konsole、VS Code 或 SSH 设置

**终端边界：** Shift+Enter 需要终端传递不同于 Enter 的输入。若 Ctrl+Enter 被编码成普通 Enter/LF，应用无法还原物理按键；“不绑定”不保证所有终端按下都无效果。

## opencode.jsonc 最小配置

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "@cortexkit/opencode-magic-context@latest",
    "@dietrichgebert/ponytail",
    "./plugins/claude-mem-wrapper.js"
  ],
  "mcp": {
    "claude-mem": {
      "type": "local",
      "command": ["<YOUR_BUN_PATH>", "<HOME>/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"],
      "enabled": true
    },
    "codegraph": {
      "type": "local",
      "command": ["codegraph", "serve", "--mcp"],
      "enabled": true
    }
  }
}
```

npm 条目在 OpenCode 重启时自动安装；配置改动也需重启生效。

## 更新

### Skills

本仓库 skill 由三个 setup 脚本统一调用的 `skills-sync.sh`（仓库根）分组同步，**重跑 setup 即更新**。同步源：本机无仓库克隆时自动取 GitHub `main` tarball；有克隆时**以本地克隆为源，先 `git pull` 才会带上远端新版**。分组即仓库 `skills/{base,accel,kb}/` 目录，新增 skill 放入对应组目录即可，无名单维护：

| 组 | 策略 |
|---|---|
| base（品味/流程，19） | 每次随仓库刷新；本地有未回流改动先整目录备份到 `~/.local/share/agent-skills/.backups/` 再覆盖（回流后删备份） |
| accel（算力平台模板，7） | 缺才装；本机特化后永不覆盖 |
| kb（公共知识，1） | 每次随仓库刷新，不备份 |

客户端不分组：实体直落 `~/.agents/skills/<名>`，装了 Claude Code 的机器同步 `~/.claude/skills/<名>`（有差异才写）。

第三方源（mattpocock/drawio/find-skills 等）照旧：

```bash
npx skills update -g   # 只遍历 ~/.agents/.skill-lock.json,不装新增 skill
```

- 手工拷贝的副本不在 lock 中，`npx skills ls -g` 显示 `Source: local`，update 不碰
- 本仓库 skill 不再走 `npx skills add`：它无条件覆盖且无分组策略

### 插件本体（不含配置）

| 插件 | 更新方式 |
|---|---|
| Pi 本体与已装包，magic-context 除外 | 步骤 2，默认 Y；逐包 `pi update <spec> --no-approve`，不用 `--all` |
| 本仓库 Pi git 包 / npm 包 | 同步骤 2，含 UI/later/耗时/主题；`pi-autoname@0.6.8` 钉版，Pi 会跳过 |
| magic-context（Pi） | 步骤 3.1 独立询问，默认 N |
| magic-context（OpenCode） | 停会话 → 清包缓存 → 重启拉新版、迁移 DB |
| context-mode fork（两侧）、later、notify | 每次拉最新 release/raw 比对；有差异才替换，原文件存 `.bak-YYYYmmddHHMMSS` |
| claude-mem wrapper | 脚本生成；内容不同时才询问替换 |
| OpenCode 的 magic-context / ponytail | 脚本仅保证配置条目存在；升级由 OpenCode 包缓存决定 |

**magic-context 永远单独升级。** 两侧共享 `context.db`，必须选两边都无人使用的时段。Pi 不用 `--all`，避免顺带升级；OpenCode 停会话后运行 `rm -rf ~/.cache/opencode/packages/@cortexkit/opencode-magic-context@latest`，再重启。

### 配置合并

重跑 `opencode-setup.sh` / `pi-setup.sh` 幂等，按字段合并、不覆盖本地敏感值。

**共同规则**

- 有变更：原文件先存 `.bak-YYYYmmddHHMMSS`；无变更：不写
- 非敏感字段跟模板；本地独有键保留
- 敏感键、本机已有值对应的模板 `<占位符>`：保留本地值
- magic-context 合并后由 JSONC 规整为 JSON；注释保留在 `.bak`，不在新文件中

| 文件 | 更新策略 / 特例 |
|---|---|
| `~/.config/opencode/opencode.json` | 已有 provider 保留本地 `options`（apiKey/网关），仅覆盖 `models`；新增 provider 整块加入；其它字段仅补缺键 |
| `~/.claude-mem/settings.json` | 非敏感字段含 `CLAUDE_MEM_*_MODEL` 随模板；`CLAUDE_MEM_PROVIDER` 强制 `openrouter` |
| `~/.config/cortexkit/magic-context.jsonc` | 同 settings；含与 OpenCode 共用的 `historian.pi` / `dreamer.pi` 块 |
| `~/.pi/agent/{settings,models}.json`、`~/.agents/mcp.json` | 同 settings，由 `pi-setup.sh` 处理；已有 `tuiMode` 保留本地选择；mcp.json 本地命令路径在合并前替换 |
| `~/.pi/agent/agents/*.md`、`extensions/claude-mem.ts` | 整文件部署；有差异才写，原文件留时间戳备份 |

**隐私保护边界**

- 键名命中 `SENSITIVE`，或模板值为 `<占位符>`：机器上已有值永不覆盖
- `SENSITIVE`：`api[_-]?key` / `secret` / `token` / `password` / `credential` / `bearer` / `auth` / `cookie` / `ingest` / `webhook` / `base[_-]?url` / `url` / `endpoint` / `host` / 以 `key` 结尾
- `opencode.json` 整块本地优先；provider 模型按上表单独更新
- 模型名不受保护：`*_MODEL`、各 provider 的 `models`、magic-context 的 model 字段随模板；`-y` 直接覆盖，交互模式先列变更
- 整文件覆盖的 `agent-skills-ui.json` / `agent-skills-editor.json` / `keybindings.json` 不含隐私内容

回归检查：`python3 tests/merge-private-preservation.py`；selfcheck 也会运行。

## 单装某一个

```bash
npx skills add brilliantrough/agent-skills@tdd -g -y
```

适合临时试用；注意下次重跑 setup 时本仓库 skill 会按 skills-sync.sh 的分组策略接管（base/kb 与仓库对齐，本地改动备份到 `.backups`）。

## License

自研部分 MIT。`skills/{grilling,domain-modeling,tdd,diagnosing-bugs,code-review}` 来自 mattpocock/skills，归属见 [NOTICE](NOTICE.md)。
