# agent-skills

个人 agent skills 精选集,带三层记忆系统的工作流。一条命令在任何服务器上装好:

```bash
npx skills@latest add brilliantrough/agent-skills --all -g -y
```

装完重开 agent session(opencode / claude-code 等)即生效,skill 装在 `~/.agents/skills/`。

本仓库还提供 [`opencode-setup.sh`](opencode-setup.sh):在新服务器上一键配好三层记忆栈的插件部分——代理环境提醒、依赖检查(fnm/Node、bun)、claude-mem 官方安装与 upstream bug 修复、MCP 工具组、magic-context/ponytail 插件条目。全部交互确认、幂等可重跑:

```bash
bash opencode-setup.sh
```

## 包含的 Skills(11 个)

来自 [mattpocock/skills](https://github.com/mattpocock/skills)(MIT,见 NOTICE):

| Skill | 用途 |
|---|---|
| `grilling` | 对计划/设计做穷追不舍的访谈,直到设计树每个分支都有结论 |
| `grill-with-docs` | grilling + 同步沉淀 `CONTEXT.md`(共享语言)和 ADR |
| `domain-modeling` | 构建和打磨项目领域模型、术语表 |
| `tdd` | 红-绿-重构循环的测试驱动开发 |
| `diagnosing-bugs` | 硬 bug 诊断回路:先建能变红的反馈回路,再假设原因 |
| `code-review` | 双轴审查(规范符合度 + spec 忠实度),并行子代理 |

自制·三层记忆系统:

| Skill | 用途 |
|---|---|
| `load-mem` | 会话启动时加载全部记忆层(注入记忆 / StrictDoc / claude-mem) |
| `save-mem` | 里程碑时持久化记忆(ctx_memory 存事实,StrictDoc 存叙事) |
| `migrate-mem` | 把散落的旧记忆文件迁入三层记忆系统 |

自制·任务工作流(手动 cue 触发):

| Skill | 用途 |
|---|---|
| `plan-brief` | 复杂需求的完整闭环:吃透需求 → 盘问细节(必问环境、验证模式)→ 生成中文计划文档 `docs/plans/<slug>.md` + 自包含启动 prompt → 拉起新会话执行 → 执行者写开发报告(`<slug>.report.md`,允许搁置、禁止造假)→ 规划会话审查(`<slug>.review.md`)。验证模式二选一:TDD(快反馈产品代码)/ smoke-and-read(科研长任务,禁测试脚手架)。规划会话本身永不执行、不开 sub-agent |
| `quick-do` | 简单任务零仪式感,当前会话直接干完:最多问一个问题、不写计划、不测试不做 TDD、完工只报一行。批量覆盖/删除等不可逆操作先展示再动手 |

**用法**:复杂需求 = 写完需求文本(输入框或文件)+ cue `plan-brief`;简单任务 = 一句话说明 + cue `quick-do`。手动 cue 保证稳定触发,两个 skill 的品味内核一致(ponytail)。

## 依赖说明

6 个 Matt 的 skill 零依赖,装了就能用。

3 个记忆 skill 依赖三层记忆栈(magic-context 的 `ctx_memory` 插件 + claude-mem + `docs/` StrictDoc 结构)。目标服务器没有这套栈时,skill 仍可读,但需要先按 [AGENTS.md](AGENTS.md)(即 `memory-system:start/end` 之间的块)把触发块粘进项目的 `AGENTS.md`,并配好对应插件。

## 插件配置(其他服务器)

skills 只是说明书,三层记忆栈的运行依赖三个 opencode 插件:claude-mem、magic-context、ponytail。

**推荐:直接跑 `bash opencode-setup.sh`**,下列手工步骤它全部自动化(依赖安装与 claude-mem 安装均先征得同意)。手工步骤留作参考与故障排查。

### 1. claude-mem(动作捕获 + 检索)

官方安装器一条命令(会写入 `~/.claude/plugins/marketplaces/thedotmack/` 和 `~/.config/opencode/plugins/claude-mem.js`):

```bash
npx claude-mem install --ide opencode
```

装完需要三件事(`opencode-setup.sh` 可全部自动完成,以下为手动参考):

**① wrapper 修复**(upstream bug [thedotmack/claude-mem#2854/#3328](https://github.com/thedotmack/claude-mem/issues/2854):bundle 导出非函数常量,而 opencode 的 loader 要求每个导出都是函数)。脚本会把 bundle 移到 `~/.config/opencode/lib/claude-mem.js`(脱离加载器扫描),并创建 `~/.config/opencode/plugins/claude-mem-wrapper.js`:

```js
// Wrapper for claude-mem's OpenCode plugin.
// Works around upstream bug (thedotmack/claude-mem#2854/#3328): re-exports
// only the plugin function so every export is callable.
import { ClaudeMemPlugin } from "../lib/claude-mem.js";

export default ClaudeMemPlugin;
```

注意:每次升级/重装 claude-mem,安装器会把 `claude-mem.js` 重新拷回 `plugins/` 并注册失效条目,重跑 `opencode-setup.sh` 即可修复(幂等),直到上游修复。

**② MCP 工具组**(claude_mem_search / timeline / smart_* 等查询工具,当前版本 14 个;插件本体只注册 hook 不带工具,MCP 是工具唯一来源)。写进 opencode 配置的 `mcp` 段。必须用 bun 运行(`mcp-server.cjs` 依赖 `bun:sqlite`,node 会崩);路径刻意用无版本号的 marketplace 路径,升级后配置不用跟着改:

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

官方安装命令(交互式,自动插入 plugin 条目;`opencode-setup.sh` 调的就是它):

```bash
npx @cortexkit/magic-context@latest setup
```

也可手动在 plugin 条目加一行,进程内插件、无 daemon、embedding 本地(无 API key):

```jsonc
"plugin": [
  "@cortexkit/opencode-magic-context@latest"
]
```

可选配置文件 `~/.config/opencode/magic-context.jsonc`——**不创建即全默认**(本机即是如此)。需要覆盖 historian 模型、provider 等时再创建,键名参考上游 README(@cortexkit/opencode-magic-context)。

故障自检:`npx @cortexkit/magic-context@latest doctor`(自动检测 harness、校验插件注册与数据库,能修的自动修)。

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
