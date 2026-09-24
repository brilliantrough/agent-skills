# agent-skills

个人 agent 环境分发源：三层记忆系统（Magic Context + StrictDoc + claude-mem）、任务工作流、个人前端品味。一条命令装 skills 本体 + 配插件。

**默认安装（`-y`，幂等）** —— 启动后只问一轮凭据（统一网关 + 5 个 key，见后文）：

OpenCode（主目标）：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)" -- -y
```

Pi：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/pi-setup.sh)" -- -y
```

只要 skills、不配插件：

```bash
npx skills@latest add brilliantrough/agent-skills --all -g -y
```

skill 装在 `~/.agents/skills/`，重开 agent session 生效。

Codex（best effort）：

```bash
bash -c "$(curl -fsSL --connect-timeout 8 -m 60 https://raw.githubusercontent.com/brilliantrough/agent-skills/main/codex-setup.sh)"
```

**`-y` 语义**：不再逐项确认，一律取默认 —— 默认 Y 的照做（装缺件、字段级合并写配置并保留本地敏感值、刷新 skills），默认 N 的跳过（notify 插件、覆盖插件缓存、升级 Pi 本体、无代理继续、AGENTS.md 注入）。`-y` 下唯一还会问的是凭据；无终端时静默跳过、占位符保留（无人值守用环境变量预填，见后文）。等价写法：`--yes`、环境变量 `ASSUME_YES=1`、管道形式 `curl -fsSL <脚本 URL> | bash -s -- -y`。

**逐句确认（不给 `-y`）** —— 写每个文件前列出变更项（模型名 / `models` 在内），逐项可拒绝：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/pi-setup.sh)"
```

OpenCode 为主；Pi 与 OpenCode 共享 `~/.claude-mem/settings.json` 与 `~/.config/cortexkit/magic-context.jsonc`；Codex 只复用 skills 原文，不改技能工作流。详见各自小节。

## Skills(18 个)

来自 [mattpocock/skills](https://github.com/mattpocock/skills)（MIT，见 [NOTICE](NOTICE.md)）：

| Skill | 用途 |
|---|---|
| `grilling` | 对计划/设计穷追不舍地访谈，直到每个分支有结论 |
| `domain-modeling` | 领域模型、术语表 |
| `tdd` | 红-绿-重构 |
| `diagnosing-bugs` | bug 诊断回路：先建反馈回路，再假设原因 |
| `code-review` | 双轴审查：规范符合度 + spec 忠实度 |

三层记忆系统（自制）：

| Skill | 用途 |
|---|---|
| `load-mem` | 启动/接续工作时恢复记忆：StrictDoc、Magic Context、claude-mem 与代码证据并用，分清现行规范与历史 |
| `save-mem` | 保存知识：Agent 自选存储位置、粒度、时机，允许多处保存；短语、列表、表格优先 |
| `migrate-mem` | 为已有项目建立/补全记忆，初始化可读的 StrictDoc 文档；不假定旧工作流、不搬原文件 |

- 三套系统互补，允许交叠：同一决策同时进 StrictDoc 和 Magic Context 合理，不强制逐条分流。冲突时以 StrictDoc 当前有效规范为准。规范随明确决策更新并简短告知，不因猜测或每次任务频繁改动。
- 文档默认中文；具体调查和存取路径由 Agent 判断。

技术写作（自制）：

| Skill | 用途 |
|---|---|
| [`readable-docs`](skills/readable-docs/SKILL.md) | 所有面向人的技术文本：短语、分点、紧凑对比表；保留事实、条件与约束强度 |

- 默认适用于 README、设计说明、计划、报告、runbook、变更记录、记忆文档；不限目录。
- 风格：PPT 要点式扫读；单元格不塞长文，复杂因果留短段落。示例见[中文改写示例](skills/readable-docs/references/examples.md)。
- 接入：装 skill，并把 [AGENTS.tail.md](AGENTS.tail.md) 规范块合入项目 `AGENTS.md`（已有项目也需更新）。
- 边界：不批量重写旧文档；不改模板、规范强度、代码、原始证据。

任务工作流（自制；手动指定优先，未指定时由 Agent 按任务意图选）：

| Skill | 用途 |
|---|---|
| `quick-do` | 行为明确的小修小补：读相关代码 → 当前会话直接改并验证；不 grilling、不写计划 |
| `steady-do` | 日常功能/插件/扩展：理解项目 → 分轮澄清 → 当前会话实现并验证；不写交接文档 |
| `plan-brief` | 长程多阶段任务：澄清 → 计划 `docs/plans/<slug>.md` + 启动 prompt → 新会话执行 → 报告 → 原会话审查 |

- 选择看不确定性、耦合、风险、交接需求，不按字数机械分档；quick/steady 难判时用 `steady-do`。适合交接但用户未要求时，先建议 `plan-brief` 并确认，不擅自把「现在实现」改成「只交计划」。
- 共同口径：事实自己查，只问未决关键选择；ponytail 简洁品味；最小真实运行 + 代码复读，不默认加测试/TDD（用户明确要求及项目强制检查照常）。检查通过 ≠ 真实交互已验收，未验证项必须说明。
- skill 指令统一英文，回复跟随用户语言（默认中文）。例：「用 steady-do，先问清楚再做」。

个人领域知识（自制）：

| Skill | 用途 |
|---|---|
| `personal-ui-taste` | 个人前端审美：浅色信息密集界面、多系列图表焦点联动、密集图表就近悬浮、症状索引与反馈演化协议 |

科研实验（自制；ponytail for experiments：规模随证据收缩，完整性满足论点）：

| Skill | 用途 |
|---|---|
| `exp-discuss` | 模糊想法先聊清楚：带证据分轮追问、点出被忽略的细节、逼出「最便宜的证伪观测」；不设计矩阵、不跑东西 |
| `exp-campaign` | 分阶段可剪枝的实验战役：观察已有结果 → 枚举最大空间 → 廉价探针剪枝 → 带观察门限的决策树计划，按阶段交给 exp-batch |
| `exp-batch` | 执行一条有界分支（方法×数据×预算 或消融分支）：先确认未被剪枝、预检环境与资源（显式指定可见设备）、按项目惯例运行，指标落共享表格 |
| `exp-probe` | 一次性抽查：补数据点、失败重跑、sanity check、最小复现；至多一个聚焦问题，一行汇报 |

科研图件（自制）：

| Skill | 用途 |
|---|---|
| `editable-vector-slides` | SVG/PDF 科研图 → 可编辑矢量 PDF + 原生 PPTX（路径/文字/渐变/阴影，非截图）；含依赖安装、验收清单、踩坑清单 |

## 依赖

- Matt 的 6 个 skill：零依赖
- 记忆 skill：配合 Magic Context、claude-mem、`docs/` StrictDoc；缺某一层仍可用其余层。`.sdoc` 校验需要 `strictdoc`：脚本末尾检查 `uv`（缺则装），可选 `uv tool install strictdoc==0.28.1` 全局装（升级 `uv tool upgrade strictdoc`）
- 工作流 / 品味 / 技术写作 skill：无硬依赖
- 项目接入记忆系统：用 [AGENTS.tail.md](AGENTS.tail.md) 中 `memory-system:start/end` 之间的引导块

## 首次部署：只需要网关 + 5 个 key

三个 setup 脚本启动后**问一轮凭据**并填好各配置（只在首次部署问：目标文件都不含 `<YOUR_*>` 占位符就跳过）。网关**回车=默认**，每个 key **回车=跳过、占位符保留**，重跑可补。

| 问什么 | 填到哪里 |
| --- | --- |
| 统一网关（回车=默认 `https://api.pezayo.com/v1`；输 `-` 留占位符） | `pi/models.json`（anthropic 协议填根域、openai 协议带 `/v1`）、`opencode.json` 各 provider `baseURL`、`~/.claude-mem/settings.json`、magic-context embedding `endpoint` |
| `claude-newapi` 的 key（anthropic 协议 · claude 模型 · 网关 claude code 分组） | `opencode.json` / `pi/models.json` 的 `claude-newapi.apiKey` |
| `codex-newapi` 的 key（openai responses 协议 · gpt 模型 · 网关 codex 分组） | 同上两处 `codex-newapi.apiKey` |
| `anthropic-newapi` 的 key（anthropic 协议 · 国产模型 · 网关 coding anthropic 分组） | 同上两处 `anthropic-newapi.apiKey` |
| magic-context embedding 的 key（openai 协议 · 嵌入模型 · 任意分组） | `magic-context.jsonc` 的 `embedding.api_key` |
| claude-mem 的 key（openai chat completions · 任意模型 · 建议 coding openai 分组） | `~/.claude-mem/settings.json` 的 `CLAUDE_MEM_OPENROUTER_API_KEY` |
| mcphub MCP host（可选，回车跳过；codex 侧不问） | `~/.agents/mcp.json`、`opencode.json` 的 `mcp.mcphub-web.url` |

- 同一份模板里的三处 `<YOUR_NEWAPI_API_KEY>` 按 provider 名就近替换，不串位。
- 无人值守：`PI_GATEWAY_BASE_URL` + `PI_GATEWAY_API_KEY`（兜底给没单独给的槽）；分开给用 `PI_CLAUDE_NEWAPI_API_KEY` / `PI_CODEX_NEWAPI_API_KEY` / `PI_ANTHROPIC_NEWAPI_API_KEY` / `PI_EMBEDDING_API_KEY` / `PI_CLAUDE_MEM_API_KEY`，另加 `MCPHUB_HOST`。
- 跳过的占位符按脚本末尾清单手工补（清单列出哪个文件差哪些），或重跑脚本重新问。
- **凭据永不被覆盖**（api key / base url / host）；**模型名跟模板走**：各 provider `models`、`CLAUDE_MEM_*_MODEL`、magic-context 的 model 字段。`-y` 直接覆盖，交互跑在写文件前列出变更并问一次 —— 想保住自定义后端的模型就别用 `-y`。
- 非 `/v1` 风格网关（自定义路径）：填完核对 `pi/models.json` 的 anthropic 根域与 claude-mem 的 BASE_URL。
- 仍需手工：`pi/auth.json` 的 coding-plan key（仅 zai/kimi 这类内置 provider 时）、`~/.func`（dot_file 的 `linux-setup.sh` 部署）、notify 的 `NOTIFY_*` 环境变量（要装 notify 才有）。

## Windows(Git Bash)

同一份 `*-setup.sh` 直接跑（Git Bash，不是 WSL；WSL 按 Linux 来）。硬前置只有 Git for Windows（自带 bash / curl / git / cygpath），其余缺件由脚本代装或给出命令：

| 需要 | 缺了怎么办 |
| --- | --- |
| Python 3 | 脚本用 uv 自管理的 3.12 兜底（会问）；或 `winget install Python.Python.3.12` |
| Node LTS | fnm 官方脚本装；失败 `winget install OpenJS.NodeJS.LTS` |
| bun / uv | 各自官方脚本（支持 MinGW）；失败提示手工命令 |

上游的 `install.ps1` / winget 包面向零前提用户；本项目约定 Git Bash，一份 bash 覆盖三个脚本。命令与 Linux 相同（在 Git Bash 里跑顶部的命令）。

脚本自己处理的差异：

- **路径**：写进 `mcp.json` / `opencode.json` 的本机路径转 `C:/...` 原生形式（Git Bash 的 `/c/...` 宿主读不懂），可执行文件补 `.exe`
- **claude-mem worker 端口**：无 uid 按 77 兜底 → `37777`，与 claude-mem 及桥扩展的 `process.getuid?.() ?? 77` 一致
- **codegraph**：官方 `install.sh` 只认 Darwin/Linux → `npm i -g @colbymchenry/codegraph@latest`
- **Pi 本体**：官方 `install.sh` 只认 Darwin/Linux → `npm i -g --ignore-scripts @earendil-works/pi-coding-agent`
- **uv 镜像**：Windows 写 `%APPDATA%\uv\uv.toml`（uv 不读 `~/.config`）
- **本仓库开发用的类型软链**：跳过（`ln -s` 需开发者模式，否则退化成整目录拷贝）
- **配置目录**：与 Linux 一致（Git Bash 的 `$HOME` 即 `%USERPROFILE%`）

宿主成熟度（脚本不改变）：

| 宿主 | 官方立场 |
| --- | --- |
| Pi | 原生 Windows + Git Bash 是官方路径（[Run Pi on Windows](https://pi.dev/docs/latest/windows)） |
| OpenCode | 能原生跑，官方仍推荐 WSL |
| Codex | 原生 Windows 是 experimental，官方推荐 WSL；脚本按 best effort 配置并提示 |

## Codex 插件配置(best effort)

| 项目 | `codex-setup.sh` 的行为 |
|---|---|
| 前置 | 已装 Codex ≥0.128.0，支持 `codex plugin marketplace`；Python ≥3.11、curl、git。不升级系统 Python / Codex |
| 依赖 | 缺 Node LTS / Bun / uv 时询问安装；可选 `uv` 装 strictdoc==0.28.1；已有 Node 需 ≥20 |
| claude-mem | 优先复用 `~/.claude/plugins/marketplaces/thedotmack` 的 runtime，注册 `claude-mem@claude-mem-local`（自带 MCP、skills、hooks）；缺失/过旧时询问官方 `--ide codex-cli` 安装器 |
| 共享记忆配置 | 已有 `~/.claude-mem/settings.json` 原样保留；官方安装器临时写入后也恢复（provider/URL/key 在内）；首次创建 OpenAI 兼容后端占位符，需手工填 |
| Ponytail | 官方 `ponytail@ponytail`；Node 须在启动 Codex 的 PATH 中 |
| CodeGraph | 缺则装 CLI + `codex mcp add` 注册；现有 `mcp_servers.codegraph` 保留；按项目 `codegraph init` |
| skills | 只装缺失的本仓库 skills（`--agent codex`）；已存在的共享 skills 不覆盖 |
| Magic Context / notify | 不安装；原生压缩不动；缺 `ctx_*` 的记忆技能仅 best effort |
| 配置安全 | 先显示待添加项并确认，修改前备份；TOML 写入交给 Codex CLI；模型/认证配置不纳入管理；已安装/显式禁用项保留，重复运行不自动升级 |

- 使用 `${CODEX_HOME:-~/.codex}/config.toml`；首次 claude-mem 官方安装器写死 `~/.codex`，自定义 `CODEX_HOME` 时只复用已有 runtime，缺失则提示手工装。`CLAUDE_CONFIG_DIR` / `CLAUDE_MEM_DATA_DIR` 可指定共享资产/记忆目录。
- 官方 claude-mem 安装器会更新共享资产、注册 Claude 插件并停止 worker（`--no-auto-start` 也避免不了停机）；已有 runtime 的升级默认不执行。装完填好记忆后端配置，再 `npx claude-mem@latest start`。
- 装完在 Codex **`/hooks` 审阅并信任 hooks，再开新会话**；用 `/mcp` 确认连接并实际调用查询工具。
- 失败告警并返回非零，不误报完成。

手工接入（claude-mem 首次安装同样有上述共享配置影响）：

```bash
npx claude-mem@latest install --ide codex-cli
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail
codex mcp add codegraph -- codegraph serve --mcp
npx skills@latest add brilliantrough/agent-skills --skill '*' --agent codex -g -y
```

更新（不在每次 setup 里自动跑）：

```bash
codex plugin marketplace upgrade ponytail
codex plugin add ponytail@ponytail
# claude-mem runtime 更新后,重新装入其本地插件快照:
codex plugin add claude-mem@claude-mem-local
npx skills@latest update -g
```

skills 共享，更新也影响 OpenCode；claude-mem runtime 更新按官方文档来，先备份共享配置。

官方参考：[Codex MCP](https://developers.openai.com/codex/mcp) · [Codex hooks](https://developers.openai.com/codex/hooks) · [claude-mem 安装器](https://github.com/thedotmack/claude-mem/blob/main/src/services/integrations/CodexCliInstaller.ts) · [Ponytail](https://github.com/DietrichGebert/ponytail#codex) · [CodeGraph](https://github.com/colbymchenry/codegraph#quick-start)

## Pi 配置

[Pi](https://pi.dev) 核心不带 MCP/subagent，能力全靠 npm 包与扩展；skills 原生读 `~/.agents/skills/`。`pi-setup.sh` 与 `opencode-setup.sh` **共享** `~/.claude-mem/settings.json` 与 `~/.config/cortexkit/magic-context.jsonc`（同一套字段级合并，两边幂等，不破坏本地值）。配置模板在 [dot_file/pi](https://github.com/brilliantrough/dot_file/tree/master/pi)。

> 开发本仓库时：脚本最后一步把本机已装的 Pi 包软链进仓库 `node_modules/`（`.gitignore` 已排除），让编辑器/pi-lens 能解析 `@earendil-works/pi-*` 与 `node:*` 类型——否则报 "Cannot find module"（运行时由 Pi 提供，不影响使用）。

| 项目 | `pi-setup.sh` 的行为 |
|---|---|
| Provider/模型 | 部署 `~/.pi/agent/models.json`：claude-newapi(anthropic)、codex-newapi(openai-responses)、anthropic-newapi；**anthropic 协议 `baseUrl` 填根域**（pi 自动补 `/v1/messages`，填 `/v1` 会 404），openai 协议带 `/v1`；`compat.supportsStore:false`、`thinkingLevelMap`(xhigh/max) 对应 opencode 的 variants |
| 设置 | `~/.pi/agent/settings.json`：默认 provider/model/thinking、`defaultTools` 补 `grep/find/ls`（pi 默认只开 read/bash/edit/write）、`packages` 由 `pi install` 维护；不写 Pi 的 `compaction` 开关 —— magic-context Pi 扩展在 `session_before_compact` 里自行 cancel 原生压缩（与官方 `setup --harness pi` 行为一致） |
| 运行默认值 | `modelThinkingLevels`：`codex-newapi/gpt-6-astra`、`codex-newapi/gpt-5.6-sol` 用 `xhigh`，其余全局 `high`；agent 级 `retry`：`maxRetries:8`、`baseDelayMs:4000`（4/8/16/32/64/128/256/512 秒，累计 17 分钟，加上首发最多 9 次请求），原生指数退避，不开 provider 内层重试 |
| 自动命名 | `pi-autoname@0.6.8` + `~/.pi/agent/pi-autoname.json`：`codex-newapi/gpt-5.6-sol` 在任务结束后命名；冷却 1440 分钟、尊重手工名称、`/autoname` 手动触发。会把最近对话片段发给命名模型；失败回退当前会话模型/文本提取。该版本配置路径固定 `~/.pi/agent`，自定义 `PI_CODING_AGENT_DIR` 时跳过此插件 |
| 任务耗时 | 本仓库包的 `pi/extensions/message-timing.ts`：`agent_start` → `agent_settled` 记秒数（含工具/重试/排队后续消息）；custom entry 持久保存、不进模型上下文、不高频刷新，仅 TUI |
| 凭据 | `~/.pi/agent/auth.json`（权限 600，内置 coding-plan provider 的 key）：模板是 `zai-coding-cn`/`kimi-coding` 占位符；字段级合并、已填 key 不覆盖、仅初始化缺失文件。内置 provider（智谱 coding plan、Kimi For Coding、qwen/xiaomi token plan、opencode-go 等）不需要写 `models.json` |
| MCP | `~/.agents/mcp.json`（共享）：mcphub-web（远程 URL）、codegraph、claude-mem；本地命令路径部署时替换为本机 `bun`/`codegraph` 绝对路径（pi-mcp-adapter 读取）。mcphub-web 配 `directTools` 挂 5 个直连工具（tavily search/extract、firecrawl scrape/search/research_search_github，首次调用自动 lazyConnect），其余走 `mcp` 网关（`mcp({search/describe/connect})`，网关内调用名带 `mcphub-web_` 前缀） |
| 插件 | `pi install npm:...`：pi-mcp-adapter、`@dietrichgebert/ponytail`（官方带 pi-extension）、`pi-subagents-j0k3r`、`pi-lens`（实时诊断/符号检索）、`@juicesharp/rpiv-ask-user-question`（结构化提问 `ask_user_question`——pi 核心没有，plan-brief/grilling 需要）、`@cortexkit/pi-magic-context`、`pi-autoname@0.6.8`；**本仓库自身也是 Pi 包**（`pi install git:github.com/brilliantrough/agent-skills`：个性化 UI `/ui`、claude-mem 桥、`/later`、任务耗时、one-dark 主题；旧散装文件自动清理。`pi update --all` 后脚本明确报版本变化 `本仓库 Pi 插件已更新: <旧> -> <新>(N 个提交)`） |
| context-mode fork | 上游 `context-mode` 与 `magic-context` **都注册 `ctx_search`** —— Pi 同名工具检测会让启动 `process.exit(1)`。本仓库维护 fork（构建后 11 个工具改名 `ctxm_*`，另做三项口径修正），**产物走 GitHub release**（编译产物不进 git 历史）。脚本 curl 最新 release 解到 `~/.pi/agent/vendor/context-mode` 再 `pi install`（没变就跳过；目标机不需要 bun、不需要 clone），并摘掉旧 clone 路径条目（两份同时登记会让 Pi 起不来）。**不要装上游 `npm:context-mode`**，脚本检测到会提示卸载。开发机改完：`bash context-mode/setup.sh --publish`。OpenCode 侧同名处理：`opencode-context-mode-vendor.tar.gz` 解到 `~/.config/opencode/plugins/context-mode/` 再放一层 `entry.js` 入口（不碰 `opencode.json` 的 `plugin` 字段），7 个 skill 进 `~/.config/opencode/skill/` |
| 主题 | `pi/themes/onedark.json` 随 Pi 包提供（One Dark，56 色 token，热重载），`settings.json` 里 `theme: one-dark`。换主题：改 `theme` 或装主题包（`awesome-pi-themes` 65 款、`@inobit/pi-themes`）；`/settings` 里选 |
| claude-mem | 官方无 Pi 适配；本仓库 Pi 包内置自研桥（镜像 opencode 插件契约：POST worker `/api/sessions/init\|observations\|summarize`，`platformSource:"pi"`；采集工具调用 + 助手消息 + **用户 prompt**，支持 `前缀*` 跳过），并提供 `claude_mem_search` 直连 worker（不走 MCP） |
| 个性化 UI | `pi/extensions/ui/index.ts`：纳管的 Atelier 0.10.1 布局/侧栏 + Zentui 0.24.0 编辑器/消息视觉，统一入口，不再装两套 UI 包；LF 提交修复、TPS、HΣ/H₁、R/W、Magic Context `todowrite` 侧栏。配置 `agent-skills-ui.json` / `agent-skills-editor.json`，命令 `/ui`、`/ui sidebar`；[源码与许可证说明](pi/extensions/ui/README.md) |
| 个性化 UI 配置 | 模板整文件覆盖 `~/.pi/agent/{agent-skills-ui,agent-skills-editor,keybindings}.json`（有差异先存 `.bak`，符号链接跳过）；不做一次性迁移。模板即已验证配置（`sidebarPanelLayout`、侧栏自定义面板、`clearSelectionOnRelease` 默认、Enter 发送/Shift+Enter 换行按键）。旧 UI 包（`pi-zentui`/`pi-atelier`/`atelier-bridge`）若在 `packages` 里会被摘掉（先存 `.bak`），避免两套 UI 同时加载 |
| later | 本仓库 Pi 包的 `pi/extensions/later.ts`：`/later 5h <prompt>` 到点注入用户消息（`sendUserMessage` + `deliverAs:followUp`，空闲即发、忙时排队等本轮结束）；`/later list`、`/later cancel <id/all>`。排程只活在当前 pi 进程内，退出/重启/切换会话即丢（挂机用 tmux 保持 pi 常驻） |
| subagent | `~/.pi/agent/agents/{explore,general}.md`（对应 opencode 的 explore/general）；frontmatter 的 `tools` **必须显式写**（默认值引用了不存在的工具） |
| magic-context 版本守卫 | opencode 插件缓存把版本钉死在下载时（重启不自动升级），与 Pi 扩展版本不一致时，共享的 `context.db` 会让新宿主 fail-closed 拒绝主回合；脚本检测到不一致时**默认不启用** Pi 版，并给出「清 `~/.cache/opencode/packages/@cortexkit/opencode-magic-context@latest` → 重启 opencode → 重跑本脚本」步骤 |
| uv/strictdoc | 同 opencode-setup.sh |

手工步骤（不用脚本时）：`pi install` 逐个装 `npm:pi-mcp-adapter`、`npm:@dietrichgebert/ponytail`、`npm:pi-subagents-j0k3r`、`npm:pi-lens`、`npm:@juicesharp/rpiv-ask-user-question`、`npm:@cortexkit/pi-magic-context`、`npm:pi-autoname@0.6.8`、`git:github.com/brilliantrough/agent-skills`（`pi remove <source>` 卸载、`pi list` 查看）；可选 context-mode fork（Pi：`curl -fsSL https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz | tar -xz -C ~/.pi/agent/vendor/context-mode` 再 `pi install ~/.pi/agent/vendor/context-mode`；OpenCode：同样取 `opencode-context-mode-vendor.tar.gz` 解到 `~/.config/opencode/plugins/context-mode` 并 `cp` 包内 `entry.js` 到 `plugins/context-mode.js`）；再把 dot_file 的 `pi/{models,settings,mcp,auth,pi-autoname}.json`、`pi/agents/*.md` 放到对应位置，填好 `models.json` 网关占位符与 `auth.json` coding plan key（`pi auth check --provider <p>` 可验证）。

## OpenCode 插件配置（手工步骤）

一键命令见顶部；下面是不用脚本时的手工步骤。

### 1. claude-mem

```bash
npx claude-mem install --ide opencode
```

装完三件事：

**① wrapper 修复**（upstream bug [thedotmack/claude-mem#2854/#3328](https://github.com/thedotmack/claude-mem/issues/2854)：bundle 导出非函数常量）。bundle 移到 `~/.config/opencode/lib/claude-mem.js`，并由 `opencode-setup.sh` 生成 `~/.config/opencode/plugins/claude-mem-wrapper.js`：

- 只 re-export 插件函数，绕过导出 bug
- 补上游缺失的**用户 prompt 采集**：上游 `chat.message` 处理器只认 `assistant`，而该钩子实际交付 `UserMessage`，用户输入从未被记录。wrapper 把每条用户输入经 `/api/sessions/init` 写入（与 Claude Code 同一通路：`user_prompts` + FTS + Chroma + observer 的 `<user_request>`），统一 contentSessionId 使 init 与插件观测落进同一会话行；不产生额外模型请求
- **前缀通配**：`CLAUDE_MEM_SKIP_TOOLS` 里以 `*` 结尾的条目（如 `mcphub-web_*`、`ctx_*`）在 POST 前按前缀过滤（worker 只做精确匹配，该语法只在两个自研 shim 生效；Pi 桥同）
- 补上游缺失的**助手回复采集**：上游 assistant 分支是死代码。wrapper 在 `experimental.text.complete` 暂存每回合最后一个文本，`session.idle` 时作为 1 条 `assistant_message` 发出——**每回合 1 次** observer 请求，而不是每个模型 step 一次

plugin 条目使用 `./plugins/claude-mem-wrapper.js`。升级 claude-mem 后重跑 `opencode-setup.sh` 重新生成。

**② MCP 工具组**（`claude_mem_search` 等查询工具，插件的 hook 不含工具）。`mcp-server.cjs` 必须用 bun 运行（依赖 `bun:sqlite`）：

```jsonc
"mcp": {
  "claude-mem": {
    "type": "local",
    "command": ["<YOUR_BUN_PATH>", "<HOME>/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"],
    "enabled": true
  }
}
```

bun 安装：`curl -fsSL https://bun.sh/install | bash`。

**③ 配置文件** `~/.claude-mem/settings.json`：

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

`CLAUDE_MEM_PROVIDER=openrouter` 走 **OpenAI Chat Completions 协议**（`POST <BASE_URL>/chat/completions`，`Authorization: Bearer <key>`），不是 Anthropic 的 `/v1/messages` + `x-api-key`。所以 `..._API_KEY` 填 **OpenAI 协议**的 key，`..._BASE_URL` 填 OpenAI 兼容网关地址（同一网关若两套协议 key 不同，用 OpenAI 那个）。

填完占位符后：

```bash
cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart
curl 127.0.0.1:37700/api/health     # 端口见 $SETTINGS 的 CLAUDE_MEM_WORKER_PORT
```

**worker 地址**：脚本把本机默认值显式写进 `~/.claude-mem/settings.json` —— `CLAUDE_MEM_WORKER_HOST=127.0.0.1` + `CLAUDE_MEM_WORKER_PORT=37700 + uid%100`（claude-mem 默认就按 uid 偏移，目的是同一服务器上不同用户不冲突；显式写出只为可见可查，取值不变）。已存在的自定义 host/port 一律保留。解析优先级三处一致：环境变量 > `settings.json` > 默认公式（Pi 桥、wrapper 都按此；上游 OpenCode 插件只认 env + 公式，wrapper 会在 import 它之前把 settings 的 host/port 写进 `process.env`）。换端口：改 settings 的 `CLAUDE_MEM_WORKER_PORT` → **重启 worker**（否则仍听旧端口）+ 重启宿主。各消费者都跟随这个键；副作用：redis 队列前缀 `claude_mem_<port>` 会跟着变。

### 2. magic-context

plugin 条目 + 关闭 opencode 内置 compaction（magic-context 接管压缩，manual setup 要求）：

```jsonc
"plugin": [
  "@cortexkit/opencode-magic-context@latest"
],
"compaction": { "auto": false, "prune": false }
```

配置文件 `~/.config/cortexkit/magic-context.jsonc`（`historian.opencode.model` 必填，缺失时 historian 失败并反复提示）：

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

**右侧可视化侧边栏**（占比 / historian / compartment 状态）是独立的 TUI 插件，注册在 `~/.config/opencode/tui.jsonc`（opencode 同时加载 `tui.json` 与 `tui.jsonc`，后者优先）：

```jsonc
{ "plugin": ["@cortexkit/opencode-magic-context@latest"] }
```

magic-context 只在自身安装向导 / `doctor` 时才写这个文件（侧边栏是显式 opt-in）；`opencode-setup.sh` 自动补齐、只增不删——想关侧边栏就手动删掉该条目。

### 3. ponytail

```jsonc
"plugin": [
  "@dietrichgebert/ponytail"
]
```

### 4. notify

来自 [brilliantrough/opencode-notify-hub](https://github.com/brilliantrough/opencode-notify-hub)。下载 release 资产 `opencode-notify-plugin-*.zip`，解出 `session-notify.js` 放进 `~/.config/opencode/plugins/`（目录内插件自动加载，无需 config 条目）。

环境变量（启动 opencode 的 shell 配置里 export）：

- `NOTIFY_GATEWAY_URL`、`NOTIFY_INGEST_KEY`：必填
- 可选：`NOTIFY_MACHINE`、`NOTIFY_HEARTBEAT_MS` 等，见仓库 `packages/plugin/src/config.ts`

### 5. codegraph(代码知识图谱 MCP)

来自 [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)。预索引代码知识图谱：查询一次取回符号源码与调用路径（含 grep 跟不上的动态分派跳转），索引随文件变更自动增量同步，100% 本地。

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

全局只配一次，每个项目各建一次索引（未 init 时 MCP 无内容可查）：

```bash
cd your-project && codegraph init
```

### 6. later(延迟发送 prompt)

挂机等实验结果用：在**输入框里直接打**（不是 slash 命令）

```text
later 5h 查看当前实验的运行结果
```

回车后这句话**不会发给模型**，而是被排程；到点插件用 `session.promptAsync` 把它作为用户消息注入会话，等同你本人敲进输入框回车。`later list`、`later cancel 2`、`later cancel all` 管理排程。

- **零模型开销**：TUI 层拦 Enter，命中关键字就自己排程、清空输入、`ctx.consume()`，不发任何请求
- **agent 忙也没事**：到点排进会话，本轮 step 结束后立刻处理（实测：`bash sleep 25` 进行中注入，工具返回后同一回合回复）
- **边界**：计时器只活在当前 opencode 进程内，退出/重启即丢未触发的排程——挂机请把 opencode 放 tmux 里
- **为什么是 TUI 插件**：server 插件（`plugins/*.js` 的 `chat.message` / `command.execute.before`）拦不住那一轮（清空 `parts` 也照样建 session 走模型，官方 issue #30268 同结论）；TUI 插件才有 `command.register` / `keymap` / prompt ref
- **不能放 `plugins/`**：那目录只认 server 插件，签名不符会让 opencode 启动即崩；要放 `~/.config/opencode/tui-plugins/` 并在 `tui.jsonc` 里引用

```jsonc
{ "plugin": ["@cortexkit/opencode-magic-context@latest", "./tui-plugins/later"] }
```

`opencode-setup.sh` 会部署插件并补上条目（只增不删）。

### 7. 按键(Enter 发送 / Shift+Enter 换行)

OpenCode 的 `tui.jsonc`：

```jsonc
"keybinds": {
  "input_submit": "return",
  "input_newline": "shift+return",
  "prompt_submit": "none"
}
```

- `Enter` 发送，`Shift+Enter` 换行；不绑定 `Ctrl+Enter`，也不再把 `Ctrl+J` 设为发送。
- `opencode-setup.sh` 经确认后更新这三个 action，迁移旧发送绑定；有差异先显示并备份，其它按键、插件和凭据保留。重启 OpenCode 生效。
- Pi 的 `dot_file/pi/keybindings.json` 设置 `tui.input.submit: [enter]`、`tui.input.newLine: [shift+enter]`，保留自定义 `app.*`。`pi-setup.sh` 按模板部署；本机修改后 `/reload` 生效。旧 LF 提交兼容逻辑仅在 Ctrl+J 被绑定为 submit 时启用，此配置不触发。
- `later` 只拦普通 Enter，带修饰键的 Enter 不触发排程。
- 不修改 tmux、Konsole、VS Code 或 SSH 设置。Shift+Enter 依赖终端能传递不同于 Enter 的输入；若 Ctrl+Enter 被终端编码成普通 Enter/LF，应用无法识别原始物理按键，因此「不绑定」不等于所有终端都能保证按下无效果。

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

npm 形式条目在 opencode 重启时自动安装；配置改动重启 opencode 生效。

## 更新

```bash
npx skills add brilliantrough/agent-skills --all -g -y   # 刷新已装 + 装入仓库新增的 skill
npx skills update -g                                     # 刷新 lock 里登记的第三方源(mattpocock/drawio/find-skills)
```

- `add --all` 幂等：已登记的 skill 有变化才覆盖，仓库新增的 skill 靠它落地。
- `update -g` **不会装新增 skill**：只遍历 `~/.agents/.skill-lock.json` 已登记条目、按内容哈希刷新，上游新增至多打印一行 `To install: npx skills add …`。两个 setup 脚本按 `add --all` → `update -g` 的顺序跑。
- 手工拷进 `~/.agents/skills/` 的副本不在 lock 里（`npx skills ls -g` 显示 `Source: local`），两个命令都不碰；`add` 才纳入跟踪（会以仓库内容覆盖本地副本；服务器上的演化更新请先回流仓库）。

插件本体（不是配置）的更新：

| 插件 | 更新方式 |
|---|---|
| 本仓库 Pi 扩展/主题(git 包)、npm 类 Pi 包 | 脚本步骤 2 的 `pi update --all`（`pi-autoname@0.6.8` 这类钉版被 pi 跳过） |
| context-mode fork(Pi/opencode 两侧)、later、notify | 每次拉最新 release/raw 与已装内容比对：不一致才替换，原文件存 `.bak-YYYYmmddHHMMSS` |
| claude-mem wrapper | 脚本内生成，内容不同才询问替换 |
| opencode 侧 magic-context / ponytail | 脚本只保证配置条目存在，升级由 opencode 自己的包缓存决定 |

重跑 `opencode-setup.sh` / `pi-setup.sh` 幂等，配置按字段级合并、不覆盖本地敏感值：

| 文件 | 更新方式 |
|---|---|
| `~/.config/opencode/opencode.json` | 已存在 provider 保留本地 `options`（apiKey/网关），只按模板覆盖 `models`；模板新增 provider 整块加入；非 provider 字段仅本地缺键时补入 |
| `~/.claude-mem/settings.json` | 非敏感字段跟模板下发（含 `CLAUDE_MEM_*_MODEL` 模型名）；`CLAUDE_MEM_PROVIDER` 强制 `openrouter`；`api key` / `base url` 等敏感键与 `<占位符>` 值保留本地；本地独有键保留 |
| `~/.config/cortexkit/magic-context.jsonc` | 同 settings（含 `historian.pi` / `dreamer.pi` 块，与 opencode 共用） |
| `~/.pi/agent/{settings,models}.json`、`~/.agents/mcp.json` | 同 settings（pi-setup.sh）；mcp.json 的本地命令路径在合并前按本机替换 |
| `~/.pi/agent/agents/*.md`、`extensions/claude-mem.ts` | 整文件部署：内容有差异才写，原文件存 `.bak-YYYYmmddHHMMSS` |

有改动先把原文件存为时间戳 `.bak-YYYYmmddHHMMSS`；合并结果与本地一致则不写。magic-context 的合并会把 JSONC 规整为 JSON（注释丢失，原样保留在 `.bak` 里）。

**隐私内容永不覆盖**：键名命中 `SENSITIVE`（`api[_-]?key`/`secret`/`token`/`password`/`credential`/`bearer`/`auth`/`cookie`/`ingest`/`webhook`/`base[_-]?url`/`url`/`endpoint`/`host`/以 `key` 结尾）或模板值是 `<占位符>` 时，一律保留机器上已有值；`opencode.json` 更是整块本地优先。模型名不受保护：`*_MODEL` 与各 provider 的 `models` 跟模板走（`-y` 直接覆盖，交互跑在写入前列出变更）。三个整文件覆盖的模板（`agent-skills-ui.json`/`agent-skills-editor.json`/`keybindings.json`）不含隐私内容。回归检查：`python3 tests/merge-private-preservation.py`（selfcheck 会一并跑）。

## 单装某一个

```bash
npx skills add brilliantrough/agent-skills@tdd -g -y
```

## License

自研部分 MIT。`skills/{grilling,domain-modeling,tdd,diagnosing-bugs,code-review}` 来自 mattpocock/skills，归属见 [NOTICE](NOTICE.md)。
