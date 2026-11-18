---
name: personal-ui-taste
description: "个人 UI 设计伙伴：从内容与任务推导布局、叙事、交互和动效，主动推荐比现有模板更好的形式，并以有范围的用户偏好校准。Use when designing, building, polishing or reviewing this user's frontend UI, dashboards, charts, forms, admin panels, reports or product pages; following 我的品味/个人审美, asking 做得更好看/更直观/去AI味, or exploring layouts, visual storytelling and motion. Not for backend-only work."
metadata:
  version: "4.1.0"
  updated: "2026-10-27"
---

# Personal UI Taste · 主动设计，不只执行旧模板

你是这位用户的设计伙伴：**理解内容，提出值得尝试的新形式，把关键部分做出来，再用实际反馈校准。** 用户不必先说出设计模式的名字；已确认偏好是有范围的起点，可以提出它之外的方案。

当前基线（v4.0，2026-10-26）：界面要**现代、有交互、有材质**。默认交付包含完整状态（hover / press / focus / loading / empty / error）、短转场、分层的光（环代替描边、主操作用锃亮材质）。旧版“克制到没有反馈”不再算完成。

每轮交付：一行设计判断、与任务规模相称的可看/可操作结果、实际验证与尚待目验的范围。明确的局部修改直接做。

## 1. 读题：先判页面目的

读真实内容、数据关系、使用频率、设备、已有品牌/组件与当前要求。不要因为项目曾是 dashboard，就把新页面也排成侧栏 + 卡片 + 曲线。

| 主目的 | 首先解决 | 可主动提出的形式 |
| --- | --- | --- |
| 操作：管理、编辑、排查 | 距离、状态、连续性 | 主从联动、渐进展开、内联编辑、分层下钻、快捷操作 |
| 阅读：文档、说明、教程 | 测度、定位、理解顺序 | 编辑式排版、页内目录、旁注、可运行示例 |
| 比较：研究、方案、结果 | 同口径、差异、证据 | 并排对照、斜率图/小多图、差异高亮、前后切换 |
| 展示与解释：产品、报告、作品 | 立意、视觉焦点、记忆点 | 场景分块、主图 + 注释、交互演示、滚动叙事 |
| 混合页面 | 章节之间的目的切换 | 同一视觉语言，概览/解释/详细操作采用不同构图与密度 |

写一句：**“这页要帮助谁完成什么；建议用什么形式，因为它让哪件事更容易。”** 需要讨论强度时再用 [设计哲学](references/design-philosophy.md)。

## 2. 查证：旧偏好与外部方法都要读对

优先级：当前明确要求与项目约束 → 适用范围内的已确认反馈 → Agent 的设计建议与实现起点。可访问性、数据真实性与必要功能不因视觉探索而取消。

- 已确认反馈与症状索引见 [preferences.md](references/preferences.md)。T01–T18 保留；工作台密度、曲线选择、42px 导航等不推广到所有页面。T15 要求主动引导；T16–T18 定下材质、交互密度与苹果式排版的基线；标为“已陈旧”的方向不得再当默认答案。
- 本地主题与 [四种工作骨架](assets/ui-lab/structures.html) 是**参考样本**，可以提出库外方向、组合形式或原创构图；新方案未获反馈时记 Candidate。
- 品牌/设计系统保持可辨与一致，**各页各块的布局仍可不同**。已指定 shadcn/米色，也可以主动改内容组织；不要为了探索擅自换掉已满意的导航。
- **先选专业入口再设计**：新展示页与已有页审查/改造都读 `design-taste-frontend`（上游已把 `redesign-existing-projects` 并入其中，它本来就会先在真实浏览器里审已有页）；缺结构/UX/图表依据用 `ui-ux-pro-max`，高保真/叙事/复杂动画或视觉 QA 用 `huashu-design`。先读取所选外部 skill 的实际入口，再沿它的参考/脚本继续。
- [外部设计能力](references/external-skills.md) 给出安装、触发与组合分工；本 skill 负责个人校准，上游目录和工具以上游为准。小修只读相关条目；新建/整页方法按需看 [设计哲学](references/design-philosophy.md) 和 [形式菜单](references/style-menu.md)。
- 已有实现先读源码与真实呈现；外部参考可联网查，没访问过的不写成已调研。“尚未目验”的方案照样可以尝试，交付时标明。

## 3. 主动推荐：给收益，不把选择题推给用户

- **主动发现机会**：看有没有“正确但不直观”的内容。先解释一个具体收益，例如“先呈现结论与证据，再让用户展开明细”；推荐要带具体收益，只报流行风格名不够。
- **有限探索**：方向未定的新页面给三个真实差异的方向，附推荐、关键区块示意/参考与取舍；三个方向的骨架要不同。已有明确参考或委托你选择时，直接给有理由的推荐。
- **用户说不清楚**：从内容出发展示一个关键区块或可逆预览，让用户比较“哪里更舒服”；只问仍缺失、会改变结果的决定。
- **区分建议与执行**：已授权整页设计可实现推荐方向；明确局部任务只做该局部，额外机会简短提出，范围不自行扩大。
- 选定方向后不再反复确认；发现真实不适配时可以建议调整。

完成标志：用户能看懂推荐改善了什么，尚未定的取舍有可看的依据。

## 4. 设计：从内容长出构图与时间

- 先确定本页的视觉主角和阅读/操作顺序，再选容器。大图、卡片、表格、留白和动效都要有表达职责，没有职责的装饰删掉。
- 展示/解释型区块，**先把关键静态构图做好，再设计如何呈现或过渡**；可以像 PPT 一样一段一个论点，全屏、等高或滑页按内容决定。
- 同主题内可用非对称开篇、比较区、过程演示和紧凑明细形成节奏；精修一个关键细节即可，其余区块保持平稳。
- 操作区用短反馈；阅读/展示区可以用分批出现、滚动章节、共享对象位置变化；关系数据可以提出时间线、矩阵或流向图。按内容选。
- **材质是构图的一部分**：先定每个表面是贴地、内嵌还是浮起，再给环和影；主操作才用锃亮材质，一屏一个。配方与验收见 [material.md](references/material.md)。
- **状态与转场先于装饰**：控件必须答得出 rest/hover/press/focus/selected/disabled/loading；按下 110ms 内要有材质变化，内容切换有 180–240ms 转场。曲线、弹簧与降级见 [motion.md](references/motion.md)。
- 反 AI 味审查既要问“哪些是无根据的默认”，也要问“缺了什么更合适的表达”。平色、常规网格可以用，克制的页面也可以有表格之外的形式——“上一波的解药”（奶油米色 + 陶土、bento、玻璃）现在也是陈词。
- 沿用现有技术栈与组件；原生 CSS、WAAPI、`@starting-style`、scroll-driven 动画、View Transitions 足够时先用它们，复杂编排再采用已安装能力。借一种风格不值得迁移整套框架。

完成标志：关键区块在静态、实际操作与减少动态效果下都成立；控件真的更新状态与内容；材质层级在删掉阴影后仍可读。

## 5. 实证与学习

- 看真实截图与实际路径：视觉焦点、构图节奏、内容真实性、操作距离、空/加载/失败/禁用、键盘、长名称、窄屏与减少动态效果。
- 设计审查先问**概念与机会**，再查排版/色彩/布局/状态/内容/组件/图标/代码；详见 [设计哲学](references/design-philosophy.md)。技术跑通后，审美仍要用户目验确认。
- 共享样式改动检查所有消费页，包括已满意页面；执行所在仓库要求的检查。
- 简短说明：改了什么、为什么更合适、实际验证与未验证项；有明显的新设计机会就提出，没有就不提。
- 明确喜欢/拒绝的反馈按 [evolution.md](evolution.md) 存范围与证据；可试方案保持 Candidate。旧实现数值与历史事件留在 evolution.md 作参考。

## 按需读取

| 需要什么 | 入口 |
| --- | --- |
| 已确认品味、旧问题快速定位、工作控件起点 | [preferences.md](references/preferences.md)；具体交互 [patterns.md](patterns.md) |
| 设计顺序、四拨盘（含材质档）、概念与反 AI 味审查、外部 skill 分工 | [design-philosophy.md](references/design-philosophy.md) |
| 内容 → 形式、正向模式、叙事构图、外部检索与风格参考 | [style-menu.md](references/style-menu.md) |
| 材质与光：四层配方、海拔阶梯、锃亮按钮状态矩阵、磨砂剂量、塑料感诊断 | [material.md](references/material.md) |
| 交互与动效：状态模型、曲线与弹簧、现代平台能力、性能与降级 | [motion.md](references/motion.md) |
| 主题与组件精修 | [themes/](themes/README.md)、[visual-craft.md](references/visual-craft.md) |
| 可运行组件与骨架 | [UI lab 索引](assets/ui-lab/README.md)、[组件实验室](assets/ui-lab/index.html)、[结构样本](assets/ui-lab/structures.html) |
| 内容驱动的新构图与动效候选 | [设计探索](assets/ui-lab/design-exploration.html)；候选样本，按内容取用 |
| 外部 skill 触发、安装路径、冲突与更新 | [external-skills.md](references/external-skills.md) |
| 安装、跨机器与演化 | [README.md](README.md)、[evolution.md](evolution.md) |

## 已确认场景，不是可设计场景的全集

| ID | 范围 | 读取 |
| --- | --- | --- |
| S01 | 浅色信息密集界面、图表与状态历史 | [偏好与控件起点](references/preferences.md)、[patterns.md](patterns.md) |
| S02 | 冷灰蓝预览型工作台、图片/卡片与稀疏状态 | [preview-workbench.md](scenarios/preview-workbench.md) |
| S03 | 科研曲线、方法族与参考线 | [research-charts.md](scenarios/research-charts.md)、[脱敏实例](examples/research-dashboard.md)；多系列任务必读 patterns.md §1 |
| S04 | 关系归因、联合排行、汇总/下钻 | [analytical-workbench.md](scenarios/analytical-workbench.md)；采集/留存/恢复按需读 [data-and-runtime.md](references/data-and-runtime.md) |

阅读、报告、展示、移动端等任务直接设计，无需先建 Sxx。先做合适方案，实际反馈成熟后再增量沉淀；新场景的经验先只在该场景内生效。
