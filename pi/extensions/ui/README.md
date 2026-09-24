# Agent Skills UI

本仓库维护的个性化 Pi UI；唯一入口 `index.ts`，命令 `/ui`（`Alt+A`），侧栏 `/ui sidebar`。

- `atelier/`：采用 Pi Atelier 0.10.1 的全屏分栏、菜单、页脚与面板协议；不运行其原生编辑器。
- `editor/`：采用 Zentui 0.24.0 编辑器和用户消息渲染所需的源码闭包，不加载其扩展入口、页脚、轮询或命令。
- `composer.ts`：统一编辑器入口，原生 CustomEditor + LF 提交修复 + WrappedPolishedEditor。
- `panels.ts`：缓存详情及 Magic Context `todowrite` 的当前分支成功快照（无第二套 TODO 存储）；优先进行中/待办，全部结束只显示摘要，完整列表用 `/todos`。
- Context 面板同时保留 Pi 上下文占比及 MC 发布的原始压力/历史整理状态；MC 指标不从模型窗口猜算，也不依赖页脚剩余宽度。
- 全屏侧栏使用独立、非 primary 的原生 `ScrollView`：普通鼠标拖选/复制限定在起始面板，跨过分界线不混入另一栏；键盘滚动与搜索仍以正文为主。Shift 强制终端选择和 regular 模式仍由终端控制。
- `wheel.ts`：全屏模式的滚轮步长。Pi 构造渲染器时不传 pi-tui 的 `wheelScrollLines`，所以每个滚轮刻度只滚 1 行（上游 #7765/#8370/#8446/#8471/#8741 都还开着；0.84.0 之前是 3 行）。这里在编辑器和页脚工厂里把这个实例字段设为 `WHEEL_SCROLL_LINES`（默认 3，改这个常量即可调整）；regular 模式无此字段，自动跳过。Alt+滚轮仍是原生 5 倍。
- `sidebar-collapse.ts`：侧栏面板的可交互层。Pi 全屏渲染器会把鼠标事件派发给光标下的组件（`dispatchMouseToLayout` → `handleMouse(event)`，坐标为组件局部坐标，返回 `{ render: true }` 即重绘），侧栏本身就是布局里的普通组件，所以只包一层即可，不动上游布局。两种点击：① 点面板**标题行**折叠/展开整块（状态存 `agent-skills-ui.json` 的 `collapsedPanels` 数组）；② 点 TOOLS 的 `│ 39 / 45 active ▸ │` 行则转发给上游 `/ui sidebar tools` 的同一动作（展开工具名列表）。面板块从渲染结果里的 `╭─ ✦ TITLE ──╮` 边框识别，键取标题首词（`TASKS · 3/3` 这种计数器变化不影响）。`press` 被吞掉以免拖出文本选择，真正的切换在 `click` 上做。
- 侧栏**可滚动**：全屏分栏时侧栏内容不再按面板高度裁剪（`isScrollable` → 用大预算排版，再让外层 `ScrollView` 剪裁），`scrollbar: "auto"` 只在溢出时显示；滚轮由 pi-tui 的 `routeWheel` 按光标位置路由到侧栏自己的 ScrollView。
- `selection.ts`：松开鼠标（copy-on-select）后清掉高亮。Pi 上游是有意保留选中框的（点一下才消失），但框会一直盖在正文/输入框上；这里在 release 处理完成后（剪贴板文本已同步取到）清空选区并重绘。开关：`agent-skills-ui.json` 的 `clearSelectionOnRelease`，**默认 true**；设 false 时不动选区（那种情况下 `hasActiveSelection()` 是 Pi 的 copy 命令唯一依据）。
- `editor/copy-clean.ts`：划词复制清洗。全屏复制的文本来自 pi-tui 的 `getActiveSelectionText()`（按屏幕行取文本、逐行 `join("\n")`），所以输入框/用户消息框行首的 `│ ` 会跟着进剪贴板，输入框里的软折行也被写成硬换行。这里在 `copySelection` 实例字段外面包一层，用渲染时登记的 `screen`↔`clean` 行对去掉装饰，输入框正文再按 `Editor.buildVisualLineMap()` 的逻辑行号把同一逻辑行的相邻行拼回去（拼回时补上行尾被裁掉的空白与折行间隙）。对不上的行原样保留。开关：`agent-skills-ui.json` 的 `cleanCopiedText`，**默认 true**。回归：`node tests/ui-copy-clean.mjs`。
- `tps.ts`：每秒最多更新一次的估算 TPS，结束后显示最后一次回复 usage 的平均速度。

配置：共享 `~/.config/cortexkit/magic-context.jsonc` 的 `todowrite.overlay: false` 只关闭 MC 的重复任务 widget，保留工具和持久化（dot_file 模板已同步）。

UI 配置：`~/.pi/agent/agent-skills-ui.json`（布局/侧栏），`agent-skills-editor.json`（编辑器/消息视觉）。均尊重 `PI_CODING_AGENT_DIR`。可信项目可用 `.pi/agent-skills-ui.json` 覆盖布局。已迁移旧配置时优先保留用户值。

页脚 `in/out` 与侧栏缓存按全会话 assistant usage 统计；`HΣ` 为 sum(cacheRead)/sum(input+cacheRead+cacheWrite)，`H₁` 为最近有效请求比例，各一位小数。`R/W` 为累计缓存读取/写入；首 token 等待和工具时间不计入 TPS。

## 来源与许可证

- https://github.com/michaelmjhhhh/pi-atelier ，npm `pi-atelier@0.10.1`，MIT，见 `atelier/LICENSE`。
- https://github.com/lmilojevicc/pi-zentui ，npm `pi-zentui@0.24.0`，MIT，见 `editor/LICENSE`。

这些是维护在仓库内的修改版源码，不依赖安装对应 npm 包；保留内部上游命名与协议以便追踪修复。初次纳管保留必要依赖闭包，不把源码迁移与全面重写混在一起。Pi 0.85.1 上验证；分栏依赖宿主布局 API，更新宿主时检查主消息复制、窄窗、弹框、输入及 reload。

## 配置部署

不再做一次性迁移：仓库模板就是当前已验证的配置，`pi-setup.sh` 用整文件覆盖写 `~/.pi/agent/{agent-skills-ui.json,agent-skills-editor.json,keybindings.json}`（内容一致则跳过，有差异先存 `.bak`，目标是符号链接则跳过）。`~/.pi/agent/agent-skills-ui.json` 承载布局/侧栏/`clearSelectionOnRelease`，`agent-skills-editor.json` 承载编辑器与页脚视觉。

在本机用 `/ui` 或 `/settings` 改过的东西，**想长期保留就要同步回仓库模板**，否则下次 setup 会覆盖回去。覆盖旧配置后要回退：把 `.bak-<时间戳>` 改回原名，并确认只加载一套 UI（旧 `pi-zentui`/`pi-atelier`/`atelier-bridge` 会被 setup 从 `packages` 里摘掉）。
