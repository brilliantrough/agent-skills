import { tool } from "@opencode-ai/plugin";
import { createOutputStore, OUTPUT_META, READ_TOOL, READ_DESCRIPTION } from "../../context-rewrite/output-store.mjs";
import { TOOL, META, DESCRIPTION, windowSize, indexOperations, makeRecord, artifact, marker, isRecord } from "../../context-rewrite/core.mjs";

function snapshot(message) {
  const operations = [];
  const records = [];
  if (message.info.role === "assistant") for (const part of message.parts) {
    if (part.type !== "tool") continue;
    operations.push({ key: part.callID, tool: part.tool, finished: ["completed", "error"].includes(part.state.status),
      text: part.state.output ?? part.state.error ?? "",
    });
    const record = part.state.metadata?.[META];
    if (part.tool === TOOL && part.state.status === "completed" && isRecord(record)) records.push([part.callID, record]);
  }
  return { id: message.info.id, operations, records };
}

export default async function ContextRewrite({ client, directory }) {
  const window = windowSize();
  const outputStore = createOutputStore();
  const visibleBySession = new Map();
  const rowsBySession = new Map();
  async function readHistory(sessionID) {
    async function fetch(limit) {
      const result = await client.session.messages({ path: { id: sessionID }, query: { directory, ...(limit ? { limit } : {}) } });
      if (result.error || !Array.isArray(result.data)) throw new Error("context_rewrite 无法读取当前会话原始记录");
      return result.data;
    }
    const cached = rowsBySession.get(sessionID);
    let page = await fetch(cached ? window + 1 : undefined);
    let overlap = cached?.findIndex((row) => row.id === page[0]?.info.id) ?? -1;
    if (cached && (overlap < 0 || !page.some((m) => m.info.id === cached.at(-1)?.id))) {
      page = await fetch(); // 历史被回退或两次调用之间新增超过一页；重建当前分支编号。
      overlap = -1;
    }
    const rows = [...(overlap >= 0 ? cached.slice(0, overlap) : []), ...page.map(snapshot)];
    const operations = rows.flatMap((r) => r.operations);
    const records = new Map(rows.flatMap((r) => r.records));
    const recent = new Set(operations.filter((op) => op.finished && op.tool !== TOOL).slice(-window));
    for (const op of operations) if (!recent.has(op)) delete op.text;
    rowsBySession.set(sessionID, rows);
    return {
      index: indexOperations(operations, [...records.values()]), records,
      directCalls: new Set(operations.filter((op) => op.tool === TOOL).map((op) => op.key)),
    };
  }

  return {
    tool: {
      [READ_TOOL]: tool({
        description: READ_DESCRIPTION,
        args: {
          id: tool.schema.string().regex(/^[a-f0-9]{64}$/).describe("context_output 的完整 id"),
          offset: tool.schema.number().int().nonnegative().optional().describe("UTF-8 字节偏移；使用上页 next_offset，不是行号"),
          full: tool.schema.boolean().optional().describe("显式取回全文，不再自动外置；默认分页"),
        },
        // 正文在 after hook 填入，避免插件工具的原生 50 KiB 截断再次裁掉显式取回。
        async execute() { return { title: "外置原文取回", output: "" }; },
      }),
      [TOOL]: tool({
        description: DESCRIPTION + ` Current window: ${window} completed operations.`,
        args: {
          ids: tool.schema.array(tool.schema.number().int().positive()).min(1).describe("要撤下的 context_op 数字 ID；不是 Magic Context tag"),
          note: tool.schema.string().min(1).describe("保留的事实、错误原因与下一步正确做法；纯文本，不重复原始大输出"),
        },
        async execute({ ids, note }, ctx) {
          const { index, directCalls } = await readHistory(ctx.sessionID);
          if (!directCalls.has(ctx.callID)) throw new Error("请直接调用 context_rewrite，不能包在 batch/codemode 内；嵌套调用无法持久化裁剪记录");
          const record = makeRecord(index, visibleBySession.get(ctx.sessionID) ?? new Map(), ids, note, window);
          return { title: "近期上下文纠正", output: artifact(record), metadata: { [META]: record } };
        },
      }),
    },
    async "tool.execute.after"(input, output) {
      if (input.callID?.includes("/")) return; // OpenCode codemode 子调用返回原数据供脚本计算。
      if (input.tool === READ_TOOL) {
        output.output = await outputStore.retrieve(input.args);
        return;
      }
      const metadata = output.metadata ?? {};
      // read 注入的项目指令不隐藏；下一次不再携带指令时可正常外置。
      if (input.tool === "read" && metadata.loaded?.length) return;
      const mcpContent = Array.isArray(output.content) ? output.content : undefined;
      const texts = mcpContent ? mcpContent.flatMap((p) => p.type === "text" ? [p.text]
        : p.type === "resource" && typeof p.resource?.text === "string" ? [p.resource.text] : [])
        : typeof output.output === "string" ? [output.output] : [];
      const fullOutputPath = !mcpContent && metadata.truncated ? metadata.outputPath : undefined;
      const filePath = input.tool === "read" && metadata.display?.type === "file" ? metadata.display.path : undefined;
      try {
        const record = await outputStore.capture(texts, {
          tool: input.tool, input: input.args, sourcePath: fullOutputPath ?? filePath,
          force: Boolean(fullOutputPath || (filePath && metadata.truncated && input.args.limit === undefined)),
          scope: fullOutputPath ? "host_saved_output_completeness_unverified" : filePath ? "complete_file_snapshot" : "tool_result_snapshot_may_be_host_truncated",
          warning: fullOutputPath ? "The host spill file may already be incomplete. Retrieval returns exactly this snapshot; missing bytes cannot be recovered by this plugin." : undefined,
          status: metadata.exit !== undefined ? `exit_code=${metadata.exit}` : output.isError ? "error" : "completed",
        });
        if (!record) return;
        if (mcpContent) output.content = [{ type: "text", text: record.pointer }, ...mcpContent.filter((p) =>
          p.type !== "text" && !(p.type === "resource" && typeof p.resource?.text === "string"))];
        else output.output = record.pointer;
        output.metadata = { ...metadata, [OUTPUT_META]: record };
      } catch (error) {
        console.error("[context_output] 保存失败，保留原始输出：", error);
      }
    },
    async "experimental.chat.messages.transform"(_input, output) {
      const sessionID = output.messages.find((m) => m.info.sessionID)?.info.sessionID;
      if (!sessionID) return;
      const { index, records } = await readHistory(sessionID);
      const visible = new Map();
      visibleBySession.set(sessionID, visible);
      for (let i = 0; i < output.messages.length; i++) {
        const original = output.messages[i];
        if (original.info.role !== "assistant") continue;
        const message = { ...original };
        output.messages[i] = message;
        const removedCall = message.parts.some((p) => p.type === "tool" && index.removed.has(p.callID));
        message.parts = message.parts.filter((p) => p.type !== "tool" || !index.removed.has(p.callID)).map((part) => {
          if (part.type !== "tool" || !["completed", "error"].includes(part.state.status)) return part;
          const record = records.get(part.callID);
          if (record) return { ...part, state: { ...part.state,
            output: part.state.output.replace(artifact(record), artifact(record, false)),
          } };
          const op = index.byKey.get(part.callID);
          if (!op) return part;
          visible.set(op.id, op.key);
          const state = { ...part.state };
          if (state.status === "completed") state.output = `${marker(op)}\n${state.output}`;
          else if (state.metadata?.interrupted && typeof state.metadata.output === "string") {
            state.metadata = { ...state.metadata, output: `${marker(op)}\n${state.metadata.output}` };
          } else state.error = `${marker(op)}\n${state.error}`;
          return { ...part, state };
        });
        if (removedCall && message.parts.every((p) => ["reasoning", "step-start", "step-finish"].includes(p.type))) message.parts = [];
      }
      // 宿主保留 msgs 原引用：须原地删空消息，不能只赋值 output.messages。
      for (let i = output.messages.length - 1; i >= 0; i--) {
        if (output.messages[i].info.role === "assistant" && output.messages[i].parts.length === 0) output.messages.splice(i, 1);
      }
    },
    async event({ event }) {
      if (event.type === "session.deleted") {
        visibleBySession.delete(event.properties.info.id);
        rowsBySession.delete(event.properties.info.id);
      }
    },
  };
}
