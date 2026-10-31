# agent-skills

研究团队的 Agent 工作底座：共同质量底线、推荐流程与可复现配置，连接按需使用的专业能力。一条命令安装 skills、配置插件；宿主、模型、个人体验与专业组件允许选择。

## 定位与维护边界

| 内容 | 本套件负责 | 不代替 |
|---|---|---|
| 协作方法 | 任务范围、证据、交接、记忆使用与经验回流 | 各项目的科学选择与实际验收 |
| 环境与工具 | 自有插件、适配、推荐配置及安装保护 | 外部项目的核心开发和发布 |
| `kb-*`知识 | 带条件的经验、参考、反例；支持跨项目判断 | 完整领域能力或新场景的实测 |
| 独立领域项目 | 发现入口、适用条件、任务交接与缺失处理 | 接管正文、工具、案例与技术更正 |

统一的是协作与证据底线，不是所有人的整套环境。`base/research/accel/kb/ppt`继续表达安装选择与更新策略；当前默认配置是推荐组合，不等于每项个人偏好都是团队规范。

知识可以通过skill交付；独立与否取决于使用者、共同演化的内容和发布责任，不按深浅或文件数划线。成熟领域自行发展，主体引用；实际复用出现反复的检索/冲突/发布困难时再补设施，不预建通用知识平台。

| 宿主 | 定位 |
|---|---|
| OpenCode | 主目标 |
| Pi | 与 OpenCode 共享记忆配置 |
| DeepSeek Harness | 固定兼容组合；原生 DeepSeek 通道、TUI 与套件工具 |
| Codex | best effort；复用 skills 原文，不改工作流 |

**四宿主的 skills 与第三方依赖是同一份**：skill 实体、设计依赖、`ppt-master` 引擎、`nju-ppt` 的独立 venv、`agent-reach` CLI（`~/.local/bin`）都装在 `~/.agents/skills` 或 `~/.local` 下，四个宿主都能用。差异只在安装入口：

| 能力 | OpenCode | Pi | DSH | Codex |
|---|---|---|---|---|
| skills 基础组 + `research`/`accel`/`kb`/`ppt` 可选组 | ✓ | ✓ | ✓ | ✓ |
| `agent-reach` 只读检索 CLI（询问，默认 N） | ✓ | ✓ | ✓ | ✓ |
| 记忆规范块写进项目 `AGENTS.md` | ✓ | ✓ | — | — |

DSH 与 Codex 的入口只负责装 skills 与 CLI，不含配置合并；`AGENTS.md` 规范块在 DSH/Codex 里手工粘，或先跑一次 Pi/OpenCode 安装。

[快速安装](#快速安装) · [Skills](#skills本仓-37-个) · [首次部署](#首次部署只需要网关--5-个-key) · [Windows](#windowsgit-bash) · [Codex](#codex-插件配置best-effort) · [Pi](#pi-配置) · [DSH](dsh/README.md) · [OpenCode](#opencode-安装与迁移) · [更新](#更新) · [贡献](CONTRIBUTING.md)

## 快速安装

**Windows 首次使用**：先安装 [Git for Windows](https://git-scm.com/download/win)（自带 Git Bash；无需安装 `gh`）。若有 `winget`，也可以在 PowerShell 中运行：

```powershell
winget install --id Git.Git -e --source winget
```

安装完成后，从开始菜单打开 **Git Bash**，在其中运行下面的安装命令。配置完成后，若 `pi` 或 `opencode` 已在其他终端的 PATH 中，也可从 PowerShell、Windows Terminal 等终端直接启动；无需每次手动打开 Git Bash，但请保留 Git for Windows，供 Bash 命令与插件使用。

### 默认安装（`-y`，幂等）

OpenCode、Pi、Codex 使用下述统一凭据流程；DSH 的 Node 版本、凭据和安装选项见 [DSH 接入](dsh/README.md)。

**OpenCode**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)" -- -y
```

先安装 OpenCode **V2**；已有安装先退出 TUI 和后台服务。脚本先转换旧配置，再更新原生 V2 模板与插件；宿主升级在脚本里问一次（默认 Y，配置里自动更新默认关闭），不迁移会话库。默认同步 base skills；交互可选 research、accel、kb。只更新插件用 `--plugins-only`，预检用 `--check`，详见[安装与迁移](#opencode-安装与迁移)。

**Pi**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/pi-setup.sh)" -- -y
```

**DeepSeek Harness（Linux / macOS）**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/dsh-setup.sh)" -- -y
```

固定 dsh `0.2.1-rc.2`、TUI `0.5.3`、pi2dsh `0.27.1`，独立数据目录；保留旧 alpha。默认 `llm-deepseek` 发送原生会话亲和头；其它 provider/model 随模板同步。运行 `dsh tui`；工具、记忆与更新边界见 [DSH 接入](dsh/README.md)。

**只装 skills，不配插件**

```bash
bash -c "$(curl -fsSL --connect-timeout 8 -m 60 https://raw.githubusercontent.com/brilliantrough/agent-skills/main/skills-sync.sh)" -- base
```

`base` 安装基础 20 个；`base research` 追加 7 个算法研究 skill；`all` 或无参数安装五组共 37 个，含 PPT 组及其独立 Python 依赖。也可把 `research`、`accel`、`kb`、`ppt` 作为额外参数传给 `skills-sync.sh`。所有组都默认补装三个外部设计 skill，并更新已登记第三方；只有选中 `ppt` 才补装 `ppt-master` 并准备独立环境。需要 curl、git、Node/npx；安装位置 `~/.agents/skills/`，重开会话生效。

**Codex（best effort）**

```bash
bash -c "$(curl -fsSL --connect-timeout 8 -m 60 https://raw.githubusercontent.com/brilliantrough/agent-skills/main/codex-setup.sh)"
```

### `-y` 与逐项确认

以下 `-y` 说明适用于 OpenCode、Pi、Codex；DSH 缺少凭据时会停止，须先用环境变量提供或改用交互安装。

`-y` 取各项默认值，不再逐项确认：

| 默认值 | 行为 | 项目 |
|---|---|---|
| Y | 执行 | 装缺件、字段级合并配置（保留本地敏感值）、刷新 skills |
| N | 跳过 | research／accel／kb 可选组、notify 首装（仅 OpenCode v1）、升级 Pi 本体、升级 Magic Context、无代理继续、AGENTS.md 注入 |
| 凭据 | 仍询问 | 无终端则跳过，保留占位符；无人值守可用环境变量预填 |

等价写法：`--yes`、`ASSUME_YES=1`、`curl -fsSL <脚本 URL> | bash -s -- -y`。

**逐项确认：不传 `-y`。** 写前列出变更（含模型名 / `models`），可逐项拒绝。

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/pi-setup.sh)"
```

## Skills（本仓 37 个）

基础 20 个；算法研究 7 个；算力模板 7 个、公共知识 2 个与 PPT 1 个按需选装。`research`、`kb` 与 `ppt` 随仓库刷新，`accel` 缺才装；另有三个设计依赖来自上游仓库（装时装前询问，默认 Y），不复制到本仓。

### 工程技能

来自 [mattpocock/skills](https://github.com/mattpocock/skills)，MIT；归属见 [NOTICE](NOTICE.md)。

| Skill | 用途 |
|---|---|
| `grilling` | 计划/设计访谈，逐分支追问至有结论 |
| `domain-modeling` | 领域模型、术语表 |
| `tdd` | 红-绿-重构 |
| `diagnosing-bugs` | bug 诊断：先建反馈回路，再假设原因 |
| `code-review` | 双轴审查：规范符合度 + spec 忠实度 |
| `teach` | 工作区内交互式教学新技能/概念；任务书、术语表、学习记录，跨会话推进 |

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
| [`readable-docs`](skills/base/readable-docs/SKILL.md) | 面向人的技术文本：短语、分点、紧凑对比表；保留事实、条件与约束强度 |

- **范围**：README、设计、计划、报告、runbook、变更记录、记忆文档；不限目录
- **风格**：PPT 要点式扫读；单元格不塞长文，复杂因果留短段落；见[中文改写示例](skills/base/readable-docs/references/examples.md)
- **接入**：安装 skill，将 [AGENTS.tail.md](AGENTS.tail.md) 规范块合入项目 `AGENTS.md`；已有项目也需更新
- **边界**：不批量重写旧文档，不改模板、规范强度、代码或原始证据

### Skill 编写与知识沉淀（自制）

| Skill | 用途 |
|---|---|
| [`distill-project-kb`](skills/base/distill-project-kb/SKILL.md) | 从项目证据筛选可迁移内容；更新kb-*或交付独立领域库，复用已完成的领域选材与验收 |
| [`writing-skill`](skills/base/writing-skill/SKILL.md) | 通用 skill 编写与组织；项目经验成库先联动 `distill-project-kb`，不重复筛选确认 |

知识库可保留带条件的案例、阴性结果和一次昂贵踩坑；模型/硬件/版本是适用条件，个人路径、凭据和运行状态留在项目记录。使用后的补条件、反例和更正回到唯一维护源，不要求每次贡献都新建skill；历史快照与安装副本不独立演化。

### 任务工作流（自制）

手动指定优先；未指定时由 Agent 按任务意图选择。

| Skill | 适用任务 | 流程 |
|---|---|---|
| `goal-first` | 研究、开发和计划的主线约束 | 保持交付、当前未知、下一步和收口条件；不因意外发现静默扩展范围 |
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
| `personal-ui-taste` | 内容驱动的设计伙伴：主动推荐结构/叙事/交互，编排外部设计方法，以有范围的个人反馈校准 |

### 科研与算法性能（research 组）

研究方法按场景可选安装；`goal-first` 仍在 base，作为通用的主线约束。

| Skill | 适用场景 | 流程与边界 |
|---|---|---|
| `exp-discuss` | 研究问题尚未说清 | 证据优先分轮讨论；不设计矩阵、不运行 |
| `exp-workflow` | 代理、小数据集矩阵与整模评测之间的路线选择 | 协调问题、证据、PyTorch 就绪检查和整模验证；代理不是必经关卡 |
| `exp-campaign` | 探索、消融、交互、Pareto 或论文矩阵 | 按研究问题设计覆盖与阶段；不因矩阵大就机械剪枝 |
| `exp-batch` | 一条有界分支或已确定的矩阵阶段 | 整批预检环境/资源、代码就绪与成本；按项目惯例运行并落指标 |
| `exp-probe` | 补数据点、失败重跑、sanity check、最小复现 | 一次聚焦检查；负结果也记录，不把代理结果外推成整模结论 |
| `pytorch-perf-tuning` | PyTorch 评测慢、设备利用率低、显存浪费、批量预研 | 按证据处理同步、去重、batch、融合、多卡；正确且够用即收口 |
| `kernel-worker` | 有界算子任务的薄委派入口 | 真实负载、数值/计量契约、资源隔离与结果交接；专业能力按需引用独立kernel-knowledge |

### 公共知识（kb 组）

| Skill | 内容与边界 |
|---|---|
| [`kb-accel-sdk`](skills/kb/kb-accel-sdk/SKILL.md) | 跨平台 SDK、PyTorch 与推理框架生态速查；不代替本机安装与验证 |
| [`kb-8bit-quantization`](skills/kb/kb-8bit-quantization/SKILL.md) | 量化格式/轴、配方搜索、掉点诊断、实测与外部证据；附结果 CSV 和配方模板。伪量化与原生部署、研发集与独立验收分开，不承诺跨模型收益 |

`kb` 可选安装、持续刷新且不自动备份；已有未回流修改先备份。阅读知识无需加载模型，原实验复现另需对应模型、平台与未打包工件。

### 图件与出图（自制）

| Skill | 用途 |
|---|---|
| `editable-vector-slides` | SVG/PDF 科研图 → 可编辑矢量 PDF + 原生 PPTX；保留路径/文字/渐变/阴影，非截图；含依赖安装、验收与踩坑清单 |
| `image-gen` | `image_gen` 工具说明：文生图、参考图编辑、多张参考图、参数与默认值、返回与落盘、宿主差异、失败含义。只讲接口不规定风格 |

### 外部工具（官方包，setup 询问，默认 N）

| Skill | 用途 | 安装方式 |
|---|---|---|
| `agent-reach-install` | Agent Reach 官方 CLI 安装与用法（只读检索小红书/Reddit/X/B站等） | `pi-setup.sh` / `opencode-setup.sh` 在 skills 同步后询问（默认 N）；确认且缺 `agent-reach` 才调其 `scripts/install.sh` 装官方包，已装跳过，不动凭据与登录态 |

### 南京大学演示文稿（ppt 组，可选）

**当前为功能分支试装版：main尚未发布该组。** 素材提供者已确认可公开，确认范围与权利边界见 [素材说明](skills/ppt/nju-ppt/ASSETS-NOTICE.md)。main入口仅在合并后可用；合并前使用下方分支命令。

| Skill | 用途 |
| --- | --- |
| [`nju-ppt`](skills/ppt/nju-ppt/SKILL.md) | 银杏金＋清浅蓝固定模板；凝练文案，11页型，调用外部 `ppt-master` 生成原生可编辑图表、表格与备注 |

首次安装或更新时，运行**不带 `-y`** 的完整setup，在“南京大学模板、ppt-master”选项输入 `y`（默认N）：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh)"
```

同一入口既能首次选装，也能更新已安装的PPT组。输入N则本次不安装／更新该组，不卸载原有skill；带 `-y` 仍默认跳过PPT。主分支发布前，该线上命令尚不会出现新选项。

只安装／更新PPT、不改插件和模型配置：

```bash
bash skills-sync.sh ppt
```

- 同步器默认下载GitHub main，不读取本地工作树；分支验收可设 `AGENT_SKILLS_REF`，入口URL也须指向同一分支；Fork 验收另设 `AGENT_SKILLS_REPO=用户/agent-skills`
- 选中PPT即允许准备其外部skill与核心Python包；需要Python 3.10+，可用 `NJU_PPT_PYTHON` 指定单个解释器路径
- 独立环境位于 `~/.local/share/agent-skills/nju-ppt/venv`；不改系统Python，不安装Office／字体／系统代理
- 模板随 `nju-ppt` 打包，用完整外部root安装到本次项目，不修改 `ppt-master` 全局索引
- `ppt-master` 同名本地或不同源副本保留并告警；手动指定已确认引擎及缺件处理见 [运行环境](skills/ppt/nju-ppt/references/runtime.md)
- `.md/.txt`基础路径无需AI图像API密钥；DOCX/PDF/旁白等沿用上游按需依赖与许可
- 单独用其它skill管理器复制本包，不代表引擎、Python依赖已自动准备

功能分支试装（不改main，不安装／更新插件和模型配置；仅同步PPT组及公共外部skill依赖）：

```bash
AGENT_SKILLS_REF=feat/nju-ppt-optional bash -c "$(curl -fsSL --connect-timeout 8 -m 60 https://raw.githubusercontent.com/brilliantrough/agent-skills/feat/nju-ppt-optional/skills-sync.sh)" -- ppt
```

测试完整setup时，同样在命令前设置 `AGENT_SKILLS_REF=feat/nju-ppt-optional` 并将入口URL的 `main` 换成该分支；不带 `-y`，PPT组选Y。公开分支不限制学生身份，素材说明不代表校方背书。

从 Fork 试装时，把入口 URL 和 `AGENT_SKILLS_REPO` 都指向 Fork；同步器据此从同一 Fork 下载完整包：

```bash
AGENT_SKILLS_REPO=The2813509163/agent-skills AGENT_SKILLS_REF=feat/nju-ppt-optional bash -c "$(curl -fsSL https://raw.githubusercontent.com/The2813509163/agent-skills/feat/nju-ppt-optional/skills-sync.sh)" -- ppt
```

使用示例：

> 用南京大学模板，把这份Markdown做成PPT，面向初学者，15页。

固定视觉不再询问。内容确认按 `ppt-master` 和本用户授权处理；需要直接完成可明确说“无需大纲确认，直接生成”，不继承模板作者的授权。

| 平台／能力 | 新分发链验证状态 |
| --- | --- |
| Windows Git Bash＋Python | 隔离HOME的分支测试通过；main tarball和外部阶段用替身，未冒充真实线上安装 |
| 引擎及核心依赖 | 上游CLI真实下载 `ppt-master`、全新venv安装、包内模板契约与项目内安装通过 |
| Windows原生导出及PowerPoint | 11页型审阅通过（2图表＋1表格）；另用完整TXT新做15页成稿，2原生表格、15页备注，PowerPoint检查182个文本框无溢出 |
| 新用户自动触发 | 本轮在原会话显式加载仓库新包和隔离引擎；真正全新OpenCode用户会话尚未测，不将两者等同 |
| macOS / Linux / WSL | 未实测；字体、导出与预览分别验证 |
| WPS、实际投影 | 未测 |

## 依赖

| 类别 | 依赖 |
|---|---|
| 已提炼的工程 skill | 方法随本仓维护，无执行依赖 |
| 记忆 skill | Magic Context、claude-mem、`docs/` StrictDoc；缺一层仍可用其余层 |
| 工作流 / 技术写作 | 无硬依赖 |
| personal-ui-taste | 四个外部设计 skill；默认安装，按任务读取，缺失时说明降级 |
| research skill | PyTorch与实验执行方法；kernel-knowledge按需自行安装/阅读，Atrex等引擎仅在目标环境已就绪时使用 |
| nju-ppt（仅ppt组） | 外部 `hugohe3/ppt-master` 精确skill＋Python 3.10+独立venv；[核心依赖](skills/ppt/nju-ppt/requirements-core.txt)，不复制引擎 |

- `.sdoc` 校验需要 `strictdoc`：脚本末尾检查 `uv`，缺则安装；可选全局安装 `uv tool install strictdoc==0.28.1`，升级用 `uv tool upgrade strictdoc`
- 项目接入记忆系统：使用 [AGENTS.tail.md](AGENTS.tail.md) 中 `memory-system:start/end` 引导块

### 外部设计依赖

| 仓库 | 精确安装名 | 分工 |
|---|---|---|
| [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | `ui-ux-pro-max` | 页面结构、产品模式、UX、图表、动效与风格检索 |
| [alchaincyf/huashu-design](https://github.com/alchaincyf/huashu-design) | `huashu-design` | 高保真、构图/叙事、动画与视觉 QA |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | `design-taste-frontend` | 新页面视觉方法、已有页面改造审查（上游已合并 `redesign-existing-projects`） |

- **分发**：四个 setup → [skills-sync.sh](skills-sync.sh) → [skills-external.sh](skills-external.sh)。精确名字补缺，再由 `npx skills@latest update -g <第三方名字>` 更新；不使用整库 `--all`，不把本仓条目交给 npx。
- **归属**：本仓维护工作流、个人偏好与验证过的适配经验；外部维护完整目录、配方、脚本与资源。新增能力先考虑引用依赖，重复验证后再提炼差异，不逐版拷贝上游。
- **更新**：第三方副本由上游管理，直接修改可能被覆盖；个人改动回到本仓 skill。同名本地/其他源不自动接管，保留并告警。
- **使用**：安装后按任务读取实际入口/参考；安装 skill 不自动装浏览器/Python 包/GSAP，也不启用上游 hooks。分工和缺失处理见 [外部设计能力](skills/base/personal-ui-taste/references/external-skills.md)。

### 独立领域资源：kernel-knowledge

[kernel-knowledge](https://git.nju.edu.cn/iscl/kernel-knowledge)维护算子工程、硬件/DSL、profiling、计量工具、优化机制与条件化证据。仓库访问权限由该项目提供；不是本套件内置内容。

- **按需自行安装**：按其`INSTALL.md`使用`tools/install_skills.py`，或直接读`INDEX.md`与目标skill；不随setup补装，不登记为本套件代管更新项。
- **主体交接**：`pytorch-perf-tuning`选热点并接回整模，`kernel-worker`负责契约/隔离/预算/交付；专业规则在领域库维护。入口与降级见[领域库接入](skills/research/kernel-worker/references/kernel-knowledge.md)。
- **缺失不假装可用**：可继续使用项目已有可信实现和工具；依赖缺失的专业能力时说明阻塞，不自动搭平台。
- **回流到源**：写入前读取领域库`AGENTS.md`、`ADMISSION.md`与发布规范。安装副本先比较并回流，撤回/改名按上游处理；主体只更新交接方法与必要摘要。
- **不重复维护**：库内平台、案例和工具共同演化；`kb-accel-sdk`保留生态导航，`kb-8bit-quantization`保留量化判断，二者不复制领域库的专业实现。

只引用、可选集成、代装依赖是不同关系。当前`skills-external.sh`还会更新锁表中的符合条件第三方；不能仅凭“本套件未首装”推断不会代更新，独立领域资源遵循自己的安装通道。

## 首次部署：只需要网关 + 5 个 key

Pi、OpenCode、Codex 三个 setup 脚本统一收集、填入凭据；目标文件均无 `<YOUR_*>` 占位符则跳过。DSH 使用独立凭据引用，详见 [DSH 接入](dsh/README.md)。

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

前四个 key 写入 `opencode.json` / `pi/models.json`：

| 配置键 | 协议 / 模型 | 网关分组 |
|---|---|---|
| `claude-newapi.apiKey` | anthropic / claude | claude code |
| `codex-newapi.apiKey` | openai responses / gpt | codex |
| `anthropic-newapi.apiKey` | anthropic / 国产模型 | coding anthropic |
| `gemini-newapi.apiKey` | google-generative-ai / gemini | gemini |

| 其余输入 | 协议 / 分组 | 写入位置 |
|---|---|---|
| magic-context embedding key | openai / 嵌入模型 / 任意分组 | `magic-context.jsonc` → `embedding.api_key` |
| claude-mem key | openai chat completions / 任意模型 / 建议 coding openai 分组 | `~/.claude-mem/settings.json` → `CLAUDE_MEM_OPENROUTER_API_KEY` |
| mcphub MCP host | — | Pi `~/.pi/agent/mcp.json`、OpenCode `opencode.json` → web `url` |

同一模板的四处 `<YOUR_NEWAPI_API_KEY>` 按 provider 名就近替换，不串位。

### 无人值守与手工补填

| 环境变量 | 用途 |
|---|---|
| `PI_GATEWAY_BASE_URL` | 统一网关 |
| `PI_GATEWAY_API_KEY` | 未单独指定 key 的槽位兜底 |
| `PI_CLAUDE_NEWAPI_API_KEY` | claude-newapi |
| `PI_CODEX_NEWAPI_API_KEY` | codex-newapi |
| `PI_ANTHROPIC_NEWAPI_API_KEY` | anthropic-newapi |
| `PI_GEMINI_NEWAPI_API_KEY` | gemini-newapi |
| `PI_EMBEDDING_API_KEY` | embedding |
| `PI_CLAUDE_MEM_API_KEY` | claude-mem |
| `MCPHUB_HOST` | mcphub MCP host |

- 跳过的占位符：按脚本末尾“文件 / 缺失项”清单手工补，或重跑脚本
- 非 `/v1` 风格网关：填完核对 `pi/models.json` 的 anthropic 根域与 claude-mem 的 BASE_URL
- 仍需手工配置：
  - `pi/auth.json`：zai/kimi 等内置 provider 的 coding-plan key
  - `~/.func`：由 dot_file 的 `linux-setup.sh` 部署
  - `NOTIFY_*` 环境变量：仅安装 notify 时需要

> **凭据与 claude-mem 已有模型不覆盖，包括 `-y` 模式。** Magic Context 模型仍跟模板走；交互模式先列变更再确认。字段范围见[配置合并](#配置合并)。

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

- Pi >= 0.99.0 的 fullscreen 滚轮使用原生 `fullscreenWheelScrollLines: 3`（每次 3 行，Alt+滚轮 15 行）；可在 `/settings` 调整。regular 模式仍由终端控制，不打滚轮补丁。
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
| skills | 共用同步器刷新 base（漂移先备份），补装四个外部设计 skill、更新已登记第三方 |
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
bash -c "$(curl -fsSL --connect-timeout 8 -m 60 https://raw.githubusercontent.com/brilliantrough/agent-skills/main/skills-sync.sh)" -- base
```

插件更新命令（setup 不自动执行；skills 会自动同步）：

```bash
codex plugin marketplace upgrade ponytail
codex plugin add ponytail@ponytail
# claude-mem runtime 更新后,重新装入其本地插件快照:
codex plugin add claude-mem@claude-mem-local
```

skills 重跑套件同步器即可；共享目录的更新也影响 OpenCode。claude-mem runtime 按官方文档更新，先备份共享配置。

官方参考：[Codex MCP](https://developers.openai.com/codex/mcp) · [Codex hooks](https://developers.openai.com/codex/hooks) · [claude-mem 安装器](https://github.com/thedotmack/claude-mem/blob/main/src/services/integrations/CodexCliInstaller.ts) · [Ponytail](https://github.com/DietrichGebert/ponytail#codex) · [CodeGraph](https://github.com/colbymchenry/codegraph#quick-start)

## Pi 配置

[Pi](https://pi.dev) 原生读 `~/.agents/skills/`；MCP/subagent 靠 npm 包与扩展提供。模板见 [dot_file/pi](https://github.com/brilliantrough/dot_file/tree/master/pi)。

与 OpenCode 共享配置，均按字段合并、幂等、不破坏本地值：

- `~/.claude-mem/settings.json`
- `~/.config/cortexkit/magic-context.jsonc`

### 模型、设置与凭据

| 文件 | 内容 |
|---|---|
| `~/.pi/agent/models.json` | claude-newapi（anthropic）、codex-newapi（openai-responses）、anthropic-newapi（anthropic）、gemini-newapi（google-generative-ai） |
| `~/.pi/agent/settings.json` | 默认 provider/model/thinking；`defaultTools` 补 `grep/find/ls`（默认仅 read/bash/edit/write）；`packages` 由 `pi install` 维护 |
| `~/.pi/agent/auth.json` | 内置 coding-plan provider 的 key；权限 600；模板含 `zai-coding-cn` / `kimi-coding` 占位符 |

- **anthropic `baseUrl` 填根域**：Pi 自动补 `/v1/messages`，填 `/v1` 会 404；openai 带 `/v1`；gemini 带 `/v1beta`（`google-generative-ai` 的 baseUrl 必须自带版本段）
- 兼容项：`compat.supportsStore:false`、`thinkingLevelMap`（xhigh/max，对应 OpenCode variants）
- 不写 Pi `compaction` 开关：magic-context 在 `session_before_compact` cancel 原生压缩，与官方 `setup --harness pi` 一致
- `auth.json`：字段级合并，已填 key 不覆盖，仅初始化缺失文件
- 智谱 coding plan、Kimi For Coding、qwen/xiaomi token plan、opencode-go 等内置 provider 无需写 `models.json`

### 运行默认值

| 项目 | 默认值 |
|---|---|
| `modelThinkingLevels` | `codex-newapi/gpt-6-astra`、`codex-newapi/gpt-6.1-sol` 用 `xhigh`；其余全局 `high` |
| agent 级 `retry` | `maxRetries:8`、`baseDelayMs:4000`；原生指数退避，不开 provider 内层重试 |
| 退避间隔 | 4/8/16/32/64/128/256/512 秒，累计 17 分钟；含首发最多 9 次请求 |

**自动命名**

- `pi-autoname@0.6.8`；配置 `~/.pi/agent/pi-autoname.json`
- 任务结束后用 `codex-newapi/gpt-6.1-sol` 命名；冷却 1440 分钟，尊重手工名称；`/autoname` 手动触发
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
| Pi 内置 MCP（>= 0.99.0） | 不需安装 MCP 插件；旧 adapter 先确认迁移 |
| `@dietrichgebert/ponytail` | 官方自带 pi-extension |
| `pi-subagents-j0k3r` | subagent |
| `pi-lens` | 实时诊断、符号检索 |
| `pi-background-tasks@2.6.10` | 后台 shell、只读委派、Fusion；完成通知唤醒会话 |
| `@juicesharp/rpiv-ask-user-question` | `ask_user_question` 结构化提问；Pi 核心没有，plan-brief/grilling 需要 |
| `@cortexkit/pi-magic-context` | Magic Context |
| `pi-autoname@0.6.8` | 自动命名 |

**本仓库也是 Pi 包：** `pi install git:github.com/brilliantrough/agent-skills`。

- 提供个性化 UI（`/ui`）、pretty-tui 工具/思考折叠块与代码块复制、`/later`、任务耗时、`image_gen` 画图工具、one-dark 主题；claude-mem 由官方 Pi 扩展提供
- 自动清理旧散装文件
- 步骤 2 逐包更新后明确显示：`本仓库 Pi 插件已更新: <旧> -> <新>(N 个提交)`

主题：`pi/themes/onedark.json`（One Dark，56 色 token，支持热重载）；`settings.json` 中设 `theme: one-dark`。可修改 `theme`、在 `/settings` 中选择，或安装主题包：`awesome-pi-themes`（65 款）、`@inobit/pi-themes`。

### 画图 `image_gen`

把调研结论、对比、流程画成图。Pi、DSH（经 pi2dsh）、OpenCode v2 共用 `image-gen/core.mjs`，只有薄适配层不同。详见 [`image-gen/README.md`](image-gen/README.md)。

- 首次运行自动从 Pi 的 `models.json` 挑一个 OpenAI 协议 provider，写 `~/.local/share/agent-skills/image-gen.json`（`0600`）；填 `base_url`、`api_key`，可选 `model`／`output_dir`／`size`／`quality`
- `pi-setup.sh`／`opencode-setup.sh` 会把缺的字段补上（已有值保留）；拿不到 key 就不建文件——画图是**可选能力**，不阻塞安装，无人值守用 `PI_IMAGE_GEN_API_KEY`
- 工具接口、参数、返回与落盘、宿主差异、失败含义：`skills/base/image-gen`（base 组，随 skills 一起装；只说明能力，画什么与风格由调用方决定）
- 默认 `gpt-image-2.5-flare`；支持 `gpt-image-2.5-sunburst`、`gpt-image-2`、`gpt-image-1.5` 等网关已售模型
- 文生图走 `POST /v1/images/generations`；给参考图走 `POST /v1/images/edits`（multipart `image[]`）
- 图片存到项目 `images/`，同时作为图片内容返回模型；纯文本模型（如 `deepseek-flash`）不附图，只回路径并提示用户自己看
- OpenCode v2 需要 `session.image_preview`（Transcript images）打开才能在聊天里看到图，默认关

### MCP 与 subagent

Pi 原生 MCP（>= 0.99.0）：全局 `~/.pi/agent/mcp.json`，可信项目 `.pi/mcp.json`；自定义 agent 目录遵循 `PI_CODING_AGENT_DIR`。

| MCP | 连接方式 / 暴露 |
|---|---|
| web | 远程 URL；4 个常用工具 `direct`，其余 `deferred` |
| codegraph | 本地命令；`deferred`；部署时替换为本机绝对路径 |

- web 直连：tavily search/extract、firecrawl scrape/search；GitHub/开发检索用 `tool_search` 发现服务器当前提供的工具
- 工具名：Pi 以 `mcp__<服务器>__<工具>` 为基础，非字母/数字/下划线字符转下划线；超过 64 字符或归一化后重名时截短并加哈希。以当前工具表 / `tool_search` 返回名为准，不手拼、不把说明中的 `tavily_search` 等简称当调用别名；不要求跨宿主完全同名
- 示例：`tavily-mcp-tavily_search` → `mcp__web__tavily_mcp_tavily_search`；`firecrawl-mcp-firecrawl_scrape` → `mcp__web__firecrawl_mcp_firecrawl_scrape`
- `tool_search` 发现并加载工具，`codemode` 批量调用并归约结果；`toolExposure` 的键仍写服务器原始工具名，不写 Pi 包装后的名称
- `/mcp` 管理服务器、连接与登录；`pi mcp list` 检查连接；原生在会话启动时连接全部启用服务器，不再按首调 lazyConnect
- 旧机器：setup 先列迁移差异，默认 N；确认后备份、导入共享配置、摘除 adapter 登记并启用原生；拒绝或失败不合并新 MCP/settings 模板
- 单独迁移：`python3 pi/migrate-mcp.py` 预览，确认后加 `--apply`；旧 `~/.agents/mcp.json`、OAuth 文件和安装目录不改；已有同名原生服务器保留
- 脚本转换 `env`/`headers` 的旧变量与转义写法；不自动迁移其它 adapter 配置来源、SSE、未知字段、URL/命令路径变量或 OAuth 登录态，遇到这些条件停止并提示
- subagent 定义：`~/.pi/agent/agents/{explore,general}.md`，对应 OpenCode 的 explore/general
- frontmatter **必须显式写 `tools`**：默认值引用了不存在的工具

### MCP 名称的临时迁移

`mcphub-web` 已改名为 `web`。两个 setup 在合并模板前执行 `mcphub-web-rename`：保留旧条目的 URL、headers、启用状态及工具配置，改前存相邻 `.bak-web-*`；OpenCode 同时覆盖 v1 `mcp` 与 v2 `mcp.servers`，`--plugins-only` 也执行，`--check` 只预览。Pi 迁移原生 `mcp.json`，不改项目级配置或旧共享源。

两名并存时只合并无冲突字段、以实值补占位符；不同实值则保留原文件、WARN 并跳过对应模板合并。无旧名则不再写入。此为临时 deprecated，待维护者通知后删除，不自动到期。自定义权限或工具白名单中若写死旧名前缀，需自行更新。

### 个性化 UI

统一入口 `pi/extensions/ui/index.ts`，不再安装两套 UI 包；见[源码与许可证说明](pi/extensions/ui/README.md)。

| 部分 | 内容 |
|---|---|
| 布局 / 侧栏 | 纳管的 Atelier 0.16.0 |
| 编辑器 / 消息视觉 | Zentui 0.32.0 |
| 工具 / 思考分组 | Pretty TUI 0.3.0，clean 模式累计一轮的思考与工具调用 |
| 功能 | LF 提交修复、TPS、HΣ/H₁、R/W、Magic Context `todowrite` 侧栏 |
| 配置 | `agent-skills-ui.json`、`agent-skills-editor.json` |
| 命令 | `/ui`、`/ui sidebar` |

**配置部署**

- 整文件覆盖 `~/.pi/agent/{agent-skills-ui,agent-skills-editor,keybindings}.json`；有差异先存 `.bak`，符号链接跳过；不做一次性迁移
- 模板已验证：`sidebarPanelLayout`、侧栏自定义面板、`clearSelectionOnRelease` 默认、`tmuxMouseMotion` 默认开、Enter 发送 / Shift+Enter 换行
- 旧 `pi-zentui` / `pi-atelier` / `atelier-bridge` 从 `packages` 摘除，先存 `.bak`，避免两套 UI 同时加载

### 官方记忆扩展与版本守卫

**claude-mem 官方扩展**

官方安装器按宿主分别部署：

```bash
npx claude-mem install --ide pi --provider claude --no-auto-start
```

- runtime：`~/.claude/plugins/cache/thedotmack/claude-mem/<version>`
- Pi 入口：`~/.pi/agent/extensions/claude-mem/`
- OpenCode 入口：`$CFG/plugins/claude-mem.js`
- `pi-setup.sh` 与 `opencode-setup.sh` 都调用官方安装器更新 runtime 和对应宿主入口
- agent-skills 不再复制 bundle、代理 hooks 或维护 claude-mem wrapper
- Pi 默认只用官方原生 `mem_search`、`mem_timeline`、`mem_get_observations`，经 HTTP 连接共享 worker，不额外登记 claude-mem MCP
- 官方安装器会停止共享 worker；`--no-auto-start` 只禁止自动启动。更新后手工重启 worker；已有 settings 在安装后原样恢复
- 迁移期先备份再移除旧模板 MCP／旧 bridge；自定义 MCP 保留。需要额外 MCP 工具可自行登记

**magic-context 版本守卫**

OpenCode 的已下载包不会因重启就自动刷新；本地目录或固定版本登记也不会跟随 `latest`。与 Pi 版本不一致时，共享 `context.db` 可能触发版本守卫，拒绝主回合。

检测到不一致时，不继续强行启用或清理整个缓存：

1. 停止所有共用 Magic Context 的宿主，备份共享数据库及配置
2. 核对两端实际包路径、版本和配置登记方式，单独安排到兼容版本
3. 显式目录登记须更新指向；不能假定删一个 `@latest` 缓存就能升级
4. 确认版本一致后再重跑 setup、启动宿主

OpenCode setup 单独询问是否刷新 Magic Context，默认 N；v2 兼容基线至少 **0.45**，旧版或版本不明只警告，不再阻塞整套部署。确认刷新才备份移走其 latest 缓存、改回官方包登记；下次宿主启动下载。升级窗口见[更新](#更新)。

### context-mode fork

**不要装上游 `npm:context-mode`。** 它与 magic-context 都注册 `ctx_search`，Pi 会因同名工具 `process.exit(1)`；脚本检测到会提示卸载。

本仓库 fork：

- 构建后将 11 个工具改名为 `ctxm_*`，另做三项口径修正
- 产物走 GitHub release，不进 git 历史
- 目标机无需 bun / clone；开发机发布：`bash context-mode/setup.sh --publish`

| 宿主 | 部署方式 |
|---|---|
| Pi | curl 最新 release → 解到 `~/.pi/agent/vendor/context-mode` → `pi install`；内容未变则跳过 |
| OpenCode v1 | `opencode-context-mode-vendor.tar.gz` → `~/.config/opencode/plugins/context-mode/`；再放一层 `entry.js` 入口 |
| OpenCode v2 | 同一 context-mode 资产 → `~/.config/opencode/vendor/context-mode/`；由 v2 适配包加载 |

- Pi：摘除旧 clone 路径条目；同时登记两份会无法启动
- OpenCode：context-mode 不单独登记为配置插件；配套 skill 装到 `~/.config/opencode/skill/`

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

1. 对照[插件清单](#插件与主题)，用 `pi install npm:<包名>` 逐个安装八个 npm 包，再用 `pi install git:github.com/brilliantrough/agent-skills` 安装本仓库包
2. 可选安装 context-mode fork：
   - Pi：`curl -fsSL https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz | tar -xz -C ~/.pi/agent/vendor/context-mode`，再 `pi install ~/.pi/agent/vendor/context-mode`
   - OpenCode v1：取 `opencode-context-mode-vendor.tar.gz` 解到 `~/.config/opencode/plugins/context-mode`，将包内 `entry.js` 用 `cp` 复制到 `plugins/context-mode.js`
3. 将 dot_file 的 `pi/{models,settings,mcp,auth,pi-autoname}.json`、`pi/agents/*.md` 放到对应位置
4. 填好 `models.json` 网关占位符、`auth.json` coding plan key；用 `pi auth check --provider <p>` 验证

管理包：`pi remove <source>` 卸载，`pi list` 查看。uv/strictdoc 处理同 `opencode-setup.sh`。

PS：开发时，脚本最后将本机 Pi 包软链到仓库 `node_modules/`（`.gitignore` 已排除），供编辑器/pi-lens 解析 `@earendil-works/pi-*`、`node:*` 类型。缺软链会报 `Cannot find module`，但运行时由 Pi 提供，不影响使用。

## OpenCode 安装与迁移

先安装 OpenCode V2，已有服务先退出。setup **只维护 V2**，检测到 V1 时停止并提示升级；配置先转换为原生 V2，再按原逻辑在线拉取模板与更新模型。

```bash
curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh -o /tmp/opencode-setup.sh
bash /tmp/opencode-setup.sh --check
bash /tmp/opencode-setup.sh --plugins-only
# 新机器安装完整套装：bash /tmp/opencode-setup.sh
```

| 模式 | 处理范围 |
| --- | --- |
| 默认完整安装 | 插件、配置、依赖与通用 skills；默认 base 20 个，交互可选 research、accel、kb、ppt，全部选中时为 37 个，另同步外部设计 skills；选 ppt 另补引擎与独立 Python 环境 |
| `--plugins-only` | 旧配置转原生 V2、自维护插件、context-mode 及其 skills、官方包登记、claude-mem runtime／入口／MCP；不更新模型／Python／通用 skills |
| `--check` | 下载校验自维护包，检查配置，查询 Ponytail／Magic Context 本地与 npm 版本；不询问、不改配置、认证或数据库 |

`--check` 与 `--plugins-only` 要求已有 Python 3、curl、Bun；`--check` 仅预览转换，仍会联网，宿主 `--version` 也可能写日志，并非零文件系统写入。

| 客户端 | 包与入口 | 配置 |
| --- | --- | --- |
| v2 | `opencode-plugins-v2.tar.gz` → `v2/`，含 server 与 TUI 入口 | `plugins`、`cli.json` |

- **旧插件迁移**：旧散装入口和旧 v1 包统一纳管；v1→v2 后移入 `$CFG/.agent-skills-backups/<时间戳>/`，不留在自动扫描目录。无需手工删除；相同内容不重写，不自动降级回 v1。
- **保留范围**：私密值、provider 本地设置、未知第三方配置、认证、会话库和外置正文。转换复用官方 2.2.3 归一化器，在本机执行；改前备份，冲突停止，无变化不写入。
- Ponytail：官方包由宿主加载；宿主会自动安装缺失包，但不会替换已有缓存。setup 维护时查询本地版本与 npm `latest`，有新版默认询问刷新；确认后只刷新该官方包，不调用宿主 plugin CLI。
- **Magic Context**：独立询问刷新，默认 N；确认后备份移走 latest 缓存、登记官方 `@latest`。选 N 保留现状并继续，兼容性 WARN 不等于可用。
- **context-mode**：独立 release，部署到 `vendor/context-mode/`。notify 旧入口备份停用。
- **验证范围**：Linux v1 1.18.35／v2 2.0.26；旧入口迁移、重复运行、两端发现全部 27 个本仓 skills 与 Ponytail 空缓存自动安装已通过。Windows 实机未覆盖；不是所有历史版本的兼容承诺。

### 宿主升级顺序

1. 退出旧 TUI 和后台服务，备份配置、认证、state 及一致的会话数据库
2. 升级 OpenCode 二进制，再运行 setup 的 `--check`／`--plugins-only`
3. 启动新版，由 **OpenCode 自己迁移会话库和 CLI 配置**；setup 不代管数据库迁移

Magic Context 的共享 `context.db` 是另一套库，升级另选所有宿主停用的窗口。v1/v2 并行须隔离配置、数据、state、cache；回退不能只换旧二进制，也不能把插件备份当作数据库备份。

管理路径、停止条件与构建发布见 [OpenCode 分发说明](opencode/README.md)；工具用法见 [近期纠错与大输出外置](context-rewrite/README.md)。

### 手工配置参考

配置使用原生 **V2**；目录包与配置见 [v2 说明](opencode/v2/README.md)。使用 setup 后不要再重复登记官方 claude-mem、later 或 context_rewrite 入口。

### 1. claude-mem

```bash
npx claude-mem install --ide opencode
```

官方安装器生成 `$HOME/.config/opencode/plugins/claude-mem.js`。当前 bundle 自带 OpenCode v1 `server` 与 v2 `setup` 入口，由 OpenCode 自己发现和加载；agent-skills 不再代理 claude-mem，也不再维护本地 wrapper。

- setup 完整安装与 `--plugins-only` 均询问运行官方最新版安装器，配置合并完成后直接更新真实配置目录；改前备份
- v1/v2 均使用同一份官方双入口文件；MCP 登记也由官方安装器写入
- 已有共享 settings 原样恢复；自定义／禁用的 claude-mem MCP 不接管，告警并跳过此次官方更新
- 若插件加载失败，先检查官方 bundle 与宿主版本，不要把 claude-mem 的工具再登记到 agent-skills 入口

#### ① MCP 查询工具

官方 13.35.0 安装器为 OpenCode 登记 `mcp.claude-mem`，命令是 `[Node绝对路径, mcp-server.cjs绝对路径]`；setup 不另写命令。原生 `claude_mem_search` 是简化搜索，MCP 提供更多查询／保存能力，两者均为官方设计。

setup 先移除受管同名 MCP 项，交官方安装器刷新，再统一转换为 `mcp.servers.claude-mem`；旧 Bun 条目交安装器更新为 Node。自定义命令、环境变量或禁用项保留并提示。旧 wrapper／lib 文件移到备份，不再运行。

#### ② settings 与 worker

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

- Pi 桥按上述优先级；官方 OpenCode bundle 由自身读取配置
- 换端口：改 `CLAUDE_MEM_WORKER_PORT` → **重启 worker + 宿主**；否则 worker 仍监听旧端口
- 所有消费者跟随该键；redis 队列前缀 `claude_mem_<port>` 也随之改变

### 2. magic-context

添加 plugin，关闭 OpenCode 内置 compaction，由 magic-context 接管（manual setup 要求）：

```jsonc
"plugins": [
  "@cortexkit/opencode-magic-context@latest"
],
"compaction": { "auto": false }
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

故障自检前先核对已装版本；会升级插件或迁移共享库的 doctor 操作，只在维护窗口执行，不直接拉 `@latest` 排障。

V2 从已登记包发现 TUI 入口；界面配置使用 `cli.json`，无需在旧 `tui.json(c)` 重复登记。

### 3. ponytail

官方包的 V2 登记示例：

```jsonc
"plugins": [
  "@dietrichgebert/ponytail"
]
```

宿主启动时自动下载缺失包；不要再登记 `v2/ponytail/`、`options.ponytailPackage` 或旧内置 skills 路径，setup 会清理这批旧配置。

### 4. notify（待适配 V2）

来源：[brilliantrough/opencode-notify-hub](https://github.com/brilliantrough/opencode-notify-hub)。

当前 setup 将旧入口备份停用；V2 支持由 notify 项目单独维护。

### 5. codegraph（代码知识图谱 MCP）

来源：[colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)。

- 预索引代码知识图谱，查询一次取回符号源码与调用路径，含 grep 难以跟踪的动态分派
- 随文件变更自动增量同步，100% 本地

```bash
curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh   # CLI 装到 ~/.local/bin
```

```jsonc
"mcp": {
  "servers": {
    "codegraph": {
      "type": "local",
      "command": ["codegraph", "serve", "--mcp"],
      "disabled": false
    }
  }
}
```

全局配一次，各项目各建一次索引；未 init 时 MCP 无内容可查。

```bash
cd your-project && codegraph init
```

### 6. later（延迟发送 prompt）

挂机等实验结果，可**直接在输入框输入**，也支持带参数的 `/later`：

```text
later 5h 查看当前实验的运行结果
```

| 输入 | 行为 |
|---|---|
| `later 5h <prompt>` | 回车只排程，不发给模型；到点以用户消息注入 |
| `later list` | 查看排程 |
| `later cancel 2` | 取消第 2 条 |
| `later cancel all` | 取消全部 |

- **排程时不调模型**：TUI 拦截输入并清空；到点向目标会话提交用户消息
- **两类计时器互相独立**：输入框排程由 TUI 管理；Agent 调用 `later` 工具的排程由服务端管理，各自查询和取消
- **仅进程内有效**：对应进程退出／重启后丢失未触发排程；v2 关 TUI 不一定停止后台服务

输入框拦截必须走 TUI API；不能把 v1 server 的 `chat.message` 当成“不发模型”的拦截器。

| 版本 | TUI 入口 | 登记方式 |
| --- | --- | --- |
| v2 | `v2/tui.js` → `later-cli.js` | 随 `v2/` 目录包发现，不另登记旧 TUI 插件 |

setup 负责部署、去重和旧入口迁移；不要同时安装整包与旧独立 later。

### 7. 按键（Enter 发送 / Shift+Enter 换行）

v2 的 `cli.json` 使用点分 action 名：

```jsonc
"keybinds": {
  "input.submit": "return",
  "input.newline": "shift+return",
  "prompt.submit": "none"
}
```

| 宿主 | 配置与生效方式 |
|---|---|
| OpenCode V2 | 完整 setup 确认后设置对应三个 action；先显示差异并备份，保留其它按键；`--plugins-only` 不统一按键。没有 `cli.json` 时先准备 `tui.json`，首启由宿主迁移 |
| Pi | `dot_file/pi/keybindings.json`：`tui.input.submit: [enter]`、`tui.input.newLine: [shift+enter]`，保留自定义 `app.*`；脚本按模板部署，本机修改后 `/reload` 生效 |

- Enter 发送，Shift+Enter 换行；不绑定 Ctrl+Enter，不再把 Ctrl+J 设为发送
- Pi 旧 LF 提交兼容逻辑仅在 Ctrl+J 绑定为 submit 时启用，此配置不触发
- `later` 只拦普通 Enter，修饰键 + Enter 不触发排程
- 不修改 tmux、Konsole、VS Code 或 SSH 设置

**终端边界：** Shift+Enter 需要终端传递不同于 Enter 的输入。若 Ctrl+Enter 被编码成普通 Enter/LF，应用无法还原物理按键；“不绑定”不保证所有终端按下都无效果。

### 8. 近期纠错与大输出外置

V2 预构建包已包含，不另装独立入口：

- `context_rewrite(ids, note)`：撤下近期无用调用及结果，仅改变模型发送视图；原始历史与命令副作用保留
- 自动外置：普通文本默认 ≥16 KiB，留下预览、状态和持久文件指针
- `context_output_read`：分页或 `full=true` 取回原文；显式全文不再次外置
- Magic Context 仍主管长期历史与记忆；编号独立，不使用它的 tag

完整参数、存储目录与宿主边界见 [上下文插件说明](context-rewrite/README.md)。

## OpenCode V2 最小配置参考

下面展示原生 V2 主配置；自维护插件目录由 setup 登记，详见[目录包配置](opencode/v2/README.md)。

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    "@cortexkit/opencode-magic-context@latest",
    "@dietrichgebert/ponytail"
  ],
  "compaction": { "auto": false },
  "mcp": {
    "servers": {
      "codegraph": {
        "type": "local",
        "command": ["codegraph", "serve", "--mcp"],
        "disabled": false
      }
    }
  }
}
```

npm 缺失包在 OpenCode 启动时自动安装；已有包不会因重启自动替换。重跑 setup 时，Ponytail 查询本地版本与 npm `latest`，有新版默认询问刷新；Magic Context 单独默认 N。不能直接复制示例覆盖现有配置；也不要额外登记旧 wrapper。

## 更新

### Skills

本仓库 skill 由四个 setup 脚本调用的 `skills-sync.sh`（仓库根）分组同步，**重跑完整 setup 刷新所选组**；OpenCode 的 `--plugins-only` 不更新通用 skills。始终从 GitHub 拉取 `main` tarball 安装；分组即仓库 `skills/{base,research,accel,kb}/` 目录，新增 skill 放入对应组目录即可，无名单维护：

| 组 | 策略 |
|---|---|
| base（品味/流程，20） | 每次随仓库刷新；本地有未回流改动先整目录备份到 `~/.local/share/agent-skills/.backups/` 再覆盖（回流后删备份） |
| research（算法研究，7） | 每次随仓库刷新；本地有未回流改动先按组备份再覆盖 |
| accel（算力平台模板，7） | 缺才装；本机特化后永不覆盖 |
| kb（公共知识，2） | 每次随仓库刷新，不备份 |
| ppt（南京大学PPT，1） | 默认不选；选中后刷新并先备份漂移，再补齐引擎和独立Python环境 |

客户端不分组：实体直落 `~/.agents/skills/<名>`，装了 Claude Code 的机器同步 `~/.claude/skills/<名>`（有差异才写）。选组只决定本次安装／更新；不选不会卸载已安装的 skill。

第三方由共用同步器末尾的 `skills-external.sh` 处理：先询问是否安装三个设计依赖（默认Y；`--uninstall` 清理，`SKILLS_EXTERNAL=skip` 跳过设计依赖），选中ppt仍补装 `hugohe3/ppt-master`，再按锁表更新已登记第三方。同时排除本仓来源、已合并的 `redesign-existing-projects` 与 `skills/{base,research,accel,kb,ppt}` 下的名字，避免本仓skill误交给npx更新。

```bash
bash skills-external.sh   # 在克隆的套件根单独补装/更新第三方，不动本仓 skill 或插件配置
bash skills-external.sh --ppt  # 另补缺ppt-master；不代替ppt组和独立Python环境准备
```

`npx skills update` 本身只更新已登记项，不补装缺项或上游新增 skill；依赖补装仍需精确的 `add --skill`。

- 冲突逐个处理，不因一个 Taste 入口冲突而跳过另一个；Claude 同名副本与共享目录不同时，保留并告警，不自动替换
- 补装失败、检测到冲突或 CLI 返回失败时，同步器返回非零
- 上游边界（skills@1.7.1）：部分网络检查失败会打印错误却仍退出 0；查看原始输出后重跑，退出 0 不等于已确认全部最新。套件不另造更新引擎

- 手工拷贝的副本不在 lock 中，`npx skills ls -g` 显示 `Source: local`，update 不碰
- 本仓库 skill 不再走 `npx skills add`：它无条件覆盖且无分组策略

### 插件本体（不含配置）

| 插件 | 更新方式 |
|---|---|
| Pi 本体与已装包，magic-context 除外 | 步骤 2，默认 Y；逐包 `pi update <spec> --no-approve`，不用 `--all` |
| 本仓库 Pi git 包 / npm 包 | 同步骤 2，含 UI/later/耗时/主题；`pi-autoname@0.6.8` 钉版，Pi 会跳过 |
| magic-context（Pi） | 步骤 3.1 独立询问，默认 N |
| Magic Context（OpenCode） | 独立询问、默认 N；确认后备份移走其 latest 缓存并登记 `@latest`，下次宿主启动下载；Pi 包另行同步 |
| OpenCode 自维护包（later、context_rewrite） | setup 的固定版本 V2 release；插件备份放 `$CFG/.agent-skills-backups/`；claude-mem runtime 与宿主入口由官方安装器维护 |
| context-mode fork | 两侧从独立 latest release 同步；OpenCode 目录备份放 `.agent-skills-backups/`，Pi 保持自身备份策略 |
| notify | 旧入口备份停用 |
| OpenCode 官方 Ponytail | 宿主负责缺包安装；setup 维护时查询版本，有新版默认询问刷新；确认后备份对应缓存并登记 `@latest`，不调用宿主 plugin CLI |

**Magic Context 升级单独确认。** 先停所有共用 `context.db` 的宿主并备份；Pi 不用 `--all`，OpenCode setup 提供默认 N 的独立刷新询问。选 Y 只备份移走它在 OpenCode 中的 latest 缓存、改回官方 npm 登记；不启动宿主、不访问数据库。选 N 保留现状，不阻塞其他插件；兼容性 WARN 须在启动前处理。

### 配置合并

重跑 `opencode-setup.sh` / `pi-setup.sh` 幂等，按字段合并、不覆盖本地敏感值。

**共同规则**

- 有变更先备份，无变更不写；OpenCode 插件目录用 `.agent-skills-backups/`，配置沿用相邻 `.bak*` 备份
- 非敏感字段跟模板；本地独有键保留
- 敏感键、本机已有值对应的模板 `<占位符>`：保留本地值
- magic-context 合并后由 JSONC 规整为 JSON；注释保留在 `.bak`，不在新文件中

| 文件 | 更新策略 / 特例 |
|---|---|
| `~/.config/opencode/opencode.json` | 先备份并转换旧字段，再在线获取 V2 模板；完整 setup 刷新 `providers.<名称>.models`，保留已有 provider 的 `settings`、headers 等本地字段。插件模式仅转换格式与规范登记；路径遵循 `OPENCODE_CONFIG_DIR`／XDG |
| `~/.claude-mem/settings.json` | `CLAUDE_MEM_*_MODEL` 随模板统一为 `mem-1`；API key、Base URL、port／host 保留，缺失键按模板补齐；`CLAUDE_MEM_PROVIDER` 仍强制 `openrouter` |
| `~/.config/cortexkit/magic-context.jsonc` | 模型及其他非敏感字段仍随模板；historian／dreamer 的 OpenCode、Pi 默认模型为 `codex-newapi/gpt-6-luna`，embedding 不变 |
| `~/.pi/agent/{settings,models,mcp}.json` | 非敏感字段随模板，由 `pi-setup.sh` 处理；已有 `tuiMode` 保留本地选择；mcp.json 本地命令路径在合并前替换；旧共享 MCP 只读迁移，不再部署 |
| `~/.pi/agent/agents/*.md` | 整文件部署；有差异才写，原文件留时间戳备份 |

**隐私保护边界**

- 键名命中 `SENSITIVE`，或模板值为 `<占位符>`：机器上已有值永不覆盖
- `SENSITIVE`：`api[_-]?key` / `secret` / `token` / `password` / `credential` / `bearer` / `auth` / `cookie` / `ingest` / `webhook` / `base[_-]?url` / `url` / `endpoint` / `host` / 以 `key` 结尾
- OpenCode 配置的本地值优先；插件登记按主版本规范化、退役旧入口，provider 模型按上表单独更新
- 模型字段中，`CLAUDE_MEM_*_MODEL` 随模板统一为 `mem-1`；API key、Base URL、port／host 保留。Magic Context 的 model 仍由脚本接管但本轮不改值。
- 整文件覆盖的 `agent-skills-ui.json` / `agent-skills-editor.json` / `keybindings.json` 不含隐私内容

回归检查：`python3 tests/merge-private-preservation.py`；selfcheck 也会运行。

## 单装某一个

```bash
npx skills add brilliantrough/agent-skills@tdd -g -y
```

适合临时试用；注意下次重跑 setup 时本仓库 skill 会按 skills-sync.sh 的分组策略接管（base/kb 与仓库对齐，本地改动备份到 `.backups`）。

## License

自研部分 MIT。`skills/{grilling,domain-modeling,tdd,diagnosing-bugs,code-review}` 来自 mattpocock/skills，归属见 [NOTICE](NOTICE.md)。
