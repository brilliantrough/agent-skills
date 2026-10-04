# Modern SaaS 亮蓝 · 工作型界面默认主题

- 来源：UI/UX Pro Max 色板（SaaS/Analytics 家族）+ Linear/Vercel 产品气质；2026-10-04 用户对比验收 Confirmed。
- 气质：深色侧栏 + 亮色内容区的现代 SaaS 管理台；电光蓝强调、细腻微光，不张扬。
- 默认适用：S01 信息密集界面、S04 分析排查工作台、一切管理台/仪表盘；也是未指定场景时的默认主题。

## Tokens

| 项 | 值 |
| --- | --- |
| 字体 | Inter（Google Fonts）；数字 tabular-nums |
| 表面 | canvas `#f6f7f9`；panel `#ffffff`；control `#f1f2f5` |
| 文本 | primary `#0f172a`；secondary `#5b6472` |
| 边界 | `#e7e9ef`；强 `#d3d8e2` |
| 强调 | accent `#2e6bf0`；hover `#1f5be0`；selected `#eaf1ff` |
| 图表色 | `#2e6bf0` `#8b5cf6` `#06b6d4` `#f59e0b` `#f43f5e` |
| 状态色 | ok `#16a34a`；warn `#d97706`；bad `#dc2626` |
| 圆角 | 控件 8；面板 10；卡片 14 |
| 阴影 | `0 1px 2px rgba(16,24,40,.05)`；浮层 `0 12px 32px rgba(16,24,40,.16)` |
| 动效 | 150ms / 240ms cubic-bezier(.4,0,.2,1) |

## 组件处理要点

- **侧栏**：深 `#0d1220`，文字 `#8b94a9`；活跃项 `linear-gradient(90deg, rgba(46,107,240,.28), rgba(46,107,240,.10))` + 左侧 2.5px 亮蓝指示条（带 `0 0 8px` 辉光）；品牌点带辉光。
- **顶栏**：`rgba(255,255,255,.82)` + `backdrop-filter: blur(10px)`。
- **主按钮**：accent 底 + `0 1px 2px rgba(46,107,240,.35)`，hover 加 `0 2px 10px rgba(46,107,240,.45)`。
- **状态灯带（标杆处理，用户全场最佳）**：颜色亮而鲜艳，hover `scaleY(1.25)` + `0 0 6px currentColor` 同色系辉光。
- **焦点曲线**：高亮系列 `drop-shadow(0 0 4px rgba(46,107,240,.35))`。

## 用户反馈记录

- 2026-10-04：灯带"这个颜色很亮，很鲜艳我很喜欢"，为全部候选中最好；整体方向挑不出毛病。
