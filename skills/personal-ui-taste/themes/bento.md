# Bento Box · 预览/画廊主题

- 来源：UI/UX Pro Max #39（Apple 气质）；2026-10-04 用户对比验收 Confirmed。
- 气质：无边界世界——层级全靠灰阶与阴影，大圆角白块浮在浅灰画布上，悬浮轻微上浮。
- 默认适用：S02 预览型工作台、卡片画廊、内容以图片/预览为主的页面。

## Tokens

| 项 | 值 |
| --- | --- |
| 字体 | Inter；数字 tabular-nums |
| 表面 | canvas `#f5f5f7`；panel `#ffffff`；control `#f0f0f2` |
| 文本 | primary `#1d1d1f`；secondary `#6e6e73` |
| 边界 | 不用边界（transparent）；层级靠阴影 |
| 强调 | accent `#0071e3`；hover `#0062c4`；selected `#e8f1fd` |
| 图表色 | `#0071e3` `#7d4edd` `#00a699` `#ff9f0a` `#ff375f` |
| 状态色 | ok `#248a3d`；warn `#c77700`；bad `#d70015` |
| 圆角 | 控件 10；面板 18；卡片 22 |
| 阴影 | 平铺 `0 1px 3px rgba(0,0,0,.05)`；hover `0 8px 24px rgba(0,0,0,.08)`；浮层 `0 16px 44px rgba(0,0,0,.14)` |
| 动效 | 160ms ease / 280ms cubic-bezier(.32,.72,.35,1) |

## 组件处理要点

- **面板/KPI**：无 border，`box-shadow` 分层，hover 阴影升一档。
- **卡片**：hover `translateY(-3px) scale(1.01)` + 阴影升起（画廊的核心反馈）。
- **侧栏**：透明融入画布；活跃项白底 + 轻阴影浮起。
- **顶栏**：透明 + `blur(12px)`。
- **按钮**：无边框带轻阴影；主按钮 `0 2px 8px rgba(0,113,227,.3)`。
- **表格**：行分隔 `#f0f0f2`，表头 `#f5f5f7`。
- 注意：信息密集表格场景慎用本主题（无边界会降低扫描线感），它服务预览而非排查。

## 用户反馈记录

- 2026-10-04：卡片观感舒适，挑不出毛病。
