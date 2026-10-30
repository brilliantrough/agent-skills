import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { DESCRIPTION, TOOL, configPath, generate } from "../../image-gen/core.mjs";

// 画图工具：图片既落盘留档，也作为图片内容返回给模型（下一轮请求里模型能看到自己画了什么）。
// DSH 经 pi2dsh 复用同一扩展，工具结果走 DSH 原生 content/attachments。
export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: TOOL,
    label: "Image gen · 画图",
    description: `${DESCRIPTION} 凭据与默认模型在 ${configPath()}。`,
    parameters: Type.Object({
      prompt: Type.String({ minLength: 1, description: "你写好的绘图提示词：主体、结构、需要出现的文字标签、风格与配色" }),
      reference: Type.Optional(Type.Array(Type.String(), { description: "参考图绝对路径；给了就改图/换风格，不给就是文生图" })),
      size: Type.Optional(Type.String({ description: "如 1024x1024、1536x1024、2048x1152；默认取配置" })),
      quality: Type.Optional(Type.Union([
        Type.Literal("auto"), Type.Literal("low"), Type.Literal("medium"), Type.Literal("high"), Type.Literal("xhigh"), Type.Literal("max"),
      ], { description: "画质档位，越高越慢越贵；默认取配置" })),
      background: Type.Optional(Type.Union([Type.Literal("transparent"), Type.Literal("opaque")], { description: "透明底用于图标/贴图" })),
      model: Type.Optional(Type.String({ description: "覆盖模型，如 gpt-image-2.5-sunburst；默认取配置" })),
    }),
    async execute(_id, params, signal, _update, ctx) {
      const result = await generate(params, ctx.cwd, signal);
      const vision = ctx.model?.input?.includes("image") ?? false;
      return {
        content: [
          { type: "text", text: `${result.path}\n${result.note}${vision ? "" : "\n当前模型看不了图片，图片已存盘，请让用户打开查看。"}` },
          ...(vision ? [{ type: "image" as const, data: result.base64, mimeType: result.mimeType }] : []),
        ],
        details: { path: result.path, size: result.note },
      };
    },
  });
}
