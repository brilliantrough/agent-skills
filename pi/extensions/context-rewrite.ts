import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
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
