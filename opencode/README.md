# OpenCode 插件分发

先安装 OpenCode，再运行仓库根 `opencode-setup.sh`；脚本只读取 `opencode --version`，不升级宿主、不迁移数据库。无客户端、未知主版本或下载失败时停止，不猜版本。

```bash
bash opencode-setup.sh --check         # 查询目标包、管理路径、待退役项；不改本机配置
bash opencode-setup.sh --plugins-only  # 同步插件与 context-mode skills，不更新模型／Python／通用 skills
bash opencode-setup.sh                # 完整安装，同样包含插件同步
```

升级前退出 OpenCode（含后台服务），先完成宿主升级，再运行上述同步命令；无需手工删除旧插件。`--check` 和 `--plugins-only` 需要已安装 Python 3、curl，前者仍会联网下载并校验发布包。

| 客户端 | 资产 | 安装位置与登记 |
| --- | --- | --- |
| v1 | `opencode-plugins-v1.tar.gz` | `plugins/zz-agent-skills.js`、`tui-plugins/later/`；`plugin`、`tui.json(c)` |
| v2 | `opencode-plugins-v2.tar.gz` | `v2/` 目录包；官方 Ponytail 单独安装；`plugins`、`cli.json` |

包内含近期纠错、大输出外置／全文取回、later、claude-mem wrapper；v2 另含旧工具 API 适配和请求亲和性设置。Ponytail 不复制进包，直接使用官方同一包的 v1/v2 双入口。工具用法见 [上下文插件](../context-rewrite/README.md)，v2 接口见 [v2 说明](v2/README.md)。

## 配置与依赖

- `OPENCODE_CONFIG_DIR` 优先，否则 `$XDG_CONFIG_HOME/opencode` 或 `~/.config/opencode`。
- 只替换本套件管理的入口；变化前备份，内容相同不重写。旧 wrapper／later／纠错入口停用，避免重复注册。
- v1 → v2：统一处理旧散装 wrapper／later／纠错入口和旧分版本包，配置切到 v2 `plugins`；旧 `tui-plugins/later/`、`context-rewrite/`、`plugins/context-mode/` 退役。现有 `cli.json` 保留；没有时准备 `tui.json`，由宿主首启迁移。
- 插件备份：`$CFG/.agent-skills-backups/<时间戳>/<原相对路径>`；移走 `plugins/context-mode.bak-*` 遗留目录，避免被 v2 自动发现。配置文件仍留相邻时间戳备份；回退插件不等于回退宿主数据库。
- 仅回收本套件固定安装路径，不按文件名子串删除用户自定义插件。Magic Context、Ponytail 缓存、会话库、认证及外置正文不删除；v1 检测到 v2 配置会停止，不自动降级。
- 官方 Ponytail：setup 只登记配置；OpenCode v1/v2 启动时由各自官方插件 loader 安装缺失包。已有包不由 setup 升级；setup 不调用宿主 plugin CLI、不清缓存、不启动服务、不迁移数据库。
- API key、URL、provider options、MCP 与其他本地字段保留。通用模型模板更新 v1 `provider` 结构；已有 v2 原生 `providers` 保持原样，不混写或猜测字段转换。
- context-mode 继续独立从 `releases/latest` 下载：v1 放 `plugins/context-mode/`；v2 放 `vendor/context-mode/`，不再放 v1 自动入口。
- Magic Context 保留已配置版本；v2 至少需要 0.45。已有 `@latest` 时定位已安装包；无法定位则提示先固定版本，不擅自升级共享数据库。新安装优先沿用已有 OpenCode／Pi 版本；没有已装版本和共享库时才固定用 0.45.0。
- claude-mem bundle 留在配置目录 `lib/claude-mem.js`，缺失则不注册采集 hook；其 MCP 与 worker 仍独立配置。
- v2 未有 `cli.json` 时：把旧 `tui.json(c)` 合并到 `tui.json`，原 JSONC 备份；首启由宿主迁移快捷键和旧 state。已有 `cli.json` 则保留。
- notify：仅 v1 安装；v2 停用旧入口，后续在 notify 项目适配。

v1、v2 不能仅换二进制就安全共用数据；并行运行须隔离配置、数据、state、cache。宿主升级／数据库迁移不属于本脚本。

## 构建与发布

开发机需要 Node/npm、Bun、GNU tar、gh；目标机不编译插件。

```bash
npm ci --prefix context-rewrite --ignore-scripts
npm ci --prefix opencode --ignore-scripts
bun opencode/release.mjs
```

产物：`opencode/dist/`；每包有文件哈希清单和部署器。固定源码版本、按主版本打包；`dist/` 不入 git。

发新版：同步修改 `opencode/package.json` 的 `version` 与根脚本 `OC_RELEASE=opencode-plugins-<版本>`，更新 lock，再构建、实机验收。提交所需源码后：

```bash
git tag opencode-plugins-<版本>
git push origin opencode-plugins-<版本>
bun opencode/release.mjs --publish
git push origin main
```

先发布资产，再推送引用它的 setup；发布使用 `--latest=false`，不抢占 context-mode 的 latest。已发布版本不覆盖，改动另升版本。

## 许可证

局部吸收与编号使用 [ranxianglei/acp-kernel](https://github.com/ranxianglei/acp-kernel) 0.0.101；相关项目 [billion-context](https://github.com/ranxianglei/billion-context)。保留 [ACP-KERNEL-LICENSE](../context-rewrite/ACP-KERNEL-LICENSE) 的许可证及出处标注要求。包内另附 OpenCode／Zod 许可证。
