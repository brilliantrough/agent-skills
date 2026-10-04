# Bespoke 观测站 · 科研工作台主题

- 来源：按 Anthropic frontend-design 流程为科研场景定制；2026-10-04 用户对比验收 Confirmed。
- 气质：冷灰蓝仪器面板——蓝图网格画布、面板顶部 2px 主色规线（仪器铭牌感）、数字是大号读数。
- 默认适用：S03 科研指标看板、实验工作台、监控运维台。

## Tokens

| 项 | 值 |
| --- | --- |
| 字体 | IBM Plex Sans（Google Fonts）；数字 tabular-nums 加粗 |
| 表面 | canvas `#edf1f4` + 26px 蓝图网格线 `rgba(29,45,66,.045)`；panel `#ffffff`；control `#eef2f5` |
| 文本 | primary `#1d2733`；secondary `#5c6b7a` |
| 边界 | `#dde5ec`；强 `#c2cfda` |
| 强调 | accent `#0b84f3`；hover `#0673d9`；selected `#e3f0fd` |
| 图表色 | `#0b84f3` `#6c5ce7` `#00a8a8` `#e8963c` `#d6517a` |
| 状态色 | ok `#1f9d63`；warn `#cf8a1a`；bad `#d64550` |
| 圆角 | 控件 6；面板 9；卡片 12 |
| 阴影 | `0 1px 2px rgba(29,45,66,.07)`；浮层 `0 14px 38px rgba(29,45,66,.17)` |
| 动效 | 140ms / 220ms ease |

## 组件处理要点

- **画布**：body 铺 26px 淡网格（`linear-gradient` 双向 1px 线），仪器背景纸。
- **面板**：顶部 2px accent 规线，圆角上沿收窄到 4px 形成铭牌感。
- **KPI**：左侧 3px accent 竖条；数值 26px/700 收紧字距。
- **导航**：活跃项浅蓝底 + 左侧 3px accent 指示条。
- **状态灯带**：装在 control 色刻度槽内（padding 3px + 细边框），各段带同色辉光（ok `.45` / warn `.6` / bad `.7`）——这是本主题的 memorable 元素，其余装饰为它让路。
- **主按钮**：`inset 0 1px 0 rgba(255,255,255,.25)` 实体按键高光，按下时 `inset 0 2px 4px rgba(0,0,0,.2)` + 下沉 1px。
- **图例 chip**：直角 4px，焦点态 `inset 0 0 0 1.5px accent`。

## 用户反馈记录

- 2026-10-04：整体挑不出毛病；字体与形状样式获认可。
