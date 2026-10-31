---
deck_id: nju-academic-ginkgo
kind: deck
category: scenario
summary: 南京大学学术答辩与项目汇报，以白底、银杏金与清浅蓝配色，将长文档压成结论清晰的演示。
keywords: [南京大学, 南大, 学术汇报, 答辩, 银杏金]
primary_color: "#BD934E"
canvas_format: ppt169
canvas_width: 1280
canvas_height: 720
canvas_viewbox: "0 0 1280 720"
source_canvas_width: 1280
source_canvas_height: 720
source_viewbox: "0 0 1280 720"
replication_mode: standard
native_structure_mode: structured
page_count: 11
placeholders:
  01_cover: ["{{PAGE_TITLE}}", "{{TITLE}}", "{{SUBTITLE}}", "{{AUTHOR}}", "{{DATE}}"]
  02_points3: ["{{PAGE_TITLE}}", "{{POINT_1_NO}}", "{{POINT_1_TITLE}}", "{{POINT_1_LINE_1}}", "{{POINT_1_LINE_2}}", "{{POINT_1_LINE_3}}", "{{POINT_2_NO}}", "{{POINT_2_TITLE}}", "{{POINT_2_LINE_1}}", "{{POINT_2_LINE_2}}", "{{POINT_2_LINE_3}}", "{{POINT_3_NO}}", "{{POINT_3_TITLE}}", "{{POINT_3_LINE_1}}", "{{POINT_3_LINE_2}}", "{{POINT_3_LINE_3}}", "{{TAKEAWAY_LABEL}}", "{{TAKEAWAY}}", "{{PAGE_NUM}}"]
  03_toc: ["{{PAGE_TITLE}}", "{{TOC_ITEM_1_NO}}", "{{TOC_ITEM_1_TITLE}}", "{{TOC_ITEM_1_DESC}}", "{{TOC_ITEM_2_NO}}", "{{TOC_ITEM_2_TITLE}}", "{{TOC_ITEM_2_DESC}}", "{{TOC_ITEM_3_NO}}", "{{TOC_ITEM_3_TITLE}}", "{{TOC_ITEM_3_DESC}}", "{{TOC_ITEM_4_NO}}", "{{TOC_ITEM_4_TITLE}}", "{{TOC_ITEM_4_DESC}}", "{{TOC_ITEM_5_NO}}", "{{TOC_ITEM_5_TITLE}}", "{{TOC_ITEM_5_DESC}}", "{{PAGE_NUM}}"]
  04_chapter: ["{{PAGE_TITLE}}", "{{CHAPTER_NUM}}", "{{CHAPTER_TITLE}}", "{{CHAPTER_DESC}}", "{{PAGE_NUM}}"]
  05_pillars4: ["{{PAGE_TITLE}}", "{{PILLAR_1_NO}}", "{{PILLAR_1_TITLE}}", "{{PILLAR_1_BODY_1}}", "{{PILLAR_1_BODY_2}}", "{{PILLAR_2_NO}}", "{{PILLAR_2_TITLE}}", "{{PILLAR_2_BODY_1}}", "{{PILLAR_2_BODY_2}}", "{{PILLAR_3_NO}}", "{{PILLAR_3_TITLE}}", "{{PILLAR_3_BODY_1}}", "{{PILLAR_3_BODY_2}}", "{{PILLAR_4_NO}}", "{{PILLAR_4_TITLE}}", "{{PILLAR_4_BODY_1}}", "{{PILLAR_4_BODY_2}}", "{{TAKEAWAY_LABEL}}", "{{TAKEAWAY}}", "{{PAGE_NUM}}"]
  06_two_col: ["{{PAGE_TITLE}}", "{{BULLET_1_TITLE}}", "{{BULLET_1_DESC}}", "{{BULLET_2_TITLE}}", "{{BULLET_2_DESC}}", "{{BULLET_3_TITLE}}", "{{BULLET_3_DESC}}", "{{FIGURE_TITLE}}", "{{FIGURE_DESC}}", "{{FIG_CAPTION}}", "{{TAKEAWAY_LABEL}}", "{{TAKEAWAY}}", "{{PAGE_NUM}}"]
  07_timeline: ["{{PAGE_TITLE}}", "{{NODE_1_DATE}}", "{{NODE_1_TITLE}}", "{{NODE_1_BODY_1}}", "{{NODE_1_BODY_2}}", "{{NODE_2_DATE}}", "{{NODE_2_TITLE}}", "{{NODE_2_BODY_1}}", "{{NODE_2_BODY_2}}", "{{NODE_3_DATE}}", "{{NODE_3_TITLE}}", "{{NODE_3_BODY_1}}", "{{NODE_3_BODY_2}}", "{{NODE_4_DATE}}", "{{NODE_4_TITLE}}", "{{NODE_4_BODY_1}}", "{{NODE_4_BODY_2}}", "{{TAKEAWAY_LABEL}}", "{{TAKEAWAY}}", "{{PAGE_NUM}}"]
  08_chart_column: ["{{PAGE_TITLE}}", "{{SOURCE}}", "{{TAKEAWAY_LABEL}}", "{{TAKEAWAY}}", "{{PAGE_NUM}}"]
  09_chart_combo: ["{{PAGE_TITLE}}", "{{AXIS_Y}}", "{{AXIS_Y2}}", "{{SOURCE}}", "{{TAKEAWAY_LABEL}}", "{{TAKEAWAY}}", "{{PAGE_NUM}}"]
  10_table: ["{{PAGE_TITLE}}", "{{SOURCE}}", "{{TAKEAWAY_LABEL}}", "{{TAKEAWAY}}", "{{PAGE_NUM}}"]
  11_ending: ["{{PAGE_TITLE}}", "{{THANK_YOU}}", "{{ENDING_SUBTITLE}}", "{{CONTACT_INFO}}", "{{PAGE_NUM}}"]
---

# 南京大学银杏金学术汇报 — Design Specification

## I. Template Overview

| Application context | Definition |
| --- | --- |
| Recurring presentation family | 学位答辩、开题中期、课题组与项目评审 |
| Intended audiences and outcomes | 专家与同学；快速识别结论，并能追问证据 |
| Delivery and reading assumptions | 现场讲解为主，兼顾会后阅读；数据有单位、口径与来源 |
| Representative narrative/page roles | 封面、目录、章节、并列论据、四项能力、图文、时间线、柱状图、柱线图、表格、结束页 |

白底、银杏金、清浅蓝点缀、深灰正文。来源为 `南京大学.pptx` 的实际第1页；其余页型依据已确认用途新建，不假称原文件提供了11页。

## II. Color Scheme
| Role | Color | Application |
| --- | --- | --- |
| Source gold | #BD934E | 原标识与建筑资产，不重染 |
| Heading gold | #B38B4A | 标题及对应序号统一同色，靠字号与粗细区分层级；时间节点同色 |
| Subtitle blue gray | #738693 | 封面副题、章节说明、结束页副句，较正文更轻 |
| Pale gold | #E2C98F | 图表浅金柱体，替代原深黄填充 |
| Sky blue | #83BED9 | 图表次要系列 |
| Clear blue | #579AB9 | 图表折线与内容细边；不进入序号／标题文字组合 |
| Blue wash | #F0F8FC | 结论带与证据区域的极浅蓝底 |
| Table header | #E4F3FA | 浅蓝表头 |
| Table header text | #56788B | 浅蓝表头上的柔和蓝灰文字，保证可读性 |
| Rule | #D8EAF2 | 分隔线 |
| Body | #404040 | 正文与结论 |
| Muted | #757575 | 来源、页码与说明 |
| White | #FFFFFF | 页面背景 |

浅金用于图表主系列，天蓝用于次系列；双轴图采用浅金柱体与清蓝折线，并通过图例、单位和线型区分，不能仅靠颜色。标题与序号统一为柔和金色，不再拆成蓝色序号与金色标题；靠字号、字重和留白分层。清蓝细线和极浅蓝结论带作为内容层辅助。副题为蓝灰；13px结论小标签仍保留较深金色，正文保持深灰。表头改为浅蓝底配蓝灰文字，不在浅底上反白。新增内容仍不采用深蓝横带、深蓝满版或旧版校徽圆盘。

## III. Typography

- 全套主字体：`Microsoft YaHei, 微软雅黑, sans-serif`；拉丁和数字随同一字体，不引入第三字体族
- 顶栏标题26.67 px，文字随新标题色更新，图像资产不改；封面52，章节42，结束页60；正文20，栏标题24–26；注释12–14
- 正文三行基线间距36；页面标题允许向右扩展至620宽，不改变叶片位置

## IV. Signature Design Elements

- 一个白金 Master，包含白背景、原左上标识裁切、原银杏叶的位置与姿态；11个不同槽位合约的Layout
- 校徽图片和叶片图片字节沿用原素材，不重染，不显示原裁切之外的周年文字；左上已可见的周年组合标识按用户要求完整保留
- 校园线稿为原路径和原渐变形成的Slide本地矢量组，经 `icons/imported/nju-campus.svg` 唯一资产引用，不是一张全页截图
- 顶部标识及标题区 y≤120；内容 x=96–1184，正文通常 y=162–443；结论 y=480–560；页码基线580；建筑约从y=585.5起
- 三栏宽320、间距64；四栏宽254、间距24；标题、正文在每栏内左对齐
- 蓝色只进入内容层，不重染原校徽、银杏叶或浅金建筑；浅金图表填充区别于原标识金，不用全局替换破坏底板
- 并列信息不用箭头；比起chevron，无遮罩的并列栏不会误导为流程，也不会让装饰抢占证据
- 时间轴保留四节点顺序；封面、章节、结束页用大字与留白建立层级，不另加满版色块
- 所有文本槽位保留可编辑的完整区域；居中仅用于右侧短图示标签，正文仍从左上起写
- 结论带浅蓝底条、左侧强调线与文字是各页独立对象，不组合、不锁定、不放入Master/Layout；底条和线为原生矩形，文字保留独立文本占位符，可分别选中、编辑与拖动
- 原生chart/table槽位以JSON数据为权威，SVG图形为近似预览。内置数据仅用于版式演示，生成正式内容时用brief数据替换，不得当作研究事实

## V. Page Roster

| File | Layout key | PowerPoint picker name | Visual character | Slot capacity |
| --- | --- | --- | --- | --- |
| `01_cover.svg` | cover | NJU Ginkgo Cover | 左对齐主题与元信息，白金建筑底板 | 主标题单行≤18字，长标题另起副题 |
| `02_points3.svg` | points3 | NJU Ginkgo Three Points | 已通过的三点并列正文 | 三组标题和三行正文，结论一行 |
| `03_toc.svg` | toc | NJU Ginkgo Contents | 五条横向目录行，序号、章名、说明分列 | 3–5条；未使用槽位置空 |
| `04_chapter.svg` | chapter | NJU Ginkgo Chapter | 同色柔和金章号与章名，蓝灰短说明；不使用深色底 | 章名≤12字；说明≤30字 |
| `05_pillars4.svg` | pillars4 | NJU Ginkgo Four Pillars | 四项并列能力，以细线分组代替大色块卡片 | 4项；每项标题≤6字，正文2–3行 |
| `06_two_col.svg` | two_col | NJU Ginkgo Two Column | 左侧三条短论点，右侧可替换图像／图表区域 | 左≤3条；右图544×272；图注单行 |
| `07_timeline.svg` | timeline | NJU Ginkgo Timeline | 四节点横向时间轴，阶段在上、产物在下 | 固定4节点；需要5节点时拆页，避免缩字 |
| `08_chart_column.svg` | chart_column | NJU Ginkgo Column Chart | 浅金与天蓝搭配的原生簇状柱状图 | JSON数据可替换；类别≤6，系列≤3；示例数据不作论据 |
| `09_chart_combo.svg` | chart_combo | NJU Ginkgo Combo Chart | 浅金柱体、清蓝折线的双轴图，左右单位明确 | JSON数据可替换；类别≤6，系列≤3；示例数据不作论据 |
| `10_table.svg` | table | NJU Ginkgo Table | 浅蓝表头、深灰正文的原生三线表，数字右对齐 | 当前4列4数据行；扩到6行5列须重新核对容量 |
| `11_ending.svg` | ending | NJU Ginkgo Ending | 与封面呼应的白底金色结束页 | 致谢≤12字，副句≤24字；联系信息可置空 |

## VI. Assets

| File | Provenance and behavior |
| --- | --- |
| `images/nju-logo.png` | 原image3.png字节不变，保留原嵌套裁切框 |
| `images/ginkgo-leaf.png` | 原image4.png字节不变，沿用旋转与翻转 |
| `icons/imported/nju-campus.svg` | 源实际版式的建筑路径；preserve-color保持矩形比例及渐变 |

## VII. Placeholder Overrides

完整词汇见frontmatter；目录使用TOC_ITEM_N_TITLE／DESC，其他并列页按栏目索引。图表表格数据直接替换载体JSON，不用文本占位符伪装数据对象。
