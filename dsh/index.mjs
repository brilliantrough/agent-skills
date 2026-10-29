import { createUserMessage } from "@deepseek-ai/dsh-llm";
import { defineTool } from "@deepseek-ai/dsh-tools";
import { DESCRIPTION, TOOL, artifact, indexOperations, isRecord, makeRecord, marker, windowSize } from "../context-rewrite/core.mjs";
import { createOutputStore, READ_DESCRIPTION, READ_TOOL } from "../context-rewrite/output-store.mjs";

export const name = "agent-skills-context";
export const inject = ["tools", "sessions"];
const text = (content) => content.filter((b) => b.type === "text").map((b) => b.text).join("\n");
const output = { schema: { type: "string" }, render: (_args, value) => [{ type: "text", text: value }] };
const SOURCE = "agent-skills-context-rewrite";

// 同一 assistant 消息的并行调用作为一个操作，不能只撤下其中的有用分支。
export function history(session) {
  const events = session.snapshotEvents();
  const records = events.filter((e) => e.type === "user/message" && e.data.source?.kind === SOURCE)
    .map((e) => e.data.source.record).filter(isRecord);
  const completed = new Map(events.filter((e) => e.type === "tool/result").map((e) => [e.data.message.toolCallId, e]));
  const operations = events.filter((e) => e.type === "assistant/message").flatMap((assistant) => {
    const calls = assistant.data.message.content.filter((b) => b.type === "tool-call");
    if (!calls.length || calls.some((c) => c.name === TOOL)) return [];
    const results = calls.flatMap((c) => completed.has(c.id) ? [completed.get(c.id)] : []);
    return [{ key: String(assistant.seq), tool: calls.map((c) => c.name).join("+"),
      finished: results.length === calls.length, assistant, results,
      text: results.map((r) => text(r.data.message.content)).join("\n") }];
  });
  return { index: indexOperations(operations, records) };
}

export function rewrite(session, ids, note, window) {
  const { index } = history(session);
  const visible = new Map(index.operations.filter((o) => o.text.includes(marker(o))).map((o) => [o.id, o.key]));
  const record = makeRecord(index, visible, ids, note, window);
  const ranges = record.targets.map((target) => {
    const op = index.byKey.get(target.toolCallId);
    const allowed = new Set([op.assistant.seq, ...op.results.map((r) => r.seq)]);
    const start = op.assistant.seq, end = Math.max(...allowed);
    const nodes = session.surface.nodes.filter((seq) => seq >= start && seq <= end);
    if (!nodes.length || nodes.length !== allowed.size || nodes.some((seq) => !allowed.has(seq))) {
      throw new Error(`操作 ${op.id} 已被压缩，或与其它上下文交错；保留原历史`);
    }
    return { op, nodes, start, end };
  });
  for (const [i, range] of ranges.entries()) {
    const retained = text(range.op.assistant.data.message.content);
    const message = createUserMessage({
      content: [{ type: "text", text: (retained ? retained + "\n" : "") + artifact(record) }],
      source: { kind: SOURCE, ...(i === 0 ? { record } : {}) },
    });
    session.append("user/message", message, {
      surfaceOp: { op: "replace", startSeq: range.start, endSeq: range.end }, sourceEventSeqs: range.nodes,
    });
  }
  return artifact(record);
}

export function apply(ctx) {
  const window = windowSize(), store = createOutputStore();
  ctx.tools.register(defineTool({
    name: TOOL, description: DESCRIPTION + " In DSH, all tool calls in one assistant step are one operation.",
    parameters: { ids: { type: "array", items: { type: "integer" }, required: true }, note: { type: "string", required: true } },
    output,
    async execute({ ids, note }, exec) {
      if (!exec.agent || exec.parent) throw new Error("请在当前会话直接调用 context_rewrite，不能通过批处理或嵌套调用");
      exec.signal.throwIfAborted();
      return rewrite(exec.agent.session, ids, note, window);
    },
  }));
  ctx.tools.register(defineTool({
    name: READ_TOOL, description: READ_DESCRIPTION,
    parameters: { id: { type: "string", required: true }, offset: { type: "integer" }, full: { type: "boolean" } },
    output, async execute(args, exec) { return store.retrieve(args, exec.signal); },
  }));
  ctx.on("tools/post-execute", async (exec, result, next) => {
    const decision = await next();
    if (!exec.agent || exec.parent || decision.kind !== "accept" || exec.name === TOOL) return decision;
    const content = decision.content ?? result.content;
    // 有其它策略改写结构化 value 时，保留它的权威输出。
    if (Object.hasOwn(decision, "value")) return decision;
    let projected = content;
    try {
      const saved = await store.capture(content.filter((b) => b.type === "text").map((b) => b.text), {
        tool: exec.name, input: exec.arguments, status: result.isError ? "error" : "completed",
      });
      if (saved) projected = [{ type: "text", text: saved.pointer }, ...content.filter((b) => b.type !== "text")];
    } catch (error) { ctx.logger.warn("[context_output] 保存失败，保留原输出：%s", String(error)); }
    const { index } = history(exec.agent.session);
    const op = index.operations.find((o) => o.assistant.data.message.content.some((c) => c.type === "tool-call" && c.id === exec.rootCallId));
    return { ...decision, content: op ? [{ type: "text", text: marker(op) }, ...projected] : projected };
  });
}
