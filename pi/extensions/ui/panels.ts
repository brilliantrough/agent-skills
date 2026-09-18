import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { registerSidebarPanel } from "./atelier/src/sidebar-panels.js";
import { aggregateMetrics, formatTokens } from "./atelier/src/metrics.js";

type Todo = { content: string; status: string };
const validTodos = (items: unknown): items is Todo[] => Array.isArray(items) && items.every(
  item => item && typeof item.content === "string" && ["pending", "in_progress", "completed", "cancelled"].includes(item.status),
);

// Read the existing tool history; never create a second task store or tool.
export function sessionTodos(entries: readonly any[]): Todo[] {
  const calls = new Map<string, Todo[]>();
  let todos: Todo[] = [];
  for (const entry of entries) {
    if (entry.type !== "message") continue;
    const message = entry.message;
    if (message.role === "assistant" && Array.isArray(message.content)) {
      for (const block of message.content) {
        if (block.type === "toolCall" && block.name === "todowrite" && validTodos(block.arguments?.todos)) {
          calls.set(block.id, block.arguments.todos);
        }
      }
    }
    if (message.role === "toolResult" && message.toolName === "todowrite" && !message.isError) {
      const snapshot = calls.get(message.toolCallId);
      if (snapshot) todos = snapshot;
    }
  }
  return todos;
}

export default function (pi: ExtensionAPI) {
  let cache: ReturnType<typeof registerSidebarPanel> | undefined;
  let tasks: ReturnType<typeof registerSidebarPanel> | undefined;
  function update(ctx: ExtensionContext) {
    if (ctx.mode !== "tui") return;
    // Same assistant-only accounting as Atelier's footer, including validity checks.
    const messages = ctx.sessionManager.getEntries().flatMap(entry =>
      entry.type === "message" && entry.message.role === "assistant" ? [entry.message] : []);
    const metrics = aggregateMetrics(messages, { subscription: false, autoCompact: null });
    cache?.update({ id: "agent-skills:cache", title: "Cache · session", rows: [
      `R ${formatTokens(metrics.cacheRead)}  W ${formatTokens(metrics.cacheWrite)}`,
      "HΣ session · H₁ last request",
    ] });
    const todos = sessionTodos(ctx.sessionManager.getBranch());
    const done = todos.filter(todo => todo.status === "completed").length;
    const cancelled = todos.filter(todo => todo.status === "cancelled").length;
    const active = [
      ...todos.filter(todo => todo.status === "in_progress"),
      ...todos.filter(todo => todo.status === "pending"),
    ];
    const summary = `✓ ${done}/${todos.length} completed${cancelled ? ` · ${cancelled} cancelled` : ""}`;
    tasks?.update({ id: "agent-skills:todos", title: `Tasks · ${done}/${todos.length}`, rows:
      !todos.length ? ["No tasks in this branch"] : !active.length ? [summary] : [
        ...active.slice(0, 22).map(todo => ({
          text: `${todo.status === "in_progress" ? "▶" : "○"} ${todo.content}`,
          role: todo.status === "in_progress" ? "working" as const : "muted" as const,
        })),
        ...(active.length > 22 ? [`+${active.length - 22} more · /todos`] : []),
        ...(done || cancelled ? [summary] : []),
      ],
    });
  }
  pi.on("session_start", (_event, ctx) => {
    cache?.dispose(); tasks?.dispose();
    if (ctx.mode !== "tui") return;
    cache = registerSidebarPanel(pi, { id: "agent-skills:cache", title: "Cache", rows: [] });
    tasks = registerSidebarPanel(pi, { id: "agent-skills:todos", title: "Tasks", rows: [] });
    update(ctx);
  });
  pi.on("message_end", (_event, ctx) => update(ctx));
  pi.on("agent_settled", (_event, ctx) => update(ctx));
  pi.on("session_tree", (_event, ctx) => update(ctx));
  pi.on("session_compact", (_event, ctx) => update(ctx));
  pi.on("session_shutdown", (_event, ctx) => {
    cache?.dispose(); tasks?.dispose(); cache = tasks = undefined;
    if (ctx.mode === "tui") ctx.ui.setWidget("agent-skills:usage", undefined);
  });
}
