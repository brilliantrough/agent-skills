import { join, resolve } from "node:path";
import { homedir } from "node:os";
import { createOutputStore, OUTPUT_META, READ_TOOL, READ_DESCRIPTION } from "../../context-rewrite/output-store.mjs";
import { TOOL, META, DESCRIPTION, windowSize, indexOperations, makeRecord, artifact, marker, isRecord } from "../../context-rewrite/core.mjs";

export default {
  id: "agent-skills.context-rewrite",
  async setup(ctx) {
    const window = windowSize();
    const store = createOutputStore();
    const visible = new Map();
    const calls = new Map();
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
      editor.update("shell", (tool) => {
        const execute = tool.execute;
        tool.execute = async (input, context) => {
          let shellID;
          const result = await execute(input, { ...context, progress: async (update) => {
            shellID = update.shellID ?? shellID;
            await context.progress(update);
          } });
          return { ...result, metadata: { ...result.metadata, ...(shellID ? { shellID } : {}) } };
        };
      });
      editor.add({ name: READ_TOOL, options: { codemode: false }, description: READ_DESCRIPTION,
        input: { type: "object", properties: { id: { type: "string", pattern: "^[a-f0-9]{64}$" }, offset: { type: "integer", minimum: 0 }, full: { type: "boolean" } }, required: ["id"], additionalProperties: false },
        execute: async (input, context) => ({ content: await store.retrieve(input, context.signal), metadata: { truncated: false } }),
      });
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
    registrations.push(await ctx.tool.hook("execute.before", (e) => {
      const key = `${e.sessionID}:${e.id}`;
      if (!calls.has(key)) calls.set(key, e.tool);
    }));
    registrations.push(await ctx.tool.hook("execute.after", async (e) => {
      const key = `${e.sessionID}:${e.id}`;
      if (calls.get(key) !== e.tool) return;
      calls.delete(key);
      if (e.status !== "completed" || e.tool === READ_TOOL) return;
      const r = e.result, metadata = r.metadata ?? {};
      if (metadata.status === "running") return;
      const spill = e.tool === "shell" && /^sh_[a-zA-Z0-9]+$/.test(metadata.shellID ?? "")
        ? join(process.env.XDG_DATA_HOME ?? join(homedir(), ".local/share"), "opencode", "shell", ctx.location.project.id, `${metadata.shellID}.out`)
        : metadata.truncated ? metadata.outputPath : undefined;
      const file = e.tool === "read" && r.output?.type !== "list-page" && r.output?.encoding !== "base64" ? resolve(ctx.location.directory, e.input.path) : undefined;
      try {
        const record = await store.capture(texts(r.content), {
          tool: e.tool, input: e.input, sourcePath: spill ?? file,
          force: Boolean((spill && metadata.truncated) || (file && metadata.truncated && e.input.limit === undefined)),
          scope: spill ? "host_saved_output" : file ? "complete_file_snapshot" : "tool_result_snapshot_may_be_host_truncated",
          status: metadata.exit !== undefined ? `exit_code=${metadata.exit}` : "completed",
        });
        if (!record) return;
        e.result = { ...r, content: [{ type: "text", text: record.pointer }, ...(Array.isArray(r.content) ? r.content.filter((p) => p.type !== "text") : [])], metadata: { ...metadata, [OUTPUT_META]: record } };
      } catch (error) { console.error("[context_output] 保存失败，保留原始输出：", error); }
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
