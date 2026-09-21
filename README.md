# agent-skills

个人 agent skills 集，含三层记忆系统、任务工作流与个人前端品味。

**一键配置**（交互确认、幂等）——一条命令同时搞定「装 skills 本体」和「配插件」（claude-mem / magic-context / ponytail / notify / codegraph / later）：

OpenCode（主目标）：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)"
```

Pi：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/pi-setup.sh)"
```

只想要 skills、不配插件的场景：

```bash
npx skills@latest add brilliantrough/agent-skills --all -g -y
```

skill 装在 `~/.agents/skills/`，重开 agent session 生效。

**Codex 插件配置(best effort)**：

```bash
bash -c "$(curl -fsSL --connect-timeout 8 -m 60 https://raw.githubusercontent.com/brilliantrough/agent-skills/main/codex-setup.sh)"
```

本仓库仍以 **OpenCode 为主**；Pi 与 OpenCode 共享记忆配置（`~/.claude-mem/settings.json`、`~/.config/cortexkit/magic-context.jsonc`）；Codex 复用现有 skills 原文，不为其修改技能工作流。详见下面的 Pi 与 Codex 说明。

## Skills(17 个)

来自 [mattpocock/skills](https://github.com/mattpocock/skills)(MIT,见 [NOTICE](NOTICE.md)):

| Skill | 用途 |
|---|---|
| `grilling` | 对计划/设计做穷追不舍的访谈,直到每个分支都有结论 |
| `domain-modeling` | 领域模型、术语表 |
| `tdd` | 红-绿-重构的测试驱动开发 |
| `diagnosing-bugs` | bug 诊断回路:先建反馈回路,再假设原因 |
| `code-review` | 双轴审查:规范符合度 + spec 忠实度 |

自制·三层记忆系统:

| Skill | 用途 |
|---|---|
| `load-mem` | 启动或接续工作时恢复相关项目记忆：结合 StrictDoc、Magic Context、claude-mem 与代码证据,分清当前规范和历史 |
| `save-mem` | 保存有用知识：Agent 自主选择存储位置、粒度和时机,允许多处保存；文档优先短语、列表、表格与少量 `PS:` 解释 |
| `migrate-mem` | 为已有开发痕迹的项目建立或补全记忆,重点初始化可读的 StrictDoc 文档；不假定旧工作流或自动搬走原文件 |

**记忆 intent**：三套系统相互补充,功能可以交叠；同一事实或决策同时保存在 StrictDoc 和 Magic Context 是合理的,不强制逐条分流或同步。发生口径冲突时,以 **StrictDoc 中当前有效的规范** 为准。规范可以随已明确的决策变化而主动更新,并简短告知用户,无需另等“保存”命令；但不因猜测、临时尝试或每次任务就频繁改动。普通记忆和说明文档可以更灵活地维护,保留有价值的历史脉络即可。文档默认中文,短语、列表、表格与少量 `PS:` 解释优先；技能提供目标与必要工具用法,具体如何调查和存取由 Agent 判断。

自制·任务工作流(手动指定优先,未指定时由 Agent 按任务意图选择):

| Skill | 用途 |
|---|---|
| `quick-do` | 行为明确、边界清楚的小修小补或机械改动：读相关代码 → 当前会话直接修改与验证；不展开 grilling、不写计划 |
| `steady-do` | 日常功能、插件、扩展及存在关键设计决策的任务：理解项目 → 分轮澄清 → 当前会话实现与验证；不写交接文档 |
| `plan-brief` | 需要规划与执行分工的长程多阶段任务：澄清 → 计划 `docs/plans/<slug>.md` + 启动 prompt → 新会话执行 → 报告 `<slug>.report.md` → 原会话审查 `<slug>.review.md`；本会话不实施 |

- **选择依据**：看不确定性、模块耦合、风险与交接需求,不按需求字数或文件数量机械分档；quick/steady 难以判断时用 `steady-do`。复杂任务适合交接但用户未要求时,先建议 `plan-brief` 并确认,不擅自把“现在实现”改成“只交计划”。
- **显式选择优先**：用户指定哪个就用哪个；发现所选流程无法安全承载任务时说明原因、协商调整,不静默切换。普通问答和只读解释不强制套开发流程。
- **共同口径**：事实自己查、只问未决的关键选择；保持 ponytail 简洁品味。默认最小真实运行 + 代码复读,不新增测试/TDD/验证脚本；用户明确要求及项目强制检查照常遵循。检查通过不等于真实交互已验收,未验证项必须说明。
- 三个 skill 的指令统一用英文；回复与交付物跟随用户语言,默认中文。例如：“给现有插件增加一个功能，先问清楚再做，用 steady-do。”

自制·个人领域知识:

| Skill | 用途 |
|---|---|
| `personal-ui-taste` | 个人前端审美:已确认偏好与场景规则(浅色信息密集界面 / 预览型工作台)、多系列图表焦点联动、密集图表就近悬浮、症状索引与反馈演化协议 |

自制·科研实验(ponytail for experiments:实验规模随证据收缩,但完整性满足论点):

| Skill | 用途 |
|---|---|
| `exp-discuss` | 把一个还很模糊的科研想法聊清楚：带着已有证据分轮追问 frontier 问题、点出被忽略的细节、逼出「最便宜的证伪观测」，最后明确交给 exp-campaign / exp-batch / exp-probe 或有意搁置；不设计矩阵、不跑东西 |
| `exp-campaign` | 为一个研究假设设计分阶段、可剪枝的实验战役：观察已有结果 → 访谈对齐 → 枚举最大实验空间 → 用廉价探针实验剪枝 → 产出带观察门限的决策树计划与最终指标/图表设计,按阶段交给 exp-batch 执行 |
| `exp-batch` | 执行一条有界的实验分支(单一 方法×数据×预算 或一条消融分支)：先确认分支未被剪枝,只问未决配置,跑前过一遍环境与资源预检(用本机平台的 smi 读活状态、显式指定可见设备、不用默认设备、看磁盘与遗留进程),按项目惯例运行,指标落到共享表格且形状直接可用于最终图表 |
| `exp-probe` | 一次性科研抽查:补一个缺失数据点、失败后重跑、单配置 sanity check、最小复现;至多一个聚焦问题,跑完一行汇报 |

自制·科研图件:

| Skill | 用途 |
|---|---|
| `editable-vector-slides` | 把好看的 SVG/PDF 科研图变成可编辑对象:SVG→矢量 PDF(保留真实文字)→原生可编辑 PPTX(路径/文字/渐变/阴影),不是截图贴幻灯片;含依赖安装、验收清单与已踩坑清单 |

## 依赖

- 6 个 Matt 的 skill:零依赖
- 3 个记忆 skill:配合 Magic Context、claude-mem 与 `docs/` StrictDoc 使用,缺少某一层时仍可利用其余层；初始化和文档校验需要 StrictDoc。项目可采用本仓库 [AGENTS.tail.md](AGENTS.tail.md) 中 `memory-system:start/end` 之间的引导块
- 3 个工作流 + 1 品味 skill:无硬依赖,品味内联
- `.sdoc` 校验需要 `strictdoc`:脚本末尾会检查 `uv`(缺则装,并处理 uv 自升级与清华 PyPI 镜像),并可选择用 `uv tool install strictdoc==0.28.1` 全局安装(升级:`uv tool upgrade strictdoc`)

## 一键脚本的首次部署(只需要网关地址 + API key)

`pi-setup.sh` / `opencode-setup.sh` / `codex-setup.sh` 启动后会**问一次**并自动填好各配置(只在“首次部署”时问：目标文件都不再含 `<YOUR_*>` 占位符就跳过)：

| 问什么 | 填到哪里 |
| --- | --- |
| OpenAI 兼容网关完整地址(如 `https://gw.example.com/v1`) | `pi/models.json`（`anthropic-messages` 的 provider 填根域、`openai-responses` 带 `/v1`）、`opencode.json` 各 provider 的 `baseURL`、`~/.claude-mem/settings.json`、`~/.config/cortexkit/magic-context.jsonc` 的 embedding `endpoint` |
| 该网关 API key(输入不回显) | 同上四处的 key 字段；写完后 `models.json` 与 claude-mem settings 会被 `chmod 600` |
| mcphub MCP host(可选，回车跳过) | `~/.agents/mcp.json`、`opencode.json` 的 `mcp.mcphub-web.url` |

- 非交互/无人值守不必手输：设 `PI_GATEWAY_BASE_URL` / `PI_GATEWAY_API_KEY` / `MCPHUB_HOST` 环境变量即可。
- 回车跳过则模板里的 `<YOUR_*>` 占位符保留，按脚本末尾清单手工填(先跳过、后补也行：再跑一次脚本，目标文件里还有占位符时会重新问)。
- 已有值永不被覆盖(见「更新」一节的隐私规则)；非 `/v1` 风格的网关(带自定义路径)建议填完后核对 `pi/models.json` 里 anthropic 渠道的根域与 claude-mem 的 BASE_URL。
- 仍需手工的只剩：`pi/auth.json` 的 coding-plan key(仅用 zai/kimi 这类内置 provider 时)、`~/.func`(由 dot_file 的 `linux-setup.sh` 部署)、notify 插件的 `NOTIFY_*` 环境变量(可选)。

## Codex 插件配置(best effort)

| 项目 | `codex-setup.sh` 的行为 |
|---|---|
| 前置条件 | 已装 Codex ≥0.128.0，支持 `codex plugin marketplace`；Python ≥3.11、curl、git。脚本不升级系统 Python 或 Codex |
| 依赖 | 缺失时询问安装 Node LTS、Bun、uv；可选用 uv 安装 strictdoc==0.28.1；已有 Node 需 ≥20 |
| claude-mem | 优先复用 `~/.claude/plugins/marketplaces/thedotmack` 的 runtime，注册 `claude-mem@claude-mem-local`(自带 MCP、skills、hooks)；缺失/过旧时询问运行官方 `--ide codex-cli` 安装器 |
| 共享记忆配置 | 已有 `~/.claude-mem/settings.json` 原样保留；官方安装器临时写入后也恢复，包括 provider/URL/key；首次创建 OpenAI 兼容记忆后端占位符，需手工填写 |
| Ponytail | 使用官方 `ponytail@ponytail` 插件；Node 必须在启动 Codex 的 PATH 中 |
| CodeGraph | 缺失时装 CLI，用 `codex mcp add` 注册；现有 `mcp_servers.codegraph` 原样保留；按项目执行 `codegraph init` |
| skills | 仅安装缺失的本仓库 skills，指定 `--agent codex`；已存在的共享 skills 不覆盖 |
| Magic Context / notify | 不安装；Codex 原生压缩保持原样；缺少 `ctx_*` 的记忆技能仅 best effort |
| 配置安全 | 先显示待添加项并确认，修改前备份；TOML 写入交给 Codex CLI，模型/认证配置不纳入管理；已安装/显式禁用项保留，重复运行不自动升级 |

- 使用 `${CODEX_HOME:-~/.codex}/config.toml`；**首次 claude-mem 官方安装器写死 `~/.codex`**，自定义 `CODEX_HOME` 时只复用已有 runtime，缺失则提示手工安装。`CLAUDE_CONFIG_DIR` / `CLAUDE_MEM_DATA_DIR` 可指定共享资产/记忆目录。
- 官方 claude-mem 安装器会更新共享资产、注册 Claude 插件并停止 worker，即使传 `--no-auto-start` 也不会避免停机；已有 runtime 的升级默认不执行。安装后填好记忆后端配置，再运行 `npx claude-mem@latest start`。
- 安装后在 Codex **`/hooks` 审阅并信任 hooks，再开新会话**；插件安装不等于 hooks 已信任。用 `/mcp` 确认服务连接并实际调用查询工具。
- 普通安装/新增条目默认 `[Y/n]`，共享 runtime 升级默认 `[y/N]`；无终端时按对应默认执行。失败会告警并返回非零，避免误报全部完成。

手工接入(claude-mem 首次安装同样有上述共享配置影响)：

```bash
npx claude-mem@latest install --ide codex-cli
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail
codex mcp add codegraph -- codegraph serve --mcp
npx skills@latest add brilliantrough/agent-skills --skill '*' --agent codex -g -y
```

更新已有安装时显式执行(不会在每次 setup 中自动更新)：

```bash
codex plugin marketplace upgrade ponytail
codex plugin add ponytail@ponytail
# claude-mem runtime 更新后,重新装入其本地插件快照:
codex plugin add claude-mem@claude-mem-local
npx skills@latest update -g
```

skills 是共享的，更新也会影响 OpenCode；claude-mem runtime 更新请按官方安装文档执行，先备份共享配置。

官方参考：[Codex MCP](https://developers.openai.com/codex/mcp) · [Codex hooks](https://developers.openai.com/codex/hooks) · [claude-mem 安装器](https://github.com/thedotmack/claude-mem/blob/main/src/services/integrations/CodexCliInstaller.ts) · [Ponytail](https://github.com/DietrichGebert/ponytail#codex) · [CodeGraph](https://github.com/colbymchenry/codegraph#quick-start)

## Pi 配置

[Pi](https://pi.dev) 核心刻意不带 MCP/subagent,能力全靠 npm 包与扩展;skills 原生读 `~/.agents/skills/`(零迁移)。`pi-setup.sh` 与 `opencode-setup.sh` **共享** `~/.claude-mem/settings.json` 与 `~/.config/cortexkit/magic-context.jsonc`(同一套字段级合并,两边幂等,不破坏本地值)。配置模板在 [dot_file/pi](https://github.com/brilliantrough/dot_file/tree/master/pi)。

> 开发本仓库时:脚本最后一步会把本机已装的 Pi 包软链进仓库 `node_modules/`(`.gitignore` 已排除),让编辑器/pi-lens 能解析 `@earendil-works/pi-*` 与 `node:*` 类型——否则这些模块会被报成 “Cannot find module”(运行时由 Pi 自己提供,不影响使用)。

| 项目 | `pi-setup.sh` 的行为 |
|---|---|
| Provider/模型 | 部署 `~/.pi/agent/models.json`:claude-newapi(anthropic)、codex-newapi(openai-responses)、anthropic-newapi;**anthropic 协议 `baseUrl` 填根域**(pi 自动补 `/v1/messages`,填 `/v1` 会 404),openai 协议带 `/v1`;`compat.supportsStore:false`、`thinkingLevelMap`(xhigh/max)对应 opencode 的 variants |
| 设置 | `~/.pi/agent/settings.json`:默认 provider/model/thinking、`defaultTools` 补 `grep/find/ls`(pi 默认只开 read/bash/edit/write)、`packages` 由 `pi install` 维护;不设置 Pi 的 `compaction` 开关——magic-context Pi 扩展在 `session_before_compact` 事件里自行 cancel 原生压缩(与官方 `setup --harness pi` 行为一致,官方只注册包 + 写共享 jsonc) |
| 运行默认值 | `modelThinkingLevels` 为 `codex-newapi/gpt-6-astra`、`codex-newapi/gpt-5.6-sol` 保存 `xhigh`,其余沿用全局 `high`;agent 级 `retry` 设置 `maxRetries:8`、`baseDelayMs:4000`,等待 4/8/16/32/64/128/256/512 秒(累计 17 分钟,加上首发最多 9 次请求),沿用原生指数退避、不额外开启 provider 内层重试 |
| 自动命名 | `pi-autoname@0.6.8` + `~/.pi/agent/pi-autoname.json`:用 `codex-newapi/gpt-5.6-sol` 在任务结束后生成会话名;周期重命名冷却 1440 分钟、尊重手工名称,可 `/autoname` 手动触发。会额外发送最近对话片段给命名模型;失败可尝试当前会话模型或回退文本提取,冷却不是请求配额。该版本配置路径固定为 `~/.pi/agent`,自定义 `PI_CODING_AGENT_DIR` 时脚本跳过此插件 |
| 任务耗时 | 本仓库包的 `pi/extensions/message-timing.ts`:从首个 `agent_start` 到 `agent_settled` 记录结束时间与秒数,包含工具/重试/排队后续消息;custom entry 持久保存、不进模型上下文、不高频刷新,仅 TUI 记录 |
| 凭据 | `~/.pi/agent/auth.json`(权限 600,coding plan 等 Pi 内置 provider 的 key):模板为 `zai-coding-cn`/`kimi-coding` 占位符;字段级合并,已填 key 不覆盖,仅初始化缺失文件。这类内置 provider(智谱 coding plan、Kimi For Coding、qwen/xiaomi token plan、opencode-go 等)不需要写 `models.json` |
| MCP | `~/.agents/mcp.json`(共享技能目录):mcphub-web(远程 URL)、codegraph、claude-mem;本地命令路径部署时替换为本机 `bun`/`codegraph` 绝对路径(pi-mcp-adapter 读取)。mcphub-web 配了 `directTools` 挂 5 个常用直连工具(tavily search/extract、firecrawl scrape/search/research_search_github,首次调用自动 lazyConnect),其余工具走 `mcp` 网关(`mcp({search/describe/connect})`,网关内调用名需带 `mcphub-web_` 前缀) |
| 插件 | `pi install npm:...`:pi-mcp-adapter、`@dietrichgebert/ponytail`(官方带 pi-extension)、`pi-subagents-j0k3r`、`pi-lens`(实时诊断/符号检索,注册 `lens_diagnostics`/`symbol_search` 等工具)、`@juicesharp/rpiv-ask-user-question`(结构化提问工具 `ask_user_question`——pi 核心无提问工具,plan-brief/grilling 类流程需要它)、`@cortexkit/pi-magic-context`、`pi-autoname@0.6.8`;**本仓库自身也是 Pi 包**(`pi install git:github.com/brilliantrough/agent-skills`,提供个性化 UI(`/ui`)、claude-mem 桥扩展、延迟 prompt 扩展(`/later`)、任务耗时扩展、one-dark 主题;旧版散装部署文件会被脚本清理。脚本在 `pi update --all` 之后会明确报出本插件的版本变化(`本仓库 Pi 插件已更新: <旧> -> <新>(N 个提交)` / `本次无更新`),不用猜有没有更新上) |
| context-mode fork | 上游 `context-mode` 与 `magic-context` **都注册 `ctx_search`** —— Pi 的同名工具检测会让启动直接 `process.exit(1)`;所以本仓库维护一份 fork(构建后把 11 个工具改名 `ctxm_*`,另做三项口径修正),**产物走 GitHub release**(编译产物不进 git 历史,源码/三层改动在 `context-mode/`)。`pi-setup.sh` 会 curl 最新 release 解到 `~/.pi/agent/vendor/context-mode` 再 `pi install`(内容没变就跳过;目标机不需要 bun、不需要 clone),并顺手摘掉旧的 clone 路径条目——两份同时登记会让 Pi 起不来。**不要装上游 `npm:context-mode`**,脚本检测到会提示卸载。开发机改完 fork:`bash context-mode/setup.sh --publish`。OpenCode 侧同名:`opencode-setup.sh` 会把 `opencode-context-mode-vendor.tar.gz` 解到 `~/.config/opencode/plugins/context-mode/` 再放一层 `entry.js` 入口(插件目录即装即用,不碰 `opencode.json` 的 `plugin` 字段),7 个 skill 进 `~/.config/opencode/skill/` |
| 主题 | 仓库 `pi/themes/onedark.json` 由上面的 **Pi 包**提供(One Dark,56 色 token;热重载),settings.json `theme: one-dark`。换主题:改 `theme` 或装主题包(如 `awesome-pi-themes` 65 款、`@inobit/pi-themes`);`/settings` 里可选所有已装主题 |
| claude-mem | 官方无 Pi 适配;**本仓库 Pi 包**内置自研桥扩展(镜像 opencode 插件契约:POST worker `/api/sessions/init\|observations\|summarize`,`platformSource:"pi"`;采集工具调用 + 助手消息 + **用户 prompt**,支持 `前缀*` 跳过),并提供 `claude_mem_search` 工具直连 worker(不依赖 MCP) |
| 个性化 UI | `pi/extensions/ui/index.ts`:基于纳管的 Atelier 0.10.1 布局/侧栏与 Zentui 0.24.0 编辑器/消息视觉，统一入口，不再安装两套 UI 包；含 LF 提交修复、TPS、HΣ/H₁、R/W 及现有 Magic Context `todowrite` 侧栏。配置 `agent-skills-ui.json` / `agent-skills-editor.json`，命令 `/ui`、`/ui sidebar`；[源码与许可证说明](pi/extensions/ui/README.md) |
| 个性化 UI 配置 | 仓库模板整文件覆盖 `~/.pi/agent/{agent-skills-ui.json,agent-skills-editor.json,keybindings.json}`(有差异先存 `.bak`,源文件是符号链接则跳过)；不再做一次性迁移。模板就是已验证的配置，包括 `sidebarPanelLayout`、侧栏自定义面板、`clearSelectionOnRelease` 默认、Enter 发送/Shift+Enter 换行按键。旧 UI 包(`pi-zentui`/`pi-atelier`/`atelier-bridge`)若还在 `packages` 里会被摘掉(先存 `.bak`)，避免两套 UI 同时加载。 |
| later | 本仓库 Pi 包的 `pi/extensions/later.ts`:`/later 5h <prompt>` 到点把该 prompt 作为用户消息注入 agent(`sendUserMessage` + `deliverAs:followUp`,空闲立即发、忙时排队等本轮结束),另有 `/later list`、`/later cancel <id/all>`;排程只活在当前 pi 进程内,退出/重启/切换会话即丢(挂机请用 tmux 保持 pi 常驻) |
| subagent | `~/.pi/agent/agents/{explore,general}.md`(对应 opencode 的 explore/general);frontmatter 的 `tools` **必须显式写**,默认值引用了不存在的工具 |
| magic-context 版本守卫 | opencode 插件缓存把版本钉死在下载时(重启不自动升级),与 Pi 扩展版本不一致时,共享的 `context.db` 会让新宿主 fail-closed 拒绝主回合;脚本检测到不一致时**默认不启用** Pi 版,并给出「清 `~/.cache/opencode/packages/@cortexkit/opencode-magic-context@latest` → 重启 opencode → 重跑本脚本」步骤 |
| uv/strictdoc | 同 opencode-setup.sh |

手工步骤(不用脚本时):`pi install npm:pi-mcp-adapter`、`npm:@dietrichgebert/ponytail`、`npm:pi-subagents-j0k3r`、`npm:pi-lens`、`npm:@juicesharp/rpiv-ask-user-question`、`npm:@cortexkit/pi-magic-context`、`npm:pi-autoname@0.6.8`、`git:github.com/brilliantrough/agent-skills`(逐个装;`pi remove <source>` 卸载、`pi list` 查看);可选:context-mode fork(Pi:`curl -fsSL https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz | tar -xz -C ~/.pi/agent/vendor/context-mode` 再 `pi install ~/.pi/agent/vendor/context-mode`;OpenCode:同样方式取 `opencode-context-mode-vendor.tar.gz` 解到 `~/.config/opencode/plugins/context-mode` 并 `cp` 包内 `entry.js` 到 `plugins/context-mode.js`);把 dot_file 的 `pi/{models,settings,mcp,auth,pi-autoname}.json`、`pi/agents/*.md` 放到对应位置,填好 `models.json` 的网关占位符与 `auth.json` 的 coding plan key(`pi auth check --provider <p>` 可验证)即可。

## OpenCode 插件配置（手工步骤）

一键命令见顶部；下面是不用脚本时的手工步骤。

### 1. claude-mem

```bash
npx claude-mem install --ide opencode
```

装完三件事:

**① wrapper 修复**(upstream bug [thedotmack/claude-mem#2854/#3328](https://github.com/thedotmack/claude-mem/issues/2854):bundle 导出非函数常量)。bundle 移到 `~/.config/opencode/lib/claude-mem.js`,并由 `opencode-setup.sh` 生成 `~/.config/opencode/plugins/claude-mem-wrapper.js`:

- 只 re-export 插件函数,绕过导出 bug;
- 补上游缺失的**用户 prompt 采集**:上游 `chat.message` 处理器只认 `assistant`,而 opencode 该钩子实际交付的是 `UserMessage`,所以用户输入从未被记录。wrapper 把每条用户输入经 `/api/sessions/init` 写入(与 Claude Code 同一通路:`user_prompts` + FTS + Chroma + observer 的 `<user_request>`),并统一 contentSessionId 使 init 与插件观测落进同一会话行;不产生额外模型请求。
- 支持**前缀通配**:`CLAUDE_MEM_SKIP_TOOLS` 里以 `*` 结尾的条目(如 `mcphub-web_*`、`ctx_*`)在 POST 前按前缀过滤(worker 本身只做精确匹配,故该语法只在这两个自研 shim 里生效);Pi 桥同样实现。
- 补上游缺失的**助手回复采集**:上游的 assistant 分支是死代码。wrapper 在 `experimental.text.complete` 暂存每回合最后一个文本,`session.idle` 时作为 1 条 `assistant_message` 观测发出——**每回合 1 次 observer 请求**,而不是每个模型 step 一次。

plugin 条目使用 `./plugins/claude-mem-wrapper.js`。升级 claude-mem 后重跑 `opencode-setup.sh` 重新生成。

**② MCP 工具组**(`claude_mem_search` 等查询工具,插件的 hook 不含工具)。`mcp-server.cjs` 必须用 bun 运行(依赖 `bun:sqlite`):

```jsonc
"mcp": {
  "claude-mem": {
    "type": "local",
    "command": ["<YOUR_BUN_PATH>", "<HOME>/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"],
    "enabled": true
  }
}
```

bun 安装:`curl -fsSL https://bun.sh/install | bash`。

**③ 配置文件** `~/.claude-mem/settings.json`:

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

`CLAUDE_MEM_PROVIDER=openrouter` 走的是 **OpenAI Chat Completions 协议**(`POST <BASE_URL>/chat/completions`,`Authorization: Bearer <key>`),不是 Anthropic 的 `/v1/messages` + `x-api-key`。所以 `..._API_KEY` 要填 **OpenAI 协议**的 key,`..._BASE_URL` 填 OpenAI 兼容网关地址(同一网关若两套协议 key 不同,用 OpenAI 那个)。

填完占位符后:

```bash
cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart
curl 127.0.0.1:37700/api/health     # 端口见 $SETTINGS 的 CLAUDE_MEM_WORKER_PORT
```

**worker 地址**：脚本会把本机默认值**显式写进** `~/.claude-mem/settings.json`——`CLAUDE_MEM_WORKER_HOST=127.0.0.1` + `CLAUDE_MEM_WORKER_PORT=37700 + uid%100`（claude-mem 自己的默认就是按 uid 偏移，目的正是**同一台服务器上不同用户不冲突**；显式写出来是为了可见、可查，取值不变）。**已存在的自定义 host/port 一律保留**（合并不覆盖）。解析优先级三处一致：环境变量 > `settings.json` > 默认公式（Pi 桥 `pi/extensions/claude-mem.ts`、OpenCode wrapper 生成的 `claude-mem-wrapper.js` 都按此）。脚本配完会打印一行 `claude-mem worker: http://127.0.0.1:37700(...)`，清单里的健康检查也用它取实际端口。 换端口时：改 `settings.json` 的 `CLAUDE_MEM_WORKER_PORT` → **重启 worker**（否则仍听旧端口）+ 重启宿主。各消费者都跟随这个键：MCP server（`~/.agents/mcp.json` 里 spawn 的 `mcp-server.cjs`，即 MCP 工具调用）与 Pi 桥直接读 `settings.json`；上游 OpenCode 插件只认 env + 内置默认公式（不读 `settings.json`），所以 wrapper 会在 import 它之前把 settings 的 host/port 写进 `process.env`，env 在每一处都优先于 settings。副作用：redis 队列前缀 `claude_mem_<port>` 会跟着变。

### 2. magic-context

plugin 条目 + 关闭 opencode 内置 compaction(magic-context 接管压缩,manual setup 要求):

```jsonc
"plugin": [
  "@cortexkit/opencode-magic-context@latest"
],
"compaction": { "auto": false, "prune": false }
```

配置文件 `~/.config/cortexkit/magic-context.jsonc`(`historian.opencode.model` 必填,缺失时 historian 失败并反复提示):

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

故障自检:`npx @cortexkit/magic-context@latest doctor`。

**右侧可视化侧边栏**(占比 / historian / compartment 状态)是独立的 TUI 插件,注册在 `~/.config/opencode/tui.jsonc`(opencode 同时加载 `tui.json` 与 `tui.jsonc`,后者优先):

```jsonc
{ "plugin": ["@cortexkit/opencode-magic-context@latest"] }
```

magic-context 只在自身安装向导 / `doctor` 时才写这个文件(设计上侧边栏是显式 opt-in);`opencode-setup.sh` 会自动补齐,只增不删——想关掉侧边栏就手动删掉该条目。

### 3. ponytail

```jsonc
"plugin": [
  "@dietrichgebert/ponytail"
]
```

### 4. notify

来自 [brilliantrough/opencode-notify-hub](https://github.com/brilliantrough/opencode-notify-hub)。下载 release 资产 `opencode-notify-plugin-*.zip`,解出 `session-notify.js` 放进 `~/.config/opencode/plugins/`(目录内插件自动加载,无需 config 条目)。

环境变量(启动 opencode 的 shell 配置里 export):

- `NOTIFY_GATEWAY_URL`、`NOTIFY_INGEST_KEY`:必填
- 可选:`NOTIFY_MACHINE`、`NOTIFY_HEARTBEAT_MS` 等,见仓库 `packages/plugin/src/config.ts`

### 5. codegraph(代码知识图谱 MCP)

来自 [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)。预索引代码知识图谱,查询一次取回符号源码与调用路径(含 grep 跟不上的动态分派跳转),索引随文件变更自动增量同步,100% 本地。

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

全局只配一次,每个项目各建一次索引(未 init 时 MCP 无内容可查):

```bash
cd your-project && codegraph init
```

### 6. later(延迟发送 prompt)

挂机等实验结果用:在**输入框里直接打**(不是 slash 命令)

```text
later 5h 查看当前实验的运行结果
```

回车后这句话**不会发给模型**,而是被排程;到点插件用 `session.promptAsync` 把它作为用户消息注入会话,等同你本人敲进输入框回车。`later list`、`later cancel 2`、`later cancel all` 管理排程。

- **零模型开销**:输入框拿到评测(`prompt ref`)后,TUI 层拦 Enter —— 命中关键字就自己排程、清空输入、`ctx.consume()`,不发任何请求
- **agent 忙也没事**:到点时用 `session.promptAsync` 排进会话,本轮 step 结束后立刻处理(实测:bash `sleep 25` 进行中注入,工具返回后同一回合回复)
- **边界**:计时器只活在当前 opencode 进程内,退出/重启即丢未触发的排程 —— 挂机请把 opencode 放 tmux 里
- **为什么是 TUI 插件**:server 插件(`plugins/*.js` 的 `chat.message` / `command.execute.before`)拦不住那一轮(清空 `parts` 也照样建 session 走模型,官方 issue #30268 同结论);TUI 插件才有 `command.register` / `keymap` / prompt ref
- **不能放 `plugins/`**:那目录只认 server 插件,签名不符会让 opencode 启动即崩;要放 `~/.config/opencode/tui-plugins/` 并在 `tui.jsonc` 里引用

```jsonc
{ "plugin": ["@cortexkit/opencode-magic-context@latest", "./tui-plugins/later"] }
```

`opencode-setup.sh` 第 5.3 步会部署插件并补上条目(只增不删)。

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
- `opencode-setup.sh` 第 5.4 步经确认后更新这三个 action，迁移旧发送绑定；有差异先显示并备份，其它按键、插件和凭据保留。重启 OpenCode 生效。
- Pi 的 `dot_file/pi/keybindings.json` 设置 `tui.input.submit: [enter]`、`tui.input.newLine: [shift+enter]`，保留自定义 `app.*`。`pi-setup.sh` 按模板部署；本机修改后 `/reload` 生效。旧 LF 提交兼容逻辑仅在 Ctrl+J 被绑定为 submit 时启用，此配置不触发。
- `later` 只拦普通 Enter，带修饰键的 Enter 不触发排程。
- 不修改 tmux、Konsole、VS Code 或 SSH 设置。Shift+Enter 依赖终端能传递不同于 Enter 的输入；若 Ctrl+Enter 被终端编码成普通 Enter/LF，应用无法识别原始物理按键，因此“不绑定”不等于所有终端都能保证按下无效果。

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

npm 形式条目在 opencode 重启时自动安装;配置改动重启 opencode 生效。

## 更新

```bash
npx skills add brilliantrough/agent-skills --all -g -y   # 刷新已装 + 装入仓库新增的 skill
npx skills update -g                                     # 刷新 lock 里登记的第三方源(mattpocock/drawio/find-skills)
```

- `add --all` 是幂等的:已登记的 skill 有变化才覆盖,仓库新增的 skill(如 `steady-do`)靠它落地。
- **`update -g` 不会安装新增 skill**:它只遍历 `~/.agents/.skill-lock.json` 里已登记的条目、按内容哈希逐个刷新,上游新增的至多打印一行 `To install: npx skills add …`。两个 setup 脚本已按 `add --all` → `update -g` 的顺序跑。
- 手工拷进 `~/.agents/skills/` 的副本不在 lock 里(`npx skills ls -g` 显示 `Source: local`),两个命令都不会碰,只能靠 `add` 纳入跟踪(add 会以仓库内容覆盖本地副本;服务器上的演化更新请先回流仓库)。

插件本体(不是配置)的更新方式:

| 插件 | 更新方式 |
|---|---|
| 本仓库 Pi 扩展/主题(git 包)、npm 类 Pi 包 | 脚本步骤 2 的 `pi update --all`(`pi-autoname@0.6.8` 这类钉版被 pi 跳过) |
| context-mode fork(Pi/opencode 两侧)、later、notify | 每次拉最新 release/raw 与已装内容比对:不一致才替换,原文件存 `.bak-YYYYmmddHHMMSS` |
| claude-mem wrapper | 脚本内生成,内容不同才询问替换 |
| opencode 侧 magic-context / ponytail | 脚本只保证配置条目存在,升级由 opencode 自己的包缓存决定 |

重跑 `opencode-setup.sh` / `pi-setup.sh` 是幂等的,配置文件按「字段级合并」更新,不覆盖本地敏感值:

| 文件 | 更新方式(non-destructive) |
|---|---|
| `~/.config/opencode/opencode.json` | 已存在的 provider 保留本地 `options`(apiKey/网关),只按模板覆盖 `models`;模板新增的 provider 整块加入;模板的非 provider 字段仅在本地缺该键时补入 |
| `~/.claude-mem/settings.json` | 模板的非敏感字段值优先下发;`CLAUDE_MEM_PROVIDER` 强制为 `openrouter`;`api key` / `base url` / `*_MODEL` 等敏感键与含 `<占位符>` 的值保留本地内容;本地独有键保留 |
| `~/.config/cortexkit/magic-context.jsonc` | 同 settings.json(含 `historian.pi` / `dreamer.pi` 块,与 opencode 共用) |
| `~/.pi/agent/{settings,models}.json`、`~/.agents/mcp.json` | 同 settings.json(pi-setup.sh);mcp.json 的本地命令路径在合并前按本机替换 |
| `~/.pi/agent/agents/*.md`、`extensions/claude-mem.ts` | 整文件部署:内容有差异才写,原文件存 `.bak-YYYYmmddHHMMSS` |

有改动时先把原文件存为时间戳 `.bak-YYYYmmddHHMMSS`;合并结果与本地一致则不写文件。magic-context 的合并会把 JSONC 规整为 JSON(注释丢失,原样保留在 `.bak` 里)。

**隐私内容永不覆盖**:键名命中 `SENSITIVE`(`api[_-]?key`/`secret`/`token`/`password`/`credential`/`bearer`/`auth`/`cookie`/`ingest`/`webhook`/`base[_-]?url`/`url`/`endpoint`/`host`/ 以 `key` 结尾)或模板值是 `<占位符>` 时,一律保留机器上已有的值;`opencode.json` 更是整块本地优先。三个整文件覆盖的模板(`agent-skills-ui.json`/`agent-skills-editor.json`/`keybindings.json`)不含隐私内容。回归检查:`python3 tests/merge-private-preservation.py`(selfcheck 会一并跑)。

## 单装某一个

```bash
npx skills add brilliantrough/agent-skills@tdd -g -y
```

## License

自研部分 MIT。`skills/{grilling,domain-modeling,tdd,diagnosing-bugs,code-review}` 来自 mattpocock/skills,归属见 [NOTICE](NOTICE.md)。
