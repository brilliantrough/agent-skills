# agent-skills

个人 agent skills 集,含三层记忆系统与任务工作流。

```bash
npx skills@latest add brilliantrough/agent-skills --all -g -y
```

skill 装在 `~/.agents/skills/`,重开 agent session 生效。

## Skills(11 个)

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

## 依赖

- 6 个 Matt 的 skill:零依赖
- 3 个记忆 skill:依赖三层记忆栈(magic-context `ctx_memory` 插件、claude-mem、`docs/` StrictDoc 结构);项目 `AGENTS.md` 需粘入本仓库 [AGENTS.md](AGENTS.md) 中 `memory-system:start/end` 之间的触发块
- 2 个工作流 skill:无硬依赖,品味内联

## 插件配置

一键脚本(交互确认、幂等,含占位符清单输出):

```bash
bash opencode-setup.sh
```

手工步骤如下。

### 1. claude-mem

```bash
npx claude-mem install --ide opencode
```

装完三件事:

**① wrapper 修复**(upstream bug [thedotmack/claude-mem#2854/#3328](https://github.com/thedotmack/claude-mem/issues/2854):bundle 导出非函数常量)。bundle 移到 `~/.config/opencode/lib/claude-mem.js`,并创建 `~/.config/opencode/plugins/claude-mem-wrapper.js`:

```js
import { ClaudeMemPlugin } from "../lib/claude-mem.js";

export default ClaudeMemPlugin;
```

plugin 条目使用 `./plugins/claude-mem-wrapper.js`。升级 claude-mem 后重跑 `opencode-setup.sh` 修复。

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
  "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>"
}
```

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
  },
  "sidekick": {
    "disable": true
  }
}
```

故障自检:`npx @cortexkit/magic-context@latest doctor`。

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
    }
  }
}
```

npm 形式条目在 opencode 重启时自动安装;配置改动重启 opencode 生效。

## 更新

```bash
npx skills update -g
```

## 单装某一个

```bash
npx skills add brilliantrough/agent-skills@tdd -g -y
```

## License

自研部分 MIT。`skills/{grilling,grill-with-docs,domain-modeling,tdd,diagnosing-bugs,code-review}` 来自 mattpocock/skills,归属见 [NOTICE](NOTICE.md)。
