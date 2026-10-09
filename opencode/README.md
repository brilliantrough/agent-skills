# OpenCode 插件分发

面向 OpenCode v1/v2 的安装、更新与旧入口迁移。setup 只用 `opencode --version` 识别主版本，**不安装／升级宿主，不启动服务，不迁移会话数据库，不升级已有 Magic Context**。

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
| `--check` | 下载校验自维护发布包，检查配置与 Magic Context，列出管理路径和待退役项 | 部署、更改配置／认证／数据库；也不试运行插件或检查全部依赖 |

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
| Ponytail | 登记官方包，两代宿主启动时自动安装缺失包；不内置副本、不手填缓存、不运行宿主 plugin CLI、不升级已有包 |
| Magic Context | 保留已有版本；v2 至少 0.45。已有 `@latest` 须能定位已装包，无法确定则停止提示；不追 latest |
| context-mode | 独立从 `releases/latest` 同步；v1 放 `plugins/context-mode/`，v2 放 `vendor/context-mode/`，不另加配置插件登记 |
| notify | 仅完整安装的 v1 路径可选；v2 将旧入口备份停用，后续由 notify 项目适配 |

Magic Context 首装优先沿用已有 OpenCode／Pi 版本；没有已装版本和共享库时固定用 0.45.0。已有共享库却无法确认版本时停止，不擅自引入新版。Ponytail 使用官方同一个包的 v1/v2 双入口，与自维护包的分版本构建不同。

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
- 不删除 Magic Context／Ponytail 缓存、认证、会话库或外置正文。**插件备份不是整机快照，也不替代数据库备份。**

自维护发布包校验失败、未知宿主版本、配置无法解析、相关路径为符号链接、Magic Context 不满足条件时停止；按错误提示处理后重跑，不强制覆盖。

## 升级、共存与回退

1. 停止旧 TUI 和后台服务，保存配置、认证、state 与一致的会话数据库备份
2. 升级 OpenCode 二进制，再执行 setup 预检和插件同步
3. 启动新版，由 OpenCode 自己迁移会话库与 CLI 配置；首次 npm 包安装需要网络

Magic Context 的共享 `context.db` 由它自己的版本和迁移机制管理；升级须另选所有使用宿主均停用的窗口。不能把 OpenCode 升级等同于允许升级 Magic Context。

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
