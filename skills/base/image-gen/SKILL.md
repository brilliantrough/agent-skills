---
name: image-gen
description: image_gen 工具说明：用宿主自带的 image_gen 画图或改图，覆盖文生图、参考图编辑、多张参考图、size/quality/background/model 参数、返回与落盘、宿主差异、失败含义。只描述工具接口与行为，不规定项目的审美、风格或出图流程。Use when the user asks for a picture, poster, illustration, icon or cover, or when you need the tool's exact parameters, host behavior or failure meanings.
---

# image-gen

工具：`image_gen(prompt, reference?, size?, quality?, background?, model?)`，三宿主同名（Pi / OpenCode v2 / DSH）。凭据与默认值在 `~/.local/share/agent-skills/image-gen.json`。

本 skill 只说明工具能力与行为。画什么、用什么风格、要不要画，由调用方（项目自己的规范或用户 prompt）决定。

## 1. 能做什么

| 能力 | 说明 |
| --- | --- |
| 文生图 | 给 `prompt` 即走 `/images/generations`，返回一张位图 |
| 参考图编辑 | 给 `reference`（绝对路径数组）即走 `/images/edits`，可传一张或多张 |
| 透明底 | `background: "transparent"` |
| 尺寸与画质 | `size`、`quality` 透传给渠道 |
| 指定模型 | `model` 覆盖默认模型 |

不能做：

- **只出位图**，不是可编辑矢量/SVG；需要精确文字、公式、真实数据或二次编辑时，位图不合适
- **一次调用一张图**（内部固定 `n: 1`）；要几张就调几次
- 不保证图中文字正确 —— 生成模型自身的限制，调 `quality` 或 `size` 都不改变这一点

## 2. 文生图

```json
{ "prompt": "希望画面里出现的内容" }
```

## 3. 参考图编辑

```json
{ "prompt": "保留什么、只改什么", "reference": ["/abs/path/a.png", "/abs/path/b.png"] }
```

多张参考图一起传；不给 `reference` 就是文生图。编辑结果可能与原图有未要求的差异，原图请自行保留。

## 4. 参数

| 参数 | 类型与取值 | 说明 |
| --- | --- | --- |
| `prompt` | 字符串，必填 | 画面内容；参考图编辑时写修改要求 |
| `reference` | 字符串数组（绝对路径） | 给了走参考图编辑 |
| `size` | 如 `1024x1024`、`1536x1024`、`2048x1152` | 默认取配置（`1024x1024`）；本机实测可用到 `3840x2160`，实际支持范围由渠道决定 |
| `quality` | `auto` / `low` / `medium` / `high` / `xhigh` / `max` | 默认取配置（`medium`）；档位越高越慢越贵，不改变像素尺寸 |
| `background` | `transparent` / `opaque` | 透明底用于图标、贴图 |
| `model` | 字符串 | 默认：文生图 `gpt-image-2.5-flare`，有参考图时 `gpt-image-2.5-sunburst` |

## 5. 返回与落盘

返回三项：落盘路径、一行 `模型 · 尺寸 · 画质 · 格式 · 体积` 摘要、图片本身（宿主是否把它交给模型见第 6 节）。

- 目录：`output_dir`，默认项目 cwd 下的 `images/`，不存在则创建
- 文件名：ISO 时间戳 + prompt 前 40 字，扩展名取渠道返回的 `output_format`
- 单图几百 KB，会进会话历史

## 6. 宿主差异

| 宿主 | 差异 |
| --- | --- |
| Pi | 当前模型 input 含 `image` 时把图作为附件返回；纯文本模型只拿到路径与摘要，会附一句提示 |
| OpenCode v2 | 图以 `data:` 文件附件进会话；TUI 里显示预览需 `session.image_preview=true`（默认关） |
| DSH | 同一 Pi 扩展经 `pi2dsh` 转成 DSH 原生附件 |

模型看不到图时，把路径交给用户自己打开，不要说"图在下面"。

## 7. 失败怎么读

工具**不自动重试**，失败即抛错，需要重试就自己再调一次。

| 报错 | 含义 |
| --- | --- |
| `图像接口 503 … 无可用渠道` / `model_not_found` | 网关没给这个 key 开该模型渠道，或模型名写错 |
| `图像接口 401` | key 无效 |
| `缺少图像接口凭据` | `image-gen.json` 缺 `base_url` 或 `api_key` |
| `图像接口返回非 JSON（HTTP …）` | 渠道返回了 HTML/网关页，原文附在前 300 字 |
| `图像接口没返回图片` | 返回体里没有 `data[0].b64_json`，原文附在前 300 字 |
| 超时 / 中断 | 大尺寸或高画质；`signal` 取消或降档重试 |

## 8. 配置

`~/.local/share/agent-skills/image-gen.json`（`0600`，`IMAGE_GEN_CONFIG` 可改路径）：

```json
{
  "base_url": "https://api.example.com/v1",
  "api_key": "...",
  "model": "gpt-image-2.5-flare",
  "edit_model": "gpt-image-2.5-sunburst",
  "output_dir": "images",
  "size": "1024x1024",
  "quality": "medium"
}
```

- 文件不存在时，从 `~/.pi/agent/models.json` 里挑第一个 `api` 以 `openai` 开头、凭据和 `baseUrl` 都填好的 provider 自动写入；挑不到就写空模板并报错
- `pi-setup.sh` / `opencode-setup.sh` 会补齐缺字段，已有的 `base_url` / `api_key` 一律保留
- 无人值守可用 `PI_IMAGE_GEN_API_KEY` 预填
- 参数优先级：单次调用参数 > `image-gen.json` > 内置默认值
