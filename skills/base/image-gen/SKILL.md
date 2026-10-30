---
name: image-gen
description: 出位图作为可选手段：用宿主自带的 image_gen 工具画示意图、概念图、海报、图标，或在用户明确要图时出图。Use when the user asks for a picture, poster, illustration, icon, cover, or when one bitmap conveys a concept faster than text — and to avoid the common mistake of drawing a flowchart that should have been vector. Covers prompt structure, size/quality/cost trade-offs, reference-image editing, host differences (Pi/OpenCode/DSH) and failure messages. 画图只是可选项，先判断能不能矢量。
---

# image-gen

工具：`image_gen(prompt, reference?, size?, quality?, background?, model?)`，三宿主同名（Pi / OpenCode v2 / DSH）。凭据与默认值在 `~/.local/share/agent-skills/image-gen.json`。

## 1. 先判断该不该出位图

画图是**可选项**，不是回答的默认配饰。

值得画：

- 用户明确要图（海报、封面、图标、插图、示意图）
- 一个概念用文字要多段，一张概念图能一句话说清
- 需要"氛围/风格"，而不是精确结构

**不要画**：

| 需求 | 用什么 |
| --- | --- |
| 流程、架构、时序、网络拓扑 | `drawio`（矢量、可改、文字清晰） |
| 论文/汇报图，要进 PPT 或 PDF | `editable-vector-slides`（原生可编辑） |
| 图里有精确代码、公式、长句 | HTML/SVG 或 drawio；gpt-image 画字会糊、会拼错 |
| 图要能二次编辑 | 同左：位图不能改 |
| 用户没要，你觉得"配一张更好看" | 最多主动提议一次，别直接画 |

一句话判据：**要精确、要改、要文字 → 矢量；要观感、要氛围 → 位图。**

## 2. 写 prompt

自己写，不要贴聊天原文或把整段需求扔进去。顺序：

1. 主体与数量：画面里到底有什么，几个
2. 结构与构图：横向流程 / 中心辐射 / 左右对比 / 三分法；有没有分栏、编号、箭头方向
3. 必须出现的文字：逐条列出，越少越好，每条几个字，不要句子
4. 风格一句话：扁平矢量插画 / 极简线稿 / 拟物 3D / 手绘白板 / 摄影级实拍
5. 配色：明度与主色（"深蓝底 + 青色高亮"），或点名一个既有色板
6. 不要什么：不要水印、不要乱码文字、不要装饰边框

风格方向从**已加载的设计 skill** 取（`personal-ui-taste`、`design-taste-frontend`、`huashu-design`、`ui-ux-pro-max`），取其一句结论落进 prompt；不要在 prompt 里复述整套设计规范。

## 3. 参数

| 参数 | 选择 |
| --- | --- |
| `size` | 默认 `1024x1024`；横向流程图 `1536x1024`；横幅/封面 `2048x1152`；最大到 `3840x2160` |
| `quality` | 草稿 `low`；文档与说明图 `medium`（默认）；封面海报 `high` 以上；`auto` 交渠道决定 |
| `background` | 图标、贴图、要贴到深色底上 → `transparent` |
| `model` | 不填按有无参考图取默认：文生图 `gpt-image-2.5-flare`（快）；给了参考图走精修 `gpt-image-2.5-sunburst`（慢但编辑更可控） |
| `reference` | 绝对路径数组，给了就走图生图 |

成本纪律：按张计费、随 `size × quality` 上升；单图几百 KB 会进会话历史。**同一次对话里不要连画多张**，先用 `low` 定构图再升档出成品。

## 4. 参考图（改图/换风格）

给绝对路径即走 `/images/edits`，默认换用 `gpt-image-2.5-sunburst`：改配色、换风格、加元素，比重新描述一遍稳。多个参考图一起给。改局部时 prompt 说清"保留什么、只改什么"。

只在要大改构图时退回 `flare`（快）：细修一次不满意就再修一次，比一次高画质重画便宜。

## 5. 宿主差异

| 宿主 | 差异 |
| --- | --- |
| Pi | 视觉模型直接看到图；纯文本模型只拿到路径和说明 |
| OpenCode v2 | 图以 `data:` 附件进会话；**要在 TUI 里看到预览需 `session.image_preview` 为 true**（默认关） |
| DSH | 走 DSH 原生附件 |

模型看不了图时，把落盘路径给用户，让他自己打开；不要说"已画好，见上"。

## 6. 失败怎么读

| 现象 | 原因 |
| --- | --- |
| `503 ... 无可用渠道` / `model_not_found` | 网关没给这个 key 开图像渠道，或模型名写错；换 key 分组或改名，别改 prompt |
| `401` | key 无效 |
| `缺少图像接口凭据` | `image-gen.json` 没填；写 `base_url` + `api_key`，或装机器时设 `PI_IMAGE_GEN_API_KEY` |
| 返回里没图 | 渠道返回格式不对，看报错原文前 300 字 |
| 超时 | 大尺寸 + 高画质；降到 `medium` 或 `1024x1024` 重试 |

## 7. 落盘

图存到项目内 `images/`（配置项 `output_dir`），文件名带时间戳和 prompt 摘要。项目不需要留图时提示用户 `.gitignore` 它。
