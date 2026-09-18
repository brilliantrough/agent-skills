# Agent Skills UI

本仓库维护的个性化 Pi UI；唯一入口 `index.ts`，命令 `/ui`（`Alt+A`），侧栏 `/ui sidebar`。

- `atelier/`：采用 Pi Atelier 0.10.1 的全屏分栏、菜单、页脚与面板协议；不运行其原生编辑器。
- `editor/`：采用 Zentui 0.24.0 编辑器和用户消息渲染所需的源码闭包，不加载其扩展入口、页脚、轮询或命令。
- `composer.ts`：统一编辑器入口，原生 CustomEditor + LF 提交修复 + WrappedPolishedEditor。
- `panels.ts`：缓存详情及 Magic Context `todowrite` 的当前分支成功快照（无第二套 TODO 存储）；优先进行中/待办，全部结束只显示摘要，完整列表用 `/todos`。
- Context 面板同时保留 Pi 上下文占比及 MC 发布的原始压力/历史整理状态；MC 指标不从模型窗口猜算，也不依赖页脚剩余宽度。
- 全屏侧栏使用独立、非 primary 的原生 `ScrollView`：普通鼠标拖选/复制限定在起始面板，跨过分界线不混入另一栏；键盘滚动与搜索仍以正文为主。Shift 强制终端选择和 regular 模式仍由终端控制。
- `tps.ts`：每秒最多更新一次的估算 TPS，结束后显示最后一次回复 usage 的平均速度。

配置：共享 `~/.config/cortexkit/magic-context.jsonc` 的 `todowrite.overlay: false` 只关闭 MC 的重复任务 widget，保留工具和持久化（dot_file 模板已同步）。

UI 配置：`~/.pi/agent/agent-skills-ui.json`（布局/侧栏），`agent-skills-editor.json`（编辑器/消息视觉）。均尊重 `PI_CODING_AGENT_DIR`。可信项目可用 `.pi/agent-skills-ui.json` 覆盖布局。已迁移旧配置时优先保留用户值。

页脚 `in/out` 与侧栏缓存按全会话 assistant usage 统计；`HΣ` 为 sum(cacheRead)/sum(input+cacheRead+cacheWrite)，`H₁` 为最近有效请求比例，各一位小数。`R/W` 为累计缓存读取/写入；首 token 等待和工具时间不计入 TPS。

## 来源与许可证

- https://github.com/michaelmjhhhh/pi-atelier ，npm `pi-atelier@0.10.1`，MIT，见 `atelier/LICENSE`。
- https://github.com/lmilojevicc/pi-zentui ，npm `pi-zentui@0.24.0`，MIT，见 `editor/LICENSE`。

这些是维护在仓库内的修改版源码，不依赖安装对应 npm 包；保留内部上游命名与协议以便追踪修复。初次纳管保留必要依赖闭包，不把源码迁移与全面重写混在一起。Pi 0.85.1 上验证；分栏依赖宿主布局 API，更新宿主时检查主消息复制、窄窗、弹框、输入及 reload。

## 迁移

`python3 pi/migrate-ui.py --agent-dir ~/.pi/agent` 仅预览；加 `--apply` 才备份并迁移。先确保本仓库 UI 已部署到 Pi git 包。只移走本项目已知散装文件（哈希匹配），停用两个旧 UI 包及本机 atelier-bridge，不删除 npm 包或用户旧配置。未知文件变体中止迁移，不冒险覆盖。

迁移会打印备份目录；回退前先停用包内 `pi/extensions/ui/index.ts`，再恢复备份的 settings 和散装文件，不能同时加载两套 UI。
