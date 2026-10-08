# UI Taste Lab · 可运行组件参考

直接用浏览器打开 [index.html](index.html)。原生 HTML/CSS/JS，无构建、无服务器、无在线字体或接口请求。

- 八套主题：shadcn-neutral、**paper-cream（暖白纸面）**、modern-saas、bespoke、bento、swiss、aurora-glass、soft-ui
- 两个对照：旧 baseline、layered 阴影技法；不加入正式风格选项
- [structures.html](structures.html)：四种**工作型结构样本**，可叠加切主题；不是全部设计形式
- [design-exploration.html](design-exploration.html)：新增内容驱动的构图/动效候选，中性与米色对比；静态正文始终可读，无外部请求
- 页面骨架为 inset：页面底用 `--canvas`，侧栏单独用 `--side-bg`，内容区是白色圆角面板（`.main`）；侧栏无 `border-right`，右缘一条上下淡出的 1px 竖线，窄屏隐藏侧栏
- 两页默认 shadcn-neutral；顶部选择器或左右按钮切换，保留当前筛选与演示记录
- 全部指标为固定演示数据；新建记录、队列顺序与表单只保留在本次页面中，刷新恢复
- 这是视觉与交互参考，新版各主题细节仍待用户目验；不是完整业务应用，也不覆盖 S04 的汇总、下钻与持久化

## Agent 读取顺序

1. 先按 [主流程](../../SKILL.md) 判断任务目的与形式，再确认视觉语言；这些 HTML 是方法样本，不是整页模板
2. 读本页索引，按组件定位 `base.css`、`lab.js` 与 `themes/<主题>.css`；只读相关片段
3. 提取需要的语义 tokens、DOM 比例与状态处理，接入项目的真实数据和框架
4. 在目标页面复验 hover/focus、禁用、空态、菜单贴边、键盘与窄屏；本演示通过不代表目标页面通过

React 项目需要 shadcn 时采用官方组件。此处 `shadcn-neutral` 是原生实现的风格参考，未打包 shadcn React 源码；不要整页拷贝演示工作台或为复用示例迁移框架。

## 组件 → 源码

| 组件 | `base.css` 定位 | `lab.js` 定位 / 页面入口 |
| --- | --- | --- |
| 导航、分组标题、节点切换、搜索 | `.side`、`.nav-group`、`.nav-label`、`.nav-item`、`.seg`、`.search` | 页面骨架、`SERVERS`、`runSearch` |
| 交互动效、短反馈、弹层与展开 | `.motion-preview`、`dialog`、`.msel-pop`、`.toast` | [体验入口](index.html#motion)、`common.js` 的 `revealChange`；两页共用 `THEMES` |
| 主/次/描边/轻/危险按钮、加载态 | `.btn` 及其变体 | Component specimens、`samplePrimary` |
| 字段、错误、禁用、键盘焦点 | `.fld`、`.inp`、`:focus-visible` | `invalidSample`、原生 `dialog` |
| 数据集多选、搜索、移除筛选 | `.msel`、`.filter-tag` | `closeMenu`、`updateDatasets`、`filteredRows` |
| 表格、空态、CSV 导出 | `.tbl`、`.table-wrap`、`.empty-cell` | `renderTable`、`exportBtn` |
| 折线焦点、图例与 tooltip 联动 | `.series`、`.legend-chip`、`.tip-row` | `setFocus`、`pointAt`、`toggleLock`、`placeTip` |
| 状态灯带 | `.strip`、`.seg.ok/warn/bad` | `STRIP`、`stripIndex` |
| 拖拽与键盘排序替代 | `.sort-item`、`.handle`、`.queue-tools` | `RUNS`、`data-move`、`dragEl` |
| 24 小时时间选择 | `.timepick` | `tpH`、`tpM`；本例编辑已有 `03:00`，新增空值语义见 patterns.md §7 |
| 预览卡片、摘要卡、详情 | `.card`、`.summary-card`、`.summary-ring` | `cards`、`batchDetail`、`showDetail` |
| 身份/状态/筛选三类标签 | `.identity`、`.badge`、`.filter-tag` | `brand`、`sampleTags` |
| 排版、数字、Radix 色阶 | `.type-sample`、`.type-numbers`、`.swatches` | `GRAY`、`BLUE`、`designSamples` |

折线图可悬浮聚焦、点击锁定、再点解除、切换锁定；图外点击或 Esc 清除。键盘左右选时间、上下选系列、Enter 锁定；图例控制系列可见性。这里用小型确定性 SVG 展示交互，业务图表优先复用项目图表库，再接入 T05 的统一焦点。

结构页筛选真实作用于演示记录；数据集也控制曲线可见性，时间和搜索不改固定趋势。点运行更新完整详情，窄屏可由表格选对象，详情在下方；无匹配时可恢复。

## 设计探索：内容 → 构图 → 交互

`design-exploration.html` / `.css` / `.js` 共用已有字体、主题、基础控件与 `common.js` 的短反馈，不新增库。固定演示快照：等待18、运行8、完成6；不声称性能或堵塞原因。

| 入口 | 设计作用 | 实现与边界 |
| --- | --- | --- |
| 非对称开篇 | 先建立主角与问题，读数支持论点 | `.hero`；静态构图，无循环装饰 |
| 列表 ↔ 流程 | 同对象在两种表示中保持连续 | `.queue-items`、`button[data-view]`；360ms 位置过渡，真实更新布局与选中态 |
| 自然滚动章节 | 一个主题，按过程换焦点 | `.story-scene`、`showScene`；IntersectionObserver 更新固定示意，无滚轮劫持 |
| 查看所选阶段 | 局部操作到完整详情 | 原生 `dialog`；Esc、焦点返回，明确不是提交 |
| 中性 / 米色 | 对比表面与内容形式的独立作用 | `themeSelect`；保持内容、对象与阅读顺序 |

减少动态效果时即时切换；700px 以下过程示意不固定，正文自然排列。可关闭 JavaScript 读正文与数据；交互不可用有明确提示。全部新构图为 Candidate，需实际目验后记录范围。

## Token 约定

| 用途 | 变量 |
| --- | --- |
| 表面、正文、边界 | `--canvas`、`--panel`、`--control`、`--text`、`--text-2`、`--border` |
| 骨架 | `--side-bg`（仅侧栏；主区不从此变量借色）、`--side-w`（侧栏列宽，默认 288px）、`--side-line`（右缘分隔线色，默认 `--border`） |
| 主操作 | `--accent`、`--accent-button`（可选的高对比按钮色）、`--accent-hover`、`--accent-fg`；此处 accent 对应主操作，不是 shadcn 同名的轻选中表面 |
| 选中、hover、焦点 | `--selected`、`--hover-bg`、`--focus-ring` |
| 状态 | `--ok/warn/bad` 及各自 `-bg`、`-fg`；图表另用 `--c1`…`--c5` |
| 比例与质感 | `--font`、`--font-display`（展示标题字体，仅部分主题使用）、`--r-sm/md/lg`、`--sh-1/2/pop`、`--pad`、`--gap`、`--t-fast/med` |

`base.css` 管共用结构；每个主题 CSS 包含完整变量及少量控件覆盖。产品默认只取所选主题，切换器仅留在有明确多主题需求的页面。

## 素材与维护

- `fonts/`：Inter、Nunito、IBM Plex Sans 拉丁字形 + Noto Sans SC（思源黑体）与 Noto Serif SC（思源宋体）中文变量切片；切片按 unicode-range 随用随取，浏览器只下载页面用到的字集。宋体切片只服务 paper-cream 的展示标题
- `icons.js`：Lucide 操作图标子集；`brands.js`：Simple Icons 四个品牌 SVG
- [SOURCES.md](SOURCES.md)：来源、版本、许可证与参考范围；更新素材时同步 `licenses/`
- 本目录是唯一维护源，随整个 skill 分发；仓库外的旧实验室入口只负责跳转
