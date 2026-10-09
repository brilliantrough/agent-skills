# OpenCode v2 适配

已在 OpenCode **2.0.26** 验证；通过 `opencode-setup.sh` 自动选择 v2 预构建包。v1 使用独立资产，两端复用公共逻辑，不是同一双入口自维护包；Pi 入口不在此包中。

正常安装、旧散装／v1 迁移均走 [统一 setup](../README.md#安装与更新)，不手工删旧入口。`--plugins-only` 更新插件和 context-mode 自带 skills；新机器需要通用 skills、claude-mem 资产与环境配置时，运行完整 setup。

| 文件 | 职责 |
| --- | --- |
| `index.js` | 注册 v2 服务端能力，并清理注册资源；Ponytail 由官方包原生加载 |
| `legacy-tools.js` | 复用已安装的 context-mode、claude-mem、later 实现，转换 v2 工具与会话事件 |
| `request-affinity.js` | 会话级缓存键、sticky session 请求头 |
| `context-rewrite.js` | 近期纠错、持久外置、显式全文取回；复用 `context-rewrite/` 核心 |
| `tui.js` | 目录包的 TUI 入口，转发到 `later-cli.js`，由 CLI 自动发现 |
| `later-cli.js` | TUI 输入 `later 5h 检查结果`、`later list`、`later cancel all`，以及 `/later` |

Magic Context 使用其自身的 v2 入口，要求已装版本至少 **0.45**；本包须在它之后加载。版本不明或过旧时 setup 停止，不自动升级共享库。notify 不包含在本包中，旧入口备份停用。上下文纠错复用 [acp-kernel](https://github.com/ranxianglei/acp-kernel) 0.0.101；部署须附带 `context-rewrite/ACP-KERNEL-LICENSE`，保留许可证及出处标注。

## 构建和部署

统一构建／发布命令见 [分发说明](../README.md)。配置目录的 `v2/` 是目录包，须在 `opencode.json` 的 `plugins` 中登记**目录**，不是 `index.js`：

```json
{
  "plugins": [
    "<已安装且支持 v2 的 Magic Context 包目录>",
    "@dietrichgebert/ponytail",
    {"package": "<配置目录>/v2"}
  ]
}
```

运行依赖：

- 配置目录：`OPENCODE_CONFIG_DIR`，否则 `$XDG_CONFIG_HOME/opencode` 或 `~/.config/opencode`。
- `vendor/context-mode/`：独立 release 产物，由适配层调用；不把旧 hooks 再登记给宿主。
- `lib/claude-mem.js`：已有上游 bundle；不存在时跳过采集 hook，其余工具仍可使用。
- 旧工具 schema、wrapper、later 已打进 bundle；不再依赖 `legacy-v1/` 或目标机 `node_modules/@opencode-ai/plugin`。
- `v2/` 目录包：本仓自维护能力；官方 Ponytail 单独由 `@dietrichgebert/ponytail` 提供，不能再把 `v2/ponytail/` 或 `options.ponytailPackage` 加入配置。

Ponytail 缺包由宿主启动时自动下载；setup 只登记，不手填缓存或调用 `opencode plugin add`。保留已有 Magic Context 的版本／目录登记，不把上面占位示例整体覆盖到现有配置。

setup 将本套件旧入口移入 `$CFG/.agent-skills-backups/<时间戳>/`，避免与 `plugins/` 自动发现重复；不删除会话库、认证或外置文件。CLI 自动发现本包的 `tui.js`，不要在 `cli.json` 中再登记旧 `tui-plugins/later`。主题、快捷键使用 `cli.json`；完整 setup 可确认更新按键，插件模式不统一按键。首次从旧 TUI 配置接入时，setup 准备 `tui.json`，由宿主首启迁移 UI 和 state。

宿主升级前先停进程、备份，再升级二进制并运行 setup；会话数据库迁移由 OpenCode 正常启动完成。Magic Context 的共享库升级是另一项维护任务。

输入框排程与 Agent 工具排程独立，分别查询／取消。本包的 TUI 定时器随 TUI 退出清除；Agent 工具定时器随服务端退出清除。关闭 TUI 不一定会停止 v2 后台服务。

## 输出与会话

- 普通文本默认 ≥16 KiB 外置；环境变量和 Agent 用法见 [`context-rewrite/README.md`](../../context-rewrite/README.md)。
- Shell 进度中的 `shellID` 保留到结果元数据，再复制该进程的原生输出文件；退出码和其他元数据不变。
- `context_output_read(full=true)` 明确标记 `truncated: false`，防止宿主再次截断。
- codemode 子调用保留原数据，最终结果才外置；两个上下文控制工具只能直接调用。
- v2 纠错通过 `session.context` 读取当前宿主上下文、重建调用索引，随后只过滤本轮发送视图；不删除原始记录，也不重建 MC 已经隐藏的消息。
- 旧结果不追溯外置。外置文件持久保留，迁移会话时一并迁移。
