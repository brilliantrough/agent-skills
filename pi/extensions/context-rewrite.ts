import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { resolve } from "node:path";
import { homedir } from "node:os";
import { createOutputStore, OUTPUT_META, READ_TOOL, READ_DESCRIPTION } from "../../context-rewrite/output-store.mjs";
import { Type } from "typebox";
import { TOOL, META, DESCRIPTION, windowSize, indexOperations, makeRecord, artifact, marker, isRecord } from "../../context-rewrite/core.mjs";

function history(ctx: any, window: number) {
  const messages = ctx.sessionManager.getBranch().filter((e: any) => e.type === "message").map((e: any) => e.message);
  const results = new Map<string, any>(messages.filter((m: any) => m.role === "toolResult").map((m: any) => [m.toolCallId, m]));
  const operations = messages.filter((m: any) => m.role === "assistant").flatMap((m: any) =>
    m.content.filter((p: any) => p.type === "toolCall").map((p: any) => ({
      key: p.id, tool: p.name, finished: results.has(p.id),
    })),
  );
  for (const op of operations.filter((op: any) => op.finished && op.tool !== TOOL).slice(-window)) {
    op.text = results.get(op.key).content.filter((c: any) => c.type === "text").map((c: any) => c.text).join("\n");
  }
  const records = new Map<string, any>();
  for (const [key, result] of results) {
    if (result.toolName === TOOL && !result.isError && isRecord(result.details?.[META])) records.set(key, result.details[META]);
  }
  return { index: indexOperations(operations, [...records.values()]), records };
}

export default function (pi: ExtensionAPI) {
  if (process.env.MAGIC_CONTEXT_PI_SUBAGENT === "1") return;
  const window = windowSize();
  const outputStore = createOutputStore();
  let visible = new Map<number, string>();
  let sessionId: string | undefined;

  pi.registerTool({
    name: TOOL,
    label: "Context rewrite · 近期纠正",
    description: DESCRIPTION + ` Current window: ${window} completed operations.`,
    exposure: "model-only",
    executionMode: "sequential",
    parameters: Type.Object({
      ids: Type.Array(Type.Integer({ minimum: 1 }), { minItems: 1, description: "要撤下的 context_op 数字 ID；不是 Magic Context tag" }),
      note: Type.String({ minLength: 1, description: "保留的事实、错误原因与下一步正确做法；纯文本，不重复原始大输出" }),
    }),
    async execute(_id, { ids, note }, _signal, _update, ctx) {
      if (sessionId !== ctx.sessionManager.getSessionId()) throw new Error("请先在当前会话读取带 context_op ID 的工具结果");
      const { index } = history(ctx, window);
      const record = makeRecord(index, visible, ids, note, window);
      return { content: [{ type: "text", text: artifact(record) }], details: { [META]: record } };
    },
  });

  pi.registerTool({
    name: READ_TOOL,
    label: "Context output · 原文取回",
    description: READ_DESCRIPTION,
    exposure: "model-only",
    parameters: Type.Object({
      id: Type.String({ pattern: "^[a-f0-9]{64}$", description: "context_output 的完整 id" }),
      offset: Type.Optional(Type.Integer({ minimum: 0, description: "UTF-8 字节偏移；使用上页 next_offset，不是行号" })),
      full: Type.Optional(Type.Boolean({ description: "显式取回全文，不再自动外置；默认分页" })),
    }),
    async execute(_id, args, signal) {
      return { content: [{ type: "text", text: await outputStore.retrieve(args, signal) }], details: undefined };
    },
  });

  pi.on("tool_result", async (event, ctx) => {
    if (event.parentToolCallId) return; // codemode 的内部计算仍获得原始数据。
    const texts = event.content.filter((p) => p.type === "text").map((p) => p.text);
    const details = event.details as any;
    const fullOutputPath = ["bash", "powershell"].includes(event.toolName) ? details?.fullOutputPath : undefined;
    const filePath = event.toolName === "read" && !event.isError && event.content.every((p) => p.type === "text")
      ? event.input.path as string : undefined;
    const sourcePath = fullOutputPath ?? (filePath ? resolve(ctx.cwd, filePath.replace(/^@/, "").replace(/^~(?=$|[\\/])/, homedir())) : undefined);
    const structured = event.structuredContent as any;
    try {
      const record = await outputStore.capture(texts, {
        tool: event.toolName, input: event.input, sourcePath,
        force: Boolean(fullOutputPath || (filePath && details?.truncation?.truncated && event.input.limit === undefined)),
        scope: fullOutputPath ? "complete_command_output" : filePath ? "complete_file_snapshot" : "tool_result_snapshot_may_be_host_truncated",
        status: `${event.isError ? "error" : "completed"}${structured?.exit_code !== undefined ? `; exit_code=${structured.exit_code}` : ""}`,
      });
      if (record) return {
        content: [{ type: "text", text: record.pointer }, ...event.content.filter((p) => p.type !== "text")],
        details: { ...details, [OUTPUT_META]: record },
        structuredContent: ["bash", "powershell"].includes(event.toolName) && structured
          ? { ...structured, output: record.pointer, truncated: true, full_output_path: record.path } : undefined,
      };
    } catch (error) {
      console.error("[context_output] 保存失败，保留原始输出：", error);
    }
  });

  // 此阶段晚于所有 context hook，包括 Magic Context；不改宿主原始消息。
  pi.on("context_with_system", (event, ctx) => {
    sessionId = ctx.sessionManager.getSessionId();
    const { index, records } = history(ctx, window);
    visible = new Map();
    const calls = new Set(event.messages.flatMap((m: any) => m.role === "assistant"
      ? m.content.filter((p: any) => p.type === "toolCall").map((p: any) => p.id) : []));
    const messages = [];
    for (const message of event.messages as any[]) {
      if (message.role === "assistant") {
        const content = message.content.filter((p: any) => p.type !== "toolCall" || !index.removed.has(p.id));
        const removedCall = message.content.some((p: any) => p.type === "toolCall" && index.removed.has(p.id));
        const onlyThinking = content.every((p: any) => p.type === "thinking");
        if (content.length && !(removedCall && onlyThinking)) messages.push({ ...message, content });
      } else if (message.role === "toolResult") {
        if (index.removed.has(message.toolCallId)) continue;
        const record = records.get(message.toolCallId);
        const op = index.byKey.get(message.toolCallId);
        if (record) {
          messages.push({ ...message, content: message.content.map((p: any) => p.type === "text"
            ? { ...p, text: p.text.replace(artifact(record), artifact(record, false)) } : p) });
        } else if (op && calls.has(op.key)) {
          visible.set(op.id, op.key);
          messages.push({ ...message, content: [{ type: "text", text: marker(op) }, ...message.content] });
        } else messages.push(message);
      } else messages.push(message);
    }
    return { messages };
  });
}
