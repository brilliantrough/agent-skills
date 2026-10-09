# OpenCode 插件分发

面向 OpenCode v1/v2 的安装、更新与旧入口迁移。setup 只用 `opencode --version` 识别主版本，**不安装／升级宿主，不启动服务，不迁移数据库**。Magic Context 刷新单独询问，默认 N。

## 安装与更新

先安装 OpenCode；已有安装先退出 TUI 和后台服务。无需手工删除旧插件。

```bash
curl -fsSL https://raw.githubusercontent.com/brilliantrough/agent-skills/main/opencode-setup.sh -o /tmp/opencode-setup.sh
bash /tmp/opencode-setup.sh --check
bash /tmp/opencode-setup.sh --plugins-only
# 首次安装完整套装：bash /tmp/opencode-setup.sh
```

| 模式 | 执行范围 | 不执行 |
| --- | --- | --- |
| 默认完整安装 | 插件、依赖、配置、通用 skills；按交互选择执行 | 宿主／数据库升级 |
| `--plugins-only` | 自维护包、context-mode 及其 skills、官方包登记、旧入口迁移 | 模型模板、Python 环境、通用 skills、claude-mem 资产安装、notify 安装、按键统一 |
| `--check` | 下载校验自维护发布包，检查配置与 Magic Context，查询 Ponytail／Magic Context 版本，列出管理路径和待退役项 | 部署、更改配置／认证／数据库；也不试运行插件或检查全部依赖 |

- 完整安装默认同步 base 19 个 skills；交互选择全组时为 27 个，另同步四个外部设计 skills。实体位于 `~/.agents/skills/`；context-mode 自带 skills 位于 `$CFG/skill/`。
- `-y`／`--yes` 取各项默认值，**不是全部同意**；算力组与 notify 首装默认跳过。查看输出中的 WARN，缺包或网络失败后重跑。
- 两个精简模式要求已有 Python 3、curl；`--check` 仍联网，宿主 `--version` 可能写自己的日志，不是零文件系统写入。
- `$CFG`：`OPENCODE_CONFIG_DIR` 优先，否则 `$XDG_CONFIG_HOME/opencode` 或 `~/.config/opencode`。Windows 用 Git Bash；本轮 v1/v2 迁移尚未做 Windows 实机验收。

## 两代宿主如何加载

| 客户端 | 自维护资产 | 安装位置 | 配置 |
| --- | --- | --- | --- |
| v1 | `opencode-plugins-v1.tar.gz` | `plugins/zz-agent-skills.js`、`tui-plugins/later/`、`context-rewrite/` | server 自动发现；npm 用 `plugin`，TUI 用 `tui.json(c)` |
| v2 | `opencode-plugins-v2.tar.gz` | `v2/` 目录包：server `index.js`、TUI `tui.js` | `plugins` 登记目录，界面用 `cli.json` |

**当前仍是两个分发资产，不是单一双入口自维护包。** 公共功能复用，宿主适配分开：

- `later`：共用 Agent 工具逻辑；v1/v2 各有 TUI 适配。输入框排程与 Agent 工具排程独立，分别随 TUI／服务端进程退出清除。
- `context_rewrite`：共用 `context-rewrite/core.mjs`、`output-store.mjs`，分别适配两代工具与消息 API；包含近期纠错、持久外置和全文取回。
- `claude-mem`：wrapper 打进包；上游 bundle 留在 `$CFG/lib/claude-mem.js`。缺失时跳过采集 hook，其 MCP／worker 仍独立配置。
- v2 额外适配旧工具 API、会话事件与请求亲和性；不要求目标机编译。

工具用法见 [上下文插件](../context-rewrite/README.md)，v2 文件与配置见 [v2 说明](v2/README.md)。

### 外部插件

| 对象 | setup 行为 |
| --- | --- |
| Ponytail | 查询本地版本与 npm latest；有新版时默认询问刷新，确认后备份移走对应缓存并登记官方 `@latest`，下次宿主启动下载；不运行宿主 plugin CLI |
| Magic Context | 单独询问刷新，默认 N；版本缺失／不明／过旧只报 WARN，不阻塞其他插件。确认后移走 latest 缓存并登记官方 `@latest`，下次宿主启动下载 |
| context-mode | 独立从 `releases/latest` 同步；v1 放 `plugins/context-mode/`，v2 放 `vendor/context-mode/`，不另加配置插件登记 |
| notify | 仅完整安装的 v1 路径可选；v2 将旧入口备份停用，后续由 notify 项目适配 |

版本检查与刷新：

- 只检查套件引用的 Ponytail、Magic Context：按配置与当前宿主缓存读取本地实际版本，联网查询官方 npm `latest`。不扫描或更新用户自行安装的其他包。
- Ponytail 稳定版有新版时询问，普通 npm／`@latest` 登记默认 Y；钉版或本地路径默认 N。版本一致不重装，本地更高不降级；非稳定版本只提示人工核对。缺包交宿主安装，已有缓存但版本未知可询问刷新。
- 确认 Ponytail 刷新后，只备份移走其 `@latest` 缓存到 `.agent-skills-backups/<时间戳>/ponytail-cache/`，登记改为官方 `@latest`，保留 options。钉版缓存和任意本地源码目录不删除。
- 查询失败：显示 WARN，不据此刷新；`--check` 不询问。`-y`／无终端采用各项默认值，Ponytail 普通登记可刷新，钉版／本地路径及 Magic Context 跳过。
- 此时仅**安排更新**；下载与加载发生在下次宿主启动。日常仍可用 OpenCode v2 `/plugins` 更新，不必每次运行 setup；版本一致不等于加载正常，npm latest 也不保证兼容任意旧宿主。

Magic Context 操作：

- **选 Y**：确认 OpenCode／Desktop／Pi 均已停用、共享库已备份。只将 OpenCode 两代布局中的 Magic Context `@latest` 缓存移到 `$CFG/.agent-skills-backups/<时间戳>/magic-context-cache/`；旧目录／钉版登记改为官方 npm `@latest`，保留插件 options。不删除任意本地源码目录、Pi 包、其他插件缓存或数据库。
- **选 N／`-y`／无终端**：不刷新缓存，保留现有登记；兼容性问题只报 WARN。其他插件继续部署，但不保证 Magic Context 或宿主可以启动。没有登记且共享库版本未知时不新增入口。
- **`--check`**：只报告现状，不询问、不刷新。通过仅表示套装可部署，不代表 Magic Context 已可用。
- 未确认刷新时，首装仍优先沿用已有 OpenCode／Pi 版本；没有已装版本和共享库时固定用 0.45.0。v2 兼容基线至少 0.45。

刷新后由宿主 loader 下载包、由 Magic Context 自己处理数据库迁移；setup 不运行它们。同机 Pi 的 Magic Context 需另行同步升级。Ponytail 仍使用官方双入口包，缺包由宿主下载。

## 旧插件迁移与备份

默认安装与 `--plugins-only` 使用同一个部署器。既能更新旧散装插件，也能从旧分版本包升级；无需先手工删除。

| 情况 | 处理 |
| --- | --- |
| 旧散装 → 当前 v1 | 更新 bundle、TUI 与 context-mode，退役独立 wrapper／later／纠错入口 |
| 旧散装／旧 v1 包 → v2 | 部署 `v2/`，登记 `plugins`，停用旧 server／TUI 入口及内置 Ponytail 配置 |
| 同版本重跑 | 内容相同不重写、不重复注册，不产生无变化备份 |
| 已有 v2 配置再运行 v1 | 停止；需隔离配置，不自动降级 |

- 管理固定安装路径；不按文件名子串删除用户插件。未知第三方登记保留，兼容性仍需自行确认。
- v1→v2 退役：旧 wrapper／later／纠错、`plugins/zz-agent-skills.js`、`tui-plugins/later/`、`context-rewrite/`、旧 context-mode 入口与目录、notify、旧请求头插件。
- 插件资产备份到 `$CFG/.agent-skills-backups/<时间戳>/<原相对路径>`；同时移走 `plugins/context-mode.bak-*` 遗留目录，避免被 v2 再次扫描。配置文件保留相邻 `.bak*` 备份。
- 私密字段、provider options、MCP 与其他本地字段保留；已有 v2 原生 `providers` 不套 v1 模型模板。完整安装会刷新 v1 `provider.models`，精简插件模式不做。
- `opencode.jsonc` 合并到 `opencode.json` 后备份退役。v2 已有 `cli.json` 时保留；没有时合并旧 `tui.json(c)` 为 `tui.json`，由宿主首启迁移 action、界面与 state。完整安装的按键设置另行确认。
- 除确认的 Ponytail／Magic Context 缓存刷新外，不清理 npm 插件缓存；认证、会话库与外置正文不动。**插件备份不是整机快照，也不替代数据库备份。****

自维护发布包校验失败、未知宿主版本、配置无法解析、相关写入路径为符号链接时停止；Magic Context 兼容性问题改为警告与独立刷新询问。

## 升级、共存与回退

1. 停止旧 TUI 和后台服务，保存配置、认证、state 与一致的会话数据库备份
2. 升级 OpenCode 二进制，再执行 setup 预检和插件同步
3. 启动新版，由 OpenCode 自己迁移会话库与 CLI 配置；首次 npm 包安装需要网络

Magic Context 的共享 `context.db` 由它自己的版本和迁移机制管理；升级须安排所有使用宿主均停用的窗口，在 setup 的独立询问中确认刷新。不能把 OpenCode 升级等同于允许升级 Magic Context。

v1/v2 可以并存二进制，但并行运行须隔离配置、数据、state、cache；Magic Context 存储也需按用途隔离。回退前保留升级后的新增数据，再恢复对应备份；只换旧二进制、只恢复插件目录都不是完整回退。

## 验证范围

已验证 Linux **v1 1.18.35／v2 2.0.26**：旧散装更新、v1→v2、公开脚本与资产下载、精简模式重复运行；私密字段、用户插件、认证与会话库保留。两端均发现全部 27 个本仓 skills、context-mode skills，并从空缓存自动安装 Ponytail 5.1.0。

真实模型、TUI、纠错与外置链路已做分项验收。未覆盖 Windows 实机、任意历史宿主版本、所有第三方插件与长会话场景；`--check` 成功不等于这些运行路径都通过。

## 构建与发布

开发机需要 Node/npm、Bun、GNU tar、gh；目标机不编译插件。

```bash
npm ci --prefix context-rewrite --ignore-scripts
npm ci --prefix opencode --ignore-scripts
bun opencode/release.mjs
```

产物：`opencode/dist/`；每包有文件哈希清单和部署器，`dist/` 不入 git。

发新版：同步修改 `opencode/package.json` 的 `version` 与根脚本 `OC_RELEASE=opencode-plugins-<版本>`，更新 lock，再构建、实机验收。提交所需源码后：

```bash
git tag opencode-plugins-<版本>
git push origin opencode-plugins-<版本>
bun opencode/release.mjs --publish
git push origin main
```

先发布资产，再推送引用它的 setup；发布使用 `--latest=false`，不抢占 context-mode 的 latest。已发布版本不覆盖，产物改动另升版本。仅修改说明不重发资产；发布包中附带的 README 在下次构建时更新。

## 许可证

局部吸收与编号使用 [ranxianglei/acp-kernel](https://github.com/ranxianglei/acp-kernel) 0.0.101；相关项目 [billion-context](https://github.com/ranxianglei/billion-context)。保留 [ACP-KERNEL-LICENSE](../context-rewrite/ACP-KERNEL-LICENSE) 的许可证及出处标注要求。包内另附 OpenCode／Zod 许可证。
