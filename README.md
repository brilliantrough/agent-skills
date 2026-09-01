# agent-skills

个人 agent skills 精选集,带三层记忆系统的工作流。一条命令在任何服务器上装好:

```bash
npx skills@latest add brilliantrough/agent-skills --all -g -y
```

装完重开 agent session(opencode / claude-code 等)即生效,skill 装在 `~/.agents/skills/`。

## 包含的 Skills(9 个)

来自 [mattpocock/skills](https://github.com/mattpocock/skills)(MIT,见 NOTICE):

| Skill | 用途 |
|---|---|
| `grilling` | 对计划/设计做穷追不舍的访谈,直到设计树每个分支都有结论 |
| `grill-with-docs` | grilling + 同步沉淀 `CONTEXT.md`(共享语言)和 ADR |
| `domain-modeling` | 构建和打磨项目领域模型、术语表 |
| `tdd` | 红-绿-重构循环的测试驱动开发 |
| `diagnosing-bugs` | 硬 bug 诊断回路:先建能变红的反馈回路,再假设原因 |
| `code-review` | 双轴审查(规范符合度 + spec 忠实度),并行子代理 |

自制(三层记忆系统):

| Skill | 用途 |
|---|---|
| `load-mem` | 会话启动时加载全部记忆层(注入记忆 / StrictDoc / claude-mem) |
| `save-mem` | 里程碑时持久化记忆(ctx_memory 存事实,StrictDoc 存叙事) |
| `migrate-mem` | 把散落的旧记忆文件迁入三层记忆系统 |

## 依赖说明

6 个 Matt 的 skill 零依赖,装了就能用。

3 个记忆 skill 依赖三层记忆栈(magic-context 的 `ctx_memory` 插件 + claude-mem + `docs/` StrictDoc 结构)。目标服务器没有这套栈时,skill 仍可读,但需要先按 [AGENTS.md](AGENTS.md)(即 `memory-system:start/end` 之间的块)把触发块粘进项目的 `AGENTS.md`,并配好对应插件。

## 插件配置(其他服务器)

skills 只是说明书,三层记忆栈的运行依赖三个 opencode 插件:claude-mem、magic-context、ponytail。

### 1. claude-mem(动作捕获 + 检索)

官方安装器一条命令(会写入 `~/.claude/plugins/marketplaces/thedotmack/` 和 `~/.config/opencode/plugins/claude-mem.js`):

```bash
npx claude-mem install --ide opencode
```

装完需要三件手工事:

**① wrapper 修复**(upstream bug [thedotmack/claude-mem#2854/#3328](https://github.com/thedotmack/claude-mem/issues/2854):bundle 导出非函数常量,而 opencode 的 loader 要求每个导出都是函数)。创建 `~/.config/opencode/plugins/claude-mem-wrapper.js`:

```js
// Wrapper for claude-mem's OpenCode plugin.
// Works around upstream bug (thedotmack/claude-mem#2854/#3328): re-exports
// only the plugin function so every export is callable.
import { ClaudeMemPlugin } from "./claude-mem.js";

export default ClaudeMemPlugin;
```

并把 opencode 配置里 plugin 条目的 `./plugins/claude-mem.js` 换成 `./plugins/claude-mem-wrapper.js`。注意:每次升级/重装 claude-mem,安装器会把条目改回 `claude-mem.js`,需要重新指向 wrapper,直到上游修复。

**② MCP 工具组**(claude_mem_search / timeline / smart_* 等 19 个工具)。写进 opencode.jsonc 的 `mcp` 段。必须用 bun 运行(`mcp-server.cjs` 依赖 `bun:sqlite`,node 会崩);路径刻意用无版本号的 marketplace 路径,升级后配置不用跟着改:

```jsonc
"mcp": {
  "claude-mem": {
    "type": "local",
    "command": ["<YOUR_BUN_PATH>", "<HOME>/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"],
    "enabled": true
  }
}
```

bun 安装:`curl -fsSL https://bun.sh/install | bash`(bun 路径通常为 `~/.bun/bin/bun`)。

**③ 配置文件** `~/.claude-mem/settings.json`(模型 / Provider / Key):

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

- `OBSERVATIONS=20`:刻意压低 SessionStart 注入预算,别让 claude-mem 的动作流水淹没 magic-context 的记忆注入
- 改完要重启 worker:`cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart`,然后 `curl 127.0.0.1:37700/api/health` 确认
- 注入/hook 行为类配置改动需要重启 opencode(进程内通过 loadFromFileOnce 读取)

### 2. magic-context(ctx_memory 注入 + 记忆管理)

plugin 条目加一行即可,进程内插件、无 daemon、embedding 本地(无 API key):

```jsonc
"plugin": [
  "@cortexkit/opencode-magic-context@latest"
]
```

可选配置文件 `~/.config/opencode/magic-context.jsonc`——**不创建即全默认**(本机即是如此)。需要覆盖 historian 模型、provider 等时再创建,键名参考上游 README(@cortexkit/opencode-magic-context)。

### 3. ponytail(品味 skill)

plugin 条目加一行:

```jsonc
"plugin": [
  "@dietrichgebert/ponytail"
]
```

### opencode.jsonc 汇总(新服务器最小可用)

本机 opencode.json / opencode.jsonc 并存是历史遗留;新服务器建议全部写进一个 `~/.config/opencode/opencode.jsonc`:

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

npm 形式的插件条目在 opencode 重启时自动安装(缓存于 `~/.cache/opencode/packages/`);所有插件配置改动均需重启 opencode 生效。

## 更新

```bash
npx skills update -g
```

## 单装某一个

```bash
npx skills add brilliantrough/agent-skills@tdd -g -y
```

## License

自研 skill:MIT。`skills/{grilling,grill-with-docs,domain-modeling,tdd,diagnosing-bugs,code-review}` 来自 mattpocock/skills,归属见 [NOTICE](NOTICE.md)。
