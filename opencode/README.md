# OpenCode 插件分发

仅维护 OpenCode V2；检测到 V1 时停止，提示先升级宿主。**完整 setup 询问执行 `opencode upgrade`（默认 Y），配置默认关闭自动更新**；不安装宿主、不启动服务、不迁移数据库。Magic Context 刷新单独询问，默认 N。

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
| 默认完整安装 | 插件、依赖、配置、通用 skills；按交互选择执行；宿主升级需显式确认 | 数据库升级 |
| `--plugins-only` | 旧配置转原生 V2、自维护包、context-mode 及其 skills、官方包登记、claude-mem runtime／入口／MCP、旧入口迁移 | 模型模板、Python 环境、通用 skills、按键统一 |
| `--check` | 下载校验自维护发布包，检查配置与 Magic Context，查询 Ponytail／Magic Context 版本，列出管理路径和待退役项 | 部署、更改配置／认证／数据库；也不试运行插件或检查全部依赖 |

- 完整安装默认同步 base 18 个 skills；交互可分别选择 research、accel、kb，全部选中时为 34 个，另同步三个外部设计 skills。实体位于 `~/.agents/skills/`；context-mode 自带 skills 位于 `$CFG/skill/`。
- `-y`／`--yes` 取各项默认值，**不是全部同意**；research、accel、kb 组默认跳过。查看输出中的 WARN，缺包或网络失败后重跑。
- 两个精简模式要求已有 Python 3、curl、Bun；完整安装可补齐 Bun。`--check` 仍联网，宿主 `--version` 可能写日志，不是零文件系统写入。
- `$CFG`：`OPENCODE_CONFIG_DIR` 优先，否则 `$XDG_CONFIG_HOME/opencode` 或 `~/.config/opencode`。Windows 用 Git Bash；本轮 v1/v2 迁移尚未做 Windows 实机验收。

## V2 如何加载

| 客户端 | 自维护资产 | 安装位置 | 配置 |
| --- | --- | --- | --- |
| v2 | `opencode-plugins-v2.tar.gz` | `v2/` 目录包：server `index.js`、TUI `tui.js` | `plugins` 登记目录，界面用 `cli.json` |

仅发布 `opencode-plugins-v2.tar.gz`；旧 V1 文件保留用于识别与迁移，不再发布新版 V1 资产。

- `later`：共用 Agent 工具逻辑；v1/v2 各有 TUI 适配。输入框排程与 Agent 工具排程独立，分别随 TUI／服务端进程退出清除。
- `context_rewrite`：共用 `context-rewrite/core.mjs`、`output-store.mjs`，分别适配两代工具与消息 API；包含近期纠错、持久外置和全文取回。
- `claude-mem`：由官方安装器维护 `$CFG/plugins/claude-mem.js`，bundle 自带 OpenCode v1 `server` 与 v2 `setup` 入口；setup 在配置合并之后调用官方安装器更新 runtime／入口／MCP，OpenCode 负责加载。安装器停止共享 worker；已有 settings 原样恢复，之后手工重启 worker。
- v2 额外适配旧工具 API、会话事件与请求亲和性；不要求目标机编译。

工具用法见 [上下文插件](../context-rewrite/README.md)，v2 文件与配置见 [v2 说明](v2/README.md)。

### 外部插件

| 对象 | setup 行为 |
| --- | --- |
| Ponytail | 查询本地版本与 npm latest；有新版时默认询问刷新，确认后备份移走对应缓存并登记官方 `@latest`，下次宿主启动下载；不运行宿主 plugin CLI |
| Magic Context | 默认登记官方 `@latest`；旧缓存路径在可复用当前包时自动迁回包名。实际刷新另问，默认 N；确认后移走 latest 缓存，下次宿主启动下载 |
| context-mode | 独立从 `releases/latest` 同步，放 `vendor/context-mode/`，不另加配置插件登记 |
| notify | 旧入口备份停用，后续由 notify 项目适配 |

版本检查与刷新：

- 只检查套件引用的 Ponytail、Magic Context：按配置与当前宿主缓存读取本地实际版本，联网查询官方 npm `latest`。不扫描或更新用户自行安装的其他包。
- Ponytail 稳定版有新版时询问，普通 npm／`@latest` 登记默认 Y；钉版或本地路径默认 N。版本一致不重装，本地更高不降级；非稳定版本只提示人工核对。缺包交宿主安装，已有缓存但版本未知可询问刷新。
- 确认 Ponytail 刷新后，只备份移走其 `@latest` 缓存到 `.agent-skills-backups/<时间戳>/ponytail-cache/`，登记改为官方 `@latest`，保留 options。钉版缓存和任意本地源码目录不删除。
- 查询失败：显示 WARN，不据此刷新；`--check` 不询问。`-y`／无终端采用各项默认值，Ponytail 普通登记可刷新，钉版／本地路径及 Magic Context 跳过。
- 此时仅**安排更新**；下载与加载发生在下次宿主启动。日常仍可用 OpenCode v2 `/plugins` 更新，不必每次运行 setup；版本一致不等于加载正常，npm latest 也不保证兼容任意旧宿主。

Magic Context 操作：

- **选 Y**：确认 OpenCode／Desktop／Pi 均已停用、共享库已备份。只将 OpenCode 两代布局中的 Magic Context `@latest` 缓存移到 `$CFG/.agent-skills-backups/<时间戳>/magic-context-cache/`；旧目录／钉版登记改为官方 npm `@latest`，保留插件 options。不删除任意本地源码目录、Pi 包、其他插件缓存或数据库。
- OpenCode v2 的 npm cache 可能把 `@latest` 做成指向数字代次目录的符号链接；用户配置的 `$XDG_CACHE_HOME`（未设置时 `$HOME/.cache`）本身也可以是符号链接。刷新时只移动受管 `@latest` 叶子链接本身，不跟随目标目录；npm、scope、包目录等中间父路径仍受符号链接保护。
- **选 N／`-y`／无终端**：不刷新缓存。旧缓存路径仍指向当前宿主可复用的官方包时，自动改为 `@cortexkit/opencode-magic-context@latest`，保留 options，写入前备份配置。失效路径、旧缓存代次或跨主版本缓存不可直接复用时，保留登记并 WARN；不借迁移之名下载新版。
- **`--check`**：预览登记迁移与 WARN，不询问、不写入、不刷新。通过仅表示套装可部署，不代表 Magic Context 已可用。
- 现有 npm 包名、精确版本和自定义源码路径保持原样，不再把包名改成本地缓存路径。新安装登记官方 `@latest`；已有共享库而当前宿主无 latest 缓存时，未确认刷新就不新增入口。
- 日常更新由 OpenCode v2 `/plugins` 的 `Ctrl+U` 或 `opencode plugin update @cortexkit/opencode-magic-context@latest` 管理（目标须与配置一致）。v2 启动复用已有缓存、检查更新，不自动替换已装包；缺包仍会下载，更新前须协调 Pi 并备份共享库。

刷新后由宿主 loader 下载包、由 Magic Context 自己处理数据库迁移；setup 不运行它们。同机 Pi 的 Magic Context 需另行同步升级。Ponytail 仍使用官方双入口包，缺包由宿主下载。

## 旧插件迁移与备份

默认安装与 `--plugins-only` 使用同一个部署器。既能更新旧散装插件，也能从旧分版本包升级；无需先手工删除。

| 情况 | 处理 |
| --- | --- |
| 旧散装／旧 v1 包 → v2 | 部署 `v2/`，登记 `plugins`，停用旧 server／TUI 入口及内置 Ponytail 配置；claude-mem 使用官方 v2 `setup` |
| 同版本重跑 | 内容相同不重写、不重复注册，不产生无变化备份 |
| V1 宿主运行当前 setup | 停止，不写入配置；先升级宿主 |

- 管理固定安装路径；不按文件名子串删除用户插件。未知第三方登记保留，兼容性仍需自行确认。
- v1→v2 退役：旧 wrapper／later／纠错、`plugins/zz-agent-skills.js`、`tui-plugins/later/`、`context-rewrite/`、旧 context-mode 入口与目录、notify、旧请求头插件。
- 插件资产备份到 `$CFG/.agent-skills-backups/<时间戳>/<原相对路径>`；同时移走 `plugins/context-mode.bak-*` 遗留目录，避免被 v2 再次扫描。配置文件保留相邻 `.bak*` 备份。
- 先把旧字段转为原生 V2，再在线获取模板。完整安装刷新 `providers.<名称>.models`；已有 provider 的 `settings`、headers、私密值等本地字段保留，本地独有 provider 保留。精简插件模式仅转换格式。
- `opencode.jsonc` 合并到 `opencode.json` 后备份退役。v2 已有 `cli.json` 时保留；没有时合并旧 `tui.json(c)` 为 `tui.json`，由宿主首启迁移 action、界面与 state。完整安装的按键设置另行确认。
- 除确认的 Ponytail／Magic Context 缓存刷新外，不清理 npm 插件缓存；认证、会话库与外置正文不动。**插件备份不是整机快照，也不替代数据库备份。**

自维护发布包校验失败、未知宿主版本、配置无法解析或存在转换冲突时停止。`opencode.json` 支持写穿符号链接并保留链接；其他安装路径仍受链接保护。用户指定的缓存根可为符号链接，v2 npm cache 的 `@latest` 叶子链接仅在确认刷新时整体移走。Magic Context 兼容性问题以 WARN 和独立刷新询问处理。

### 临时 deprecated 迁移

`config-v2-native`（1.0.21 起）：发布包内置官方 `@opencode/core` 2.2.3 归一化器，目标机用 Bun 执行，无需安装 npm 依赖。完整安装与 `--plugins-only` 均先转换 `opencode.json(c)`；`--check` 仅预览。转换在本机完成，不上传配置；保留凭据、环境变量／文件引用、权限顺序，已被宿主忽略的字段会提示后清理。改前相邻备份 `.bak-v2-*`，注释留在备份；无变化不写入。官方 claude-mem 安装器写入旧 MCP 字段后，再归一化一次。

`mc-cache-entry`（1.0.15 起）：`deploy.py` 将旧部署器写入的 Magic Context `@latest` 缓存目录迁回官方包名。只处理受管缓存根内的标准包路径，且必须与当前宿主缓存解析结果一致；保留缓存和 options，配置沿用相邻备份。自定义源码路径、npm 精确版本不自动接管。完整安装与 `--plugins-only` 执行，`--check` 只预览；重复运行不再改回 Local。退役时删除标记块及本段，不恢复旧路径冻结逻辑。

`mcphub-web-rename`：两个 setup 共用根目录 `migrate-web-mcp.py`，在模板合并前把旧 MCP 服务名改为 `web`。OpenCode 检查 `opencode.json`／`opencode.jsonc` 的 `mcp` 与 `mcp.servers`；完整安装和 `--plugins-only` 执行，`--check` 只预览。改前相邻备份 `.bak-web-*`，连接地址、凭据、禁用状态不变。两名并存且实值冲突时保留、WARN、跳过主配置模板合并，其他插件继续。退役时删除脚本、两个调用段及对应临时检查。

`claude-mem-legacy` 标记对应短期过渡，不是长期历史兼容：旧 wrapper／lib 文件备份退役；旧受管 MCP 登记交官方安装器刷新。自定义命令／环境变量／禁用项保留，告警并跳过此次 claude-mem 官方更新。安装失败恢复本次安装前的 OpenCode 配置和插件，不回滚已经更新的 runtime；官方非致命 WARN 仍需按输出处理。

迁移期约一周，最终由维护者明确决定何时删除，不自动到期。退役时一并删迁移分支及过时说明，保留备份，不为旧布局继续加兼容。

## 升级、共存与回退

1. 停止旧 TUI 和后台服务，保存配置、认证、state 与一致的会话数据库备份
2. 升级 OpenCode 二进制，再执行 setup 预检和插件同步
3. 启动新版，由 OpenCode 自己迁移会话库与 CLI 配置；首次 npm 包安装需要网络

Magic Context 的共享 `context.db` 由它自己的版本和迁移机制管理；升级须安排所有使用宿主均停用的窗口，可用宿主包更新命令或 setup 的独立刷新询问。恢复包名登记仅复用当前缓存，不等于授权升级 Magic Context。

v1/v2 可以并存二进制，但并行运行须隔离配置、数据、state、cache；Magic Context 存储也需按用途隔离。回退前保留升级后的新增数据，再恢复对应备份；只换旧二进制、只恢复插件目录都不是完整回退。

## 验证范围

历史验收基线为 Linux v1 1.18.35／v2 2.0.26。当前配置转换基于官方 **2.2.3**：预览、私密值与引用保留、权限顺序、混合 MCP、备份、幂等、冲突停止和符号链接写穿均有检查；模板通过官方 schema 校验。

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
