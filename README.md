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

## Skills(12 个)

来自 [mattpocock/skills](https://github.com/mattpocock/skills)(MIT,见 [NOTICE](NOTICE.md)):

| Skill | 用途 |
|---|---|
| `grilling` | 对计划/设计做穷追不舍的访谈,直到每个分支都有结论 |
| `grill-with-docs` | grilling + 同步沉淀 `CONTEXT.md` 和 ADR |
| `domain-modeling` | 领域模型、术语表 |
| `tdd` | 红-绿-重构的测试驱动开发 |
| `diagnosing-bugs` | bug 诊断回路:先建反馈回路,再假设原因 |
| `code-review` | 双轴审查:规范符合度 + spec 忠实度 |

自制·三层记忆系统:

| Skill | 用途 |
|---|---|
| `load-mem` | 会话启动时加载全部记忆层(注入记忆 / StrictDoc / claude-mem) |
| `save-mem` | 里程碑时持久化记忆(`ctx_memory` 存事实,StrictDoc 存叙事) |
| `migrate-mem` | 旧记忆文件迁入三层记忆系统 |

自制·任务工作流(在需求后手动 cue 触发):

| Skill | 用途 |
|---|---|
| `plan-brief` | 复杂需求 → 盘问细节 → 计划文档 `docs/plans/<slug>.md` + 启动 prompt → 新会话执行 → 开发报告 `<slug>.report.md` → 审查 `<slug>.review.md`。验证模式:TDD(快反馈代码)/ smoke-and-read(科研长任务) |
| `quick-do` | 简单任务当前会话直接完成:不写计划、不测试、完工只报一行 |

自制·个人领域知识:

| Skill | 用途 |
|---|---|
| `personal-ui-taste` | 个人前端审美:已确认偏好与场景规则(浅色信息密集界面 / 预览型工作台)、多系列图表焦点联动、密集图表就近悬浮、症状索引与反馈演化协议 |

## 依赖

- 6 个 Matt 的 skill:零依赖
- 3 个记忆 skill:依赖三层记忆栈(magic-context `ctx_memory` 插件、claude-mem、`docs/` StrictDoc 结构);项目 `AGENTS.md` 需粘入本仓库 [AGENTS.md](AGENTS.md) 中 `memory-system:start/end` 之间的触发块
- 2 个工作流 + 1 品味 skill:无硬依赖,品味内联
- `.sdoc` 校验需要 `strictdoc`:脚本末尾会检查 `uv`(缺则装,并处理 uv 自升级与清华 PyPI 镜像),并可选择用 `uv tool install strictdoc==0.28.1` 全局安装(升级:`uv tool upgrade strictdoc`)

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

| 项目 | `pi-setup.sh` 的行为 |
|---|---|
| Provider/模型 | 部署 `~/.pi/agent/models.json`:claude-newapi(anthropic)、codex-newapi(openai-responses)、anthropic-newapi;**anthropic 协议 `baseUrl` 填根域**(pi 自动补 `/v1/messages`,填 `/v1` 会 404),openai 协议带 `/v1`;`compat.supportsStore:false`、`thinkingLevelMap`(xhigh/max)对应 opencode 的 variants |
| 设置 | `~/.pi/agent/settings.json`:默认 provider/model/thinking、`defaultTools` 补 `grep/find/ls`(pi 默认只开 read/bash/edit/write)、`packages` 由 `pi install` 维护;不设置 Pi 的 `compaction` 开关——magic-context Pi 扩展在 `session_before_compact` 事件里自行 cancel 原生压缩(与官方 `setup --harness pi` 行为一致,官方只注册包 + 写共享 jsonc) |
| 运行默认值 | `modelThinkingLevels` 为 `codex-newapi/gpt-6-astra`、`codex-newapi/gpt-5.6-sol` 保存 `xhigh`,其余沿用全局 `high`;agent 级 `retry` 设置 `maxRetries:3`、`baseDelayMs:4000`,等待 4/8/16 秒(加上首发最多 4 次请求),不额外开启 provider 内层重试 |
| 自动命名 | `pi-autoname@0.6.8` + `~/.pi/agent/pi-autoname.json`:用 `codex-newapi/gpt-5.6-sol` 在任务结束后生成会话名;周期重命名冷却 1440 分钟、尊重手工名称,可 `/autoname` 手动触发。会额外发送最近对话片段给命名模型;失败可尝试当前会话模型或回退文本提取,冷却不是请求配额。该版本配置路径固定为 `~/.pi/agent`,自定义 `PI_CODING_AGENT_DIR` 时脚本跳过此插件 |
| 任务耗时 | 本仓库包的 `pi/extensions/message-timing.ts`:从首个 `agent_start` 到 `agent_settled` 记录结束时间与秒数,包含工具/重试/排队后续消息;custom entry 持久保存、不进模型上下文、不高频刷新,仅 TUI 记录 |
| 凭据 | `~/.pi/agent/auth.json`(权限 600,coding plan 等 Pi 内置 provider 的 key):模板为 `zai-coding-cn`/`kimi-coding` 占位符;字段级合并,已填 key 不覆盖,仅初始化缺失文件。这类内置 provider(智谱 coding plan、Kimi For Coding、qwen/xiaomi token plan、opencode-go 等)不需要写 `models.json` |
| MCP | `~/.agents/mcp.json`(共享技能目录):mcphub-web(远程 URL)、codegraph、claude-mem;本地命令路径部署时替换为本机 `bun`/`codegraph` 绝对路径(pi-mcp-adapter 读取)。mcphub-web 配了 `directTools` 挂 5 个常用直连工具(tavily search/extract、firecrawl scrape/search/research_search_github,首次调用自动 lazyConnect),其余工具走 `mcp` 网关(`mcp({search/describe/connect})`,网关内调用名需带 `mcphub-web_` 前缀) |
| 插件 | `pi install npm:...`:pi-mcp-adapter、`@dietrichgebert/ponytail`(官方带 pi-extension)、`pi-subagents-j0k3r`、`pi-lens`(实时诊断/符号检索,注册 `lens_diagnostics`/`symbol_search` 等工具)、`@juicesharp/rpiv-ask-user-question`(结构化提问工具 `ask_user_question`——pi 核心无提问工具,plan-brief/grilling 类流程需要它)、`@cortexkit/pi-magic-context`、`pi-autoname@0.6.8`;**本仓库自身也是 Pi 包**(`pi install git:github.com/brilliantrough/agent-skills`,提供个性化 UI(`/ui`)、claude-mem 桥扩展、延迟 prompt 扩展(`/later`)、任务耗时扩展、one-dark 主题;旧版散装部署文件会被脚本清理。脚本在 `pi update --all` 之后会明确报出本插件的版本变化(`本仓库 Pi 插件已更新: <旧> -> <新>(N 个提交)` / `本次无更新`),不用猜有没有更新上) |
| 主题 | 仓库 `pi/themes/onedark.json` 由上面的 **Pi 包**提供(One Dark,56 色 token;热重载),settings.json `theme: one-dark`。换主题:改 `theme` 或装主题包(如 `awesome-pi-themes` 65 款、`@inobit/pi-themes`);`/settings` 里可选所有已装主题 |
| claude-mem | 官方无 Pi 适配;**本仓库 Pi 包**内置自研桥扩展(镜像 opencode 插件契约:POST worker `/api/sessions/init\|observations\|summarize`,`platformSource:"pi"`;采集工具调用 + 助手消息 + **用户 prompt**,支持 `前缀*` 跳过),并提供 `claude_mem_search` 工具直连 worker(不依赖 MCP) |
| 个性化 UI | `pi/extensions/ui/index.ts`:基于纳管的 Atelier 0.10.1 布局/侧栏与 Zentui 0.24.0 编辑器/消息视觉，统一入口，不再安装两套 UI 包；含 LF 提交修复、TPS、HΣ/H₁、R/W 及现有 Magic Context `todowrite` 侧栏。配置 `agent-skills-ui.json` / `agent-skills-editor.json`，命令 `/ui`、`/ui sidebar`；[源码与许可证说明](pi/extensions/ui/README.md) |
| UI 迁移 | `pi/migrate-ui.py` 默认只预览，加 `--apply` 才备份、停用旧 UI 包和已知散装扩展；哈希不匹配/符号链接/包资源过滤需人工确认，不覆盖已有按键、凭据或无关包。setup 在安装本仓库包后调用，首次仅补缺失 Enter 换行与 Ctrl+Enter/Ctrl+J 提交配置 |
| later | 本仓库 Pi 包的 `pi/extensions/later.ts`:`/later 5h <prompt>` 到点把该 prompt 作为用户消息注入 agent(`sendUserMessage` + `deliverAs:followUp`,空闲立即发、忙时排队等本轮结束),另有 `/later list`、`/later cancel <id/all>`;排程只活在当前 pi 进程内,退出/重启/切换会话即丢(挂机请用 tmux 保持 pi 常驻) |
| subagent | `~/.pi/agent/agents/{explore,general}.md`(对应 opencode 的 explore/general);frontmatter 的 `tools` **必须显式写**,默认值引用了不存在的工具 |
| magic-context 版本守卫 | opencode 插件缓存把版本钉死在下载时(重启不自动升级),与 Pi 扩展版本不一致时,共享的 `context.db` 会让新宿主 fail-closed 拒绝主回合;脚本检测到不一致时**默认不启用** Pi 版,并给出「清 `~/.cache/opencode/packages/@cortexkit/opencode-magic-context@latest` → 重启 opencode → 重跑本脚本」步骤 |
| uv/strictdoc | 同 opencode-setup.sh |

手工步骤(不用脚本时):`pi install npm:pi-mcp-adapter`、`npm:@dietrichgebert/ponytail`、`npm:pi-subagents-j0k3r`、`npm:pi-lens`、`npm:@juicesharp/rpiv-ask-user-question`、`npm:@cortexkit/pi-magic-context`、`npm:pi-autoname@0.6.8`、`git:github.com/brilliantrough/agent-skills`(逐个装;`pi remove <source>` 卸载、`pi list` 查看);把 dot_file 的 `pi/{models,settings,mcp,auth,pi-autoname}.json`、`pi/agents/*.md` 放到对应位置,填好 `models.json` 的网关占位符与 `auth.json` 的 coding plan key(`pi auth check --provider <p>` 可验证)即可。

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
curl 127.0.0.1:37700/api/health
```

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

### 7. 按键改绑(Enter 换行 / Ctrl+Enter 发送)

默认 Enter 直接发送,长 prompt 没编辑完就飞出去。改成 Enter 换行:

```jsonc
"keybinds": {
  "input_newline": ["enter", "shift+enter"],
  "prompt_submit": ["ctrl+enter", "alt+enter"]
}
```

- `Enter` / `Shift+Enter` → 换行,`Ctrl+Enter` / `Alt+Enter` → 发送
- **Alt+Enter 是保底**:走 legacy 的 `ESC+\r`,任何终端都能送出来(**现在就能用**,不用改终端)
- **Ctrl/Shift+Enter 要三件套**:终端键位表能区分修饰键 + tmux 透传 + 应用解析。Konsole 23.08 不自带 csi-u 键位表 → 用 dot_file 里的 `konsole/csi-u.keytab`(Settings → Edit Current Profile → Keyboard 选 `CSI-u …`);tmux 需要 `set -g extended-keys always` + `set -as terminal-features 'xterm*:extkeys'`(pi 启动时会自己警告 `extended-keys` 为 off)。opencode 两种编码都认(`ESC[27;5;13~` xterm 格式 / `ESC[13;5u` kitty 格式,实测)
- 这套做法和上游一致:opencode 官方 [Keybinds 文档](https://opencode.ai/docs/keybinds) 的 Shift+Enter 段就是让终端改发 `\u001b[13;2u`(同一个 CSI-u 编码);issue [#11898](https://github.com/anomalyco/opencode/issues/11898)(Enter 换行 + Ctrl+Enter 发送)正是本改动,维护者在 [#11983](https://github.com/anomalyco/opencode/issues/11983) 回复「必须改终端设置让它送出修饰键」;[Claude Code 终端配置](https://code.claude.com/docs/en/terminal-config) 的 tmux 片段同样是 `extended-keys` + `terminal-features 'xterm:extkeys'`
- `opencode-setup.sh` 第 5.4 步写入这两个键,**只补缺失的键**,本地已自定义的按键不动(想回默认就手动删掉该键)
- Pi 的个性化 UI 包内置 LF 提交修复；`pi/migrate-ui.py` 为 `~/.pi/agent/keybindings.json` 补缺失的 `tui.input.submit: [ctrl+enter, ctrl+j]` / `tui.input.newLine: [enter, shift+enter]`，保留已有按键；改完 `/reload`，实体按键效果仍以当前终端为准。

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
npx skills update -g
```

重跑 `opencode-setup.sh` / `pi-setup.sh` 是幂等的,配置文件按「字段级合并」更新,不覆盖本地敏感值:

| 文件 | 更新方式(non-destructive) |
|---|---|
| `~/.config/opencode/opencode.json` | 已存在的 provider 保留本地 `options`(apiKey/网关),只按模板覆盖 `models`;模板新增的 provider 整块加入;模板的非 provider 字段仅在本地缺该键时补入 |
| `~/.claude-mem/settings.json` | 模板的非敏感字段值优先下发;`CLAUDE_MEM_PROVIDER` 强制为 `openrouter`;`api key` / `base url` / `*_MODEL` 等敏感键与含 `<占位符>` 的值保留本地内容;本地独有键保留 |
| `~/.config/cortexkit/magic-context.jsonc` | 同 settings.json(含 `historian.pi` / `dreamer.pi` 块,与 opencode 共用) |
| `~/.pi/agent/{settings,models}.json`、`~/.agents/mcp.json` | 同 settings.json(pi-setup.sh);mcp.json 的本地命令路径在合并前按本机替换 |
| `~/.pi/agent/agents/*.md`、`extensions/claude-mem.ts` | 整文件部署:内容有差异才写,原文件存 `.bak-YYYYmmddHHMMSS` |

有改动时先把原文件存为时间戳 `.bak-YYYYmmddHHMMSS`;合并结果与本地一致则不写文件。magic-context 的合并会把 JSONC 规整为 JSON(注释丢失,原样保留在 `.bak` 里)。

## 单装某一个

```bash
npx skills add brilliantrough/agent-skills@tdd -g -y
```

## License

自研部分 MIT。`skills/{grilling,grill-with-docs,domain-modeling,tdd,diagnosing-bugs,code-review}` 来自 mattpocock/skills,归属见 [NOTICE](NOTICE.md)。
