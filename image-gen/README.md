# image-gen — 画图工具

把知识、对比、流程画成图：`image_gen(prompt, reference?, size?, quality?, background?, model?)`。

一个核心 `core.mjs`，三个宿主薄适配：

| 宿主 | 入口 | 图片如何回到模型 |
| --- | --- | --- |
| Pi | `pi/extensions/image-gen.ts`（`pi` 字段自动加载） | `content: [{type:"image"}]`，纯文本模型自动不附 |
| DSH | 同一 Pi 扩展，经 `pi2dsh` | 原生 DSH content/attachments |
| OpenCode v2 | `opencode/v2/image-gen.js` | `content: [{type:"file", uri:"data:..."}]` |

## 配置

`~/.local/share/agent-skills/image-gen.json`（`0600`，`IMAGE_GEN_CONFIG` 可改路径）：

```json
{
  "base_url": "https://api.pezayo.com/v1",
  "api_key": "...",
  "model": "gpt-image-2.5-flare",
  "output_dir": "images",
  "size": "1024x1024",
  "quality": "medium"
}
```

文件不存在或缺少 `base_url`／`api_key` 时，自动从 `~/.pi/agent/models.json` 挑第一个 `api` 以 `openai` 开头且有 `baseUrl`／`apiKey` 的 provider 写入；挑不到就报错并留下空模板。

- `output_dir` 相对项目 cwd，默认 `images/`
- `size` 可任意到 `3840x2160`；`quality` 支持 `auto`／`low`／`medium`／`high`／`xhigh`／`max`
- `background: "transparent"` 用于图标、贴图

## 接口

| 场景 | 请求 | 返回 |
| --- | --- | --- |
| 文生图 | `POST {base_url}/images/generations`（JSON） | `data[0].b64_json` + `size`/`quality`/`output_format` |
| 图生图／编辑 | `POST {base_url}/images/edits`（multipart，字段 `image[]`） | 同上 |

网关必须给这个 key 开图像渠道，否则返回 `503 model_not_found ... 无可用渠道`。

## 已知边界

- OpenCode v2 想在聊天里看到图，需打开 `session.image_preview`（默认关）
- 生成的图每张几百 KB，会进会话历史；同一次对话里不要连续画很多张
- v1 OpenCode 入口没有这个工具
