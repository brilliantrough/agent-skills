# 贡献指南

本仓库分发「安装入口 + skills + 自有插件与适配」，不代替外部项目的核心开发。外部贡献最常见的三类是：新增 skill、引用外部能力、改动 setup 脚本。三类同一道关：**不能破坏别人的机器**。

文档用中文，短句、分点、表格优先。

## 先判断该放哪

| 你想加的东西 | 去处 | 不该进本仓的情况 |
| --- | --- | --- |
| 通用工作方法、品味、流程 | `skills/base/<名>/` | 只在某个项目成立的规范 |
| 算法研究、实验、性能调优 | `skills/research/<名>/` | 需要私有大盘或集群才能复现 |
| 算力平台模板 | `skills/accel/<名>/` | 单机特化值（应留在宿主机层） |
| 跨项目公共知识 | `skills/kb/<名>/` | 完整领域能力 |
| 固定版式带素材 | `skills/ppt/<名>/` | 素材权利来源不清 |

判据一句：**换一台机器、换一个人，还成立吗？** 不成立的留在自己项目里。

## 一、新增 skill

1. 建目录 `skills/<组>/<名>/`，写 `SKILL.md`。目录名 = frontmatter `name`，小写连字符，不与任何已有 skill 重名（跨组也不行）。
2. frontmatter 至少两项，`description` 要写清「做什么 + 何时用」——没提触发条件的 skill 不会被选中：

```yaml
---
name: my-skill
description: 一句话说明用途与触发场景。
---
```

命令式 skill（用户显式敲，不让模型自主触发）加 `disable-model-invocation: true`。

3. 正文写**判断与边界**，不是资料汇编。带上适用条件（模型 / 硬件 / 版本 / 日期）；阴性结果和一次昂贵踩坑，比正确结论更有复用价值。
4. 附件放 skill 目录内，用相对路径引用。**不得出现个人绝对路径、用户名、内网地址、凭据**。
5. 组策略由目录决定，不用改脚本：`base`/`research`/`ppt` 每次随仓库刷新（先备份本地漂移）、`accel` 缺才装（本机特化永不覆盖）、`kb` 每次覆盖不备份。放进组目录即生效。

## 二、引用外部能力（优先，而不是复制）

- **第三方 skill**：登记进 `skills-external.sh` 的名字表，由安装器装到用户机器。同名本地副本或不同来源副本不接管，保留并告警——别写成"强制覆盖"。
- **官方 CLI / 引擎**：用精确 repo 名安装（如 `hugohe3/ppt-master`），不 vendored 进本仓，不修改上游全局索引或用户环境的全局状态。
- **随包分发的素材**：另写 `ASSETS-NOTICE.md` 说明来源与权利边界，并同步 `NOTICE.md`。只有配图不要写授权结论——写"提供者确认了什么"，不写"已获授权"。
- **Pi 扩展 / 主题**：必须在 `package.json` 的 `pi.extensions` / `pi.themes` 登记，否则装了也不会加载。

整目录复制第三方源码不接受：上游一更新，本地改动静默消失。

## 三、改动 setup 脚本

四个入口 `pi-setup.sh` / `opencode-setup.sh` / `codex-setup.sh` / `dsh-setup.sh` 共享 `skills-sync.sh` 与 `skills-external.sh`。

**新增可选安装一律默认 N**：

```bash
ask "安装/更新 X 组(说明;缺才装·本机特化不覆盖)?" N && GROUPS+=(x)
```

`-y` 取各项默认值，默认 N 即"无人值守时不装"。默认 Y 只留给两种情况：不装就没有可用工具，或它是脚本自身的运行前提。新机器不该因为装了个基础套件，就顺带多出一个无头浏览器或一个 Python 虚拟环境。

其余硬约束：

| 约束 | 原因 |
| --- | --- |
| 幂等：重跑不改变已正确的状态 | 用户会反复跑 |
| 敏感键一律保留本机值 | 否则冲掉别人的 key / base_url |
| 字段级合并，不整文件覆盖 | 同上 |
| 四个入口同类逻辑保持一致 | 用哪台机器都得同一结论 |
| `*.sh` 保持 LF | Windows 检出后 Git Bash 才跑得起来（`.gitattributes` 已锁） |
| 不新增"取源"快捷方式 | 取源只有一种：从 GitHub 拉；自创分支会静默装错版本 |
| 不卸载、不删用户数据、不迁移数据库 | 安装脚本不该有破坏性 |

另两条：

- `AGENTS.tail.md` 是会被粘进目标项目 `AGENTS.md` 尾部的规范块，改它等于改所有人的提示词——单独成 PR 说明动机。
- 新增行为在 `tests/` 留一个可离线重跑的脚本：本地 fixture、不联网、不碰真实 `HOME`。

## 四、改动要一起更新的地方

最容易漏的一类：只改了 `skills/`，忘了文档计数。

| 位置 | 改什么 |
| --- | --- |
| `README.md` | 目录锚点（`#skills本仓-N-个`）、快速安装的组数量、`## Skills（本仓 N 个）`、OpenCode 模式表的 `all` 合计、更新表的分组行 |
| `opencode/README.md` | 完整安装的 base 数量与 `all` 合计 |
| `NOTICE.md` | 新增第三方代码、素材、字体、引擎 |
| `assets/<套名>/ASSETS-NOTICE.md` | 素材来源与权利边界 |

## 五、提交前自检

仓库的完整自检脚本不随分发，可跑下面这些等价的最小检查：

```bash
bash -n pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh skills-sync.sh skills-external.sh
python3 -m py_compile skills/*/*/scripts/*.py 2>/dev/null

# 结构：组目录只能是这五个；每个 skill 目录必须有 SKILL.md；不跨组重名
python3 - <<'PY'
import os, collections
G = {"base", "research", "accel", "kb", "ppt"}
seen, bad = collections.Counter(), []
for g in sorted(os.listdir("skills")):
    if not os.path.isdir(f"skills/{g}"):
        continue
    if g not in G:
        bad.append(f"未知组目录 {g}")
        continue
    for s in sorted(os.listdir(f"skills/{g}")):
        d = f"skills/{g}/{s}"
        if os.path.isdir(d):
            if not os.path.exists(f"{d}/SKILL.md"):
                bad.append(f"{d} 缺 SKILL.md")
            seen[s] += 1
bad += [f"{s} 跨组重名" for s, c in seen.items() if c > 1]
print("\n".join(bad) or "结构 OK")
PY
```

再人眼确认：`README.md` 的计数与 `skills/` 实际数量一致。

## 六、PR 要求

- 标题 `feat(范围):` / `fix(范围):` / `docs(范围):`，范围取脚本名或目录名（`skills`、`pi-setup`、`opencode`、`dsh`）。
- 正文写四项：改了什么、**在哪台机器上用什么命令验的**（贴输出）、没验什么、已知边界。验证矩阵比形容词有用。
- 明说"不做什么"：不迁移数据、不改他人配置、不加未经确认的默认安装。
- 带素材说明权利来源；带第三方代码说明许可与是否 vendored。
- 一个 PR 一件事。顺带重排、顺带升级宿主、顺带无关重构，另开 PR。
- Draft 可以开，用于征求方向；请在正文写清"还需什么才能合"。

## 七、不接受的改动

- 提交真实凭据、内网地址、个人绝对路径、会话或数据库样本。
- 整目录复制第三方 skill 或上游插件源码。
- 在分发链路里加"省一步"的快捷方式（本地副本当源、跳过下载、缓存兜底）。
- 覆盖用户已有的 `api_key` / `base_url` / `token` 等本机值。
- 只改一处计数，让 README 与 `skills/` 实际数量对不上。
- 把只在单个项目成立的审美、流程或路径写进 `base` 组。

## License

贡献进本仓的代码与文档按仓库 `LICENSE`（MIT）授权；第三方素材与代码的权利边界见 `NOTICE.md` 及各 `ASSETS-NOTICE.md`，不因本仓许可而扩展。
