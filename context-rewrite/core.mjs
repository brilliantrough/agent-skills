// 两端共用：acp-kernel 局部吸收 API；不运行全局压缩流水线。
import { applyAbsorb, assignRefs, createInitialState, defaultConfig, hideAbsorbedMessages, refForRaw, refToIndex } from "acp-kernel";

export const TOOL = "context_rewrite";
export const META = "agentSkillsContextRewrite";
export const DESCRIPTION =
  "Replace recent low-value tool operations in FUTURE model context with a correction note. " +
  "Use after an oversized read, wrong cwd/environment/flags, or an abandoned approach; " +
  "keep the useful finding and exact next action (e.g. targeted read or ctxm_execute_file). " +
  "Copy numeric IDs from [context_op id=N], NOT Magic Context tags. Only the latest completed " +
  "operations within the configured window (default 10) qualify. Call directly, not inside a batch/codemode, " +
  "after observing results; then run the corrected operation separately. A batch is one operation: " +
  "do not discard useful sibling results. Inputs and outputs leave future requests; original history is " +
  "retained, filesystem/process side effects are NOT undone. The removed operations already ran: " +
  "do not repeat them merely because their raw messages are absent; retry only with the intended correction. " +
  "Do not remove unresolved evidence, " +
  "user instructions, or facts needed for the task. Only the unchanged earlier cache prefix can be reused.";

const callId = (key) => `call:${key}`;
const resultId = (key) => `result:${key}`;
const config = defaultConfig(1, { protectedTools: [TOOL] });

export function windowSize() {
  const n = Number(process.env.CONTEXT_REWRITE_WINDOW ?? 10);
  if (!Number.isSafeInteger(n) || n < 1) throw new Error("CONTEXT_REWRITE_WINDOW 必须是正整数");
  return n;
}

// 从当前原始分支编号；运行中的调用也占号，避免并行完成顺序改变已有 ID。
export function indexOperations(operations, records) {
  const unique = [...new Map(operations.filter((op) => op.tool !== TOOL).map((op) => [op.key, op])).values()];
  const state = createInitialState();
  const messages = unique.flatMap((op) => [
    { id: callId(op.key), role: "assistant", contentType: "tool-call", toolName: op.tool, toolCallId: op.key },
    { id: resultId(op.key), role: "tool", contentType: "tool-result", toolName: op.tool, toolCallId: op.key, text: op.text ?? "" },
  ]);
  state.messageRefs = assignRefs(messages.filter((m) => m.contentType === "tool-result"), {
    existing: state.messageRefs, nextIndex: 1,
  }).map;
  state.absorbed = records.flatMap((r) => r.targets);
  const remaining = new Set(hideAbsorbedMessages(messages, state).map((m) => m.id));
  const byKey = new Map(unique.map((op) => [op.key, { ...op, id: refToIndex(refForRaw(state.messageRefs, resultId(op.key))) }]));
  const removed = new Set(unique.filter((op) => !remaining.has(resultId(op.key))).map((op) => op.key));
  return { operations: [...byKey.values()], byKey, removed, messages, state };
}

export function makeRecord(index, visible, ids, note, window) {
  if (!Array.isArray(ids) || !ids.length || ids.some((id) => !Number.isSafeInteger(id) || id < 1)) {
    throw new Error("ids 必须是非空正整数数组，来自 [context_op id=N]");
  }
  if (typeof note !== "string" || !note.trim()) throw new Error("note 必须写明应保留的结论及下一步做法");
  // 已撤下的操作仍占窗口位置；不能靠连续裁剪向旧历史挖掘。
  const recent = index.operations.filter((op) => op.finished).slice(-window);
  let state = index.state;
  const targets = [...new Set(ids)].map((id) => {
    const op = recent.find((candidate) => candidate.id === id);
    if (!op || index.removed.has(op.key) || visible.get(id) !== op.key) {
      const available = recent.filter((o) => !index.removed.has(o.key) && visible.get(o.id) === o.key);
      throw new Error(`操作 ${id} 不在最近 ${window} 次已完成且已展示的可撤操作内；可用 ID：${available.map((o) => o.id).join(", ") || "无"}`);
    }
    const outcome = applyAbsorb({
      ref: refForRaw(state.messageRefs, resultId(op.key)), summary: note.trim(),
      messages: index.messages, state, config,
    });
    if (!outcome.ok) throw new Error(outcome.resultText);
    state = outcome.state;
    return { ...state.absorbed.at(-1), id: op.id, tool: op.tool };
  });
  return { version: 1, targets, note: note.trim() };
}

export function artifact(record, includeNote = true) {
  return `[context_rewrite]\noperations: ${record.targets.map((t) => `${t.id}:${t.tool}`).join(", ")}\n` +
    "effect: inputs_and_outputs_removed_from_future_context; originals_retained; side_effects_not_undone\n" +
    "record: these operations already ran; do not repeat without a correction\n" +
    (includeNote ? `note:\n${record.note}\n` : "") + "[/context_rewrite]";
}

export function marker(op) {
  return `[context_op id=${op.id} tool=${op.tool}]`;
}

export function isRecord(value) {
  return value?.version === 1 && Array.isArray(value.targets) && value.targets.length > 0 &&
    value.targets.every((t) => Number.isSafeInteger(t.id) && typeof t.toolCallId === "string" &&
      t.callMessageId === callId(t.toolCallId) && t.resultMessageId === resultId(t.toolCallId) && typeof t.tool === "string") &&
    typeof value.note === "string";
}
