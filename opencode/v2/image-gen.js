import { tool } from "@opencode-ai/plugin";
import { basename } from "node:path";
import { DESCRIPTION, TOOL, configPath, generate } from "../../image-gen/core.mjs";

// 图片以 data: URI 的 file part 返回；OpenCode 会把它转成会话附件并作为媒体内容喂给模型。
export default {
  id: "agent-skills.image-gen",
  async setup(ctx) {
    return ctx.tool.transform((editor) =>
      editor.add({
        name: TOOL,
        options: { codemode: true },
        description: `${DESCRIPTION} 凭据与默认模型在 ${configPath()}。`,
        input: tool.schema.object({
          prompt: tool.schema.string().describe("你写好的绘图提示词：主体、结构、需要出现的文字标签、风格与配色"),
          reference: tool.schema.array(tool.schema.string()).optional().describe("参考图绝对路径；给了就改图/换风格，不给就是文生图"),
          size: tool.schema.string().optional().describe("如 1024x1024、1536x1024、2048x1152；默认取配置"),
          quality: tool.schema.enum(["auto", "low", "medium", "high", "xhigh", "max"]).optional().describe("画质档位，越高越慢越贵；默认取配置"),
          background: tool.schema.enum(["transparent", "opaque"]).optional().describe("透明底用于图标/贴图"),
          model: tool.schema.string().optional().describe("覆盖模型，如 gpt-image-2.5-sunburst；默认取配置"),
        }),
        async execute(args, context) {
          const result = await generate(args, ctx.location.directory, context.signal);
          return {
            content: [
              { type: "text", text: `${result.path}\n${result.note}` },
              { type: "file", uri: `data:${result.mimeType};base64,${result.base64}`, mime: result.mimeType, name: basename(result.path) },
            ],
            metadata: { path: result.path, size: result.note },
          };
        },
      }),
    );
  },
};
