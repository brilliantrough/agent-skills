# UI Taste Lab · 可运行组件参考

直接用浏览器打开 [index.html](index.html)。原生 HTML/CSS/JS，无构建、无服务器、无在线字体或接口请求。

- 七套主题：shadcn-neutral、modern-saas、bespoke、bento、swiss、aurora-glass、soft-ui
- 两个对照：旧 baseline、layered 阴影技法；不加入正式风格选项
- 默认 shadcn-neutral；顶部选择器或左右按钮切换，保留当前筛选与演示记录
- 全部指标为固定演示数据；新建记录、队列顺序与表单只保留在本次页面中，刷新恢复
- 这是视觉与交互参考，新版各主题细节仍待用户目验；不是完整业务应用，也不覆盖 S04 的汇总、下钻与持久化

## Agent 读取顺序

1. 先读 [主题规则](../../themes/README.md)，确认目标主题；已有项目沿用其组件体系
2. 读本页索引，按组件定位 `base.css`、`lab.js` 与 `themes/<主题>.css`；只读相关片段
3. 提取需要的语义 tokens、DOM 比例与状态处理，接入项目的真实数据和框架
4. 在目标页面复验 hover/focus、禁用、空态、菜单贴边、键盘与窄屏；本演示通过不代表目标页面通过

React 项目需要 shadcn 时采用官方组件。此处 `shadcn-neutral` 是原生实现的风格参考，未打包 shadcn React 源码；不要整页拷贝演示工作台或为复用示例迁移框架。

## 组件 → 源码

| 组件 | `base.css` 定位 | `lab.js` 定位 / 页面入口 |
| --- | --- | --- |
| 导航、节点切换、搜索 | `.side`、`.nav-item`、`.seg`、`.search` | 页面骨架、`SERVERS`、`runSearch` |
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

## Token 约定

| 用途 | 变量 |
| --- | --- |
| 表面、正文、边界 | `--canvas`、`--panel`、`--control`、`--text`、`--text-2`、`--border` |
| 主操作 | `--accent`、`--accent-hover`、`--accent-fg`；此处 accent 对应主操作，不是 shadcn 同名的轻选中表面 |
| 选中、hover、焦点 | `--selected`、`--hover-bg`、`--focus-ring` |
| 状态 | `--ok/warn/bad` 及各自 `-bg`、`-fg`；图表另用 `--c1`…`--c5` |
| 比例与质感 | `--font`、`--r-sm/md/lg`、`--sh-1/2/pop`、`--pad`、`--gap`、`--t-fast/med` |

`base.css` 管共用结构；每个主题 CSS 包含完整变量及少量控件覆盖。产品默认只取所选主题，切换器仅留在有明确多主题需求的页面。

## 素材与维护

- `fonts/`：Inter、Nunito、IBM Plex Sans 拉丁字形 + Noto Sans SC（思源黑体）中文变量切片；切片按 unicode-range 随用随取，浏览器只下载页面用到的字集
- `icons.js`：Lucide 操作图标子集；`brands.js`：Simple Icons 四个品牌 SVG
- [SOURCES.md](SOURCES.md)：来源、版本、许可证与参考范围；更新素材时同步 `licenses/`
- 本目录是唯一维护源，随整个 skill 分发；仓库外的旧实验室入口只负责跳转
