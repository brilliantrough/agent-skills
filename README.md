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

3 个记忆 skill 依赖三层记忆栈(magic-context 的 `ctx_memory` 插件 + claude-mem + `docs/` StrictDoc 结构)。目标服务器没有这套栈时,skill 仍可读,但需要先按 `templates-AGENTS-memory-block.md` 把触发块粘进项目的 `AGENTS.md`,并配好对应插件。

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
