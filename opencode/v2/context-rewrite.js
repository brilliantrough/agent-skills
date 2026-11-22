import { TOOL, META, DESCRIPTION, windowSize, indexOperations, makeRecord, artifact, marker, isRecord } from "../../context-rewrite/core.mjs";

export default {
  id: "agent-skills.context-rewrite",
  async setup(ctx) {
    const window = windowSize();
    const visible = new Map();
    const registrations = [];
    const texts = (content) => typeof content === "string" ? [content] : (content ?? []).filter((p) => p.type === "text").map((p) => p.text);
    async function history(sessionID) {
      const messages = await ctx.session.context({ sessionID });
      const operations = [], records = new Map();
      for (const m of messages) if (m.type === "assistant") for (const p of m.content) {
        if (p.type !== "tool") continue;
        operations.push({ key: p.id, tool: p.name, finished: ["completed", "error"].includes(p.state.status), text: texts(p.state.content).join("\n") || p.state.error?.message || "" });
        const record = p.state.metadata?.[META];
        if (p.name === TOOL && isRecord(record)) records.set(p.id, record);
      }
      return { index: indexOperations(operations, [...records.values()]), records, operations };
    }
    registrations.push(await ctx.tool.transform((editor) => {
      editor.add({ name: TOOL, options: { codemode: false }, description: DESCRIPTION + ` Current window: ${window} completed operations.`,
        input: { type: "object", properties: { ids: { type: "array", minItems: 1, items: { type: "integer", minimum: 1 } }, note: { type: "string", minLength: 1 } }, required: ["ids", "note"], additionalProperties: false },
        async execute({ ids, note }, context) {
          const { index, operations } = await history(context.sessionID);
          if (!operations.some((op) => op.key === context.id && op.tool === TOOL)) throw new Error("请直接调用 context_rewrite，不能嵌套在 codemode 内");
          const record = makeRecord(index, visible.get(context.sessionID) ?? new Map(), ids, note, window);
          return { content: artifact(record), metadata: { [META]: record } };
        },
      });
    }));
    registrations.push(await ctx.session.hook("context", async (e) => {
      const { index, records } = await history(e.sessionID);
      const shown = new Map();
      visible.set(e.sessionID, shown);
      e.messages = e.messages.map((m) => {
        const removed = m.content.some((p) => ["tool-call", "tool-result"].includes(p.type) && index.removed.has(p.id));
        const content = m.content.filter((p) => !["tool-call", "tool-result"].includes(p.type) || !index.removed.has(p.id)).map((p) => {
        if (p.type !== "tool-result") return p;
        const record = records.get(p.id), op = index.byKey.get(p.id);
        if (!record && !op) return p;
        if (op) shown.set(op.id, op.key);
        const convert = (text) => record ? text.replace(artifact(record), artifact(record, false)) : `${marker(op)}\n${text}`;
        const result = p.result.type === "content" ? { ...p.result, value: p.result.value.map((c) => c.type === "text" ? { ...c, text: convert(c.text) } : c) }
          : { ...p.result, value: convert(typeof p.result.value === "string" ? p.result.value : JSON.stringify(p.result.value)) };
        return { ...p, result };
        });
        return { ...m, content: removed && content.every((p) => p.type === "reasoning") ? [] : content };
      }).filter((m) => m.content.length > 0);
    }));
    return async () => { for (const r of registrations.reverse()) await r.dispose(); };
  },
};
