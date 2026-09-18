import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
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

/** Pi 装的包(settings.json 的 packages[])及各包版本;git 附短 SHA。 */
export function installedPackages(): { name: string; version: string }[] {
  const agentDir = getAgentDir();
  let sources: unknown;
  try {
    sources = JSON.parse(readFileSync(join(agentDir, "settings.json"), "utf8"))?.packages;
  } catch {
    return [];
  }
  if (!Array.isArray(sources)) return [];
  const rows: { name: string; version: string }[] = [];
  for (const source of sources) {
    if (typeof source !== "string") continue;
    const spec = source.startsWith("npm:") ? source.slice(4) : source;
    const at = spec.lastIndexOf("@");
    const name = at > 0 ? spec.slice(0, at) : spec;
    let dir: string;
    if (source.startsWith("npm:")) dir = join(agentDir, "npm/node_modules", name);
    else if (source.startsWith("git:")) dir = join(agentDir, "git", source.slice(4));
    else dir = source.replace(/^~/, process.env.HOME ?? "");
    let version = "?";
    try {
      version = JSON.parse(readFileSync(join(dir, "package.json"), "utf8")).version ?? "?";
    } catch {
      continue; // 目录不在(还没装/已删):列表不显示幽灵包
    }
    if (dir.includes("/git/")) {
      try {
        const sha = execFileSync("git", ["-C", dir, "rev-parse", "--short", "HEAD"], {
          encoding: "utf8",
          stdio: ["ignore", "pipe", "ignore"],
        }).trim();
        if (sha) version = `${version}·${sha}`;
      } catch {
        // 不是 git 仓库就用 package.json 的版本
      }
    }
    rows.push({ name: name.replace(/^.*\//, ""), version });
  }
  return rows;
}

export default function (pi: ExtensionAPI) {
  let cache: ReturnType<typeof registerSidebarPanel> | undefined;
  let tasks: ReturnType<typeof registerSidebarPanel> | undefined;
  let packages: ReturnType<typeof registerSidebarPanel> | undefined;
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
  function updatePackages() {
    const installed = installedPackages();
    packages?.update({ id: "agent-skills:packages", title: `Plugins · ${installed.length}`, rows:
      installed.length ? installed.map(pkg => `${pkg.name} ${pkg.version}`) : ["No Pi packages installed"],
    });
  }
  pi.on("session_start", (_event, ctx) => {
    cache?.dispose(); tasks?.dispose(); packages?.dispose();
    if (ctx.mode !== "tui") return;
    cache = registerSidebarPanel(pi, { id: "agent-skills:cache", title: "Cache", rows: [] });
    tasks = registerSidebarPanel(pi, { id: "agent-skills:todos", title: "Tasks", rows: [] });
    packages = registerSidebarPanel(pi, { id: "agent-skills:packages", title: "Plugins", rows: [] });
    updatePackages();
    update(ctx);
  });
  pi.on("message_end", (_event, ctx) => update(ctx));
  pi.on("agent_settled", (_event, ctx) => update(ctx));
  pi.on("session_tree", (_event, ctx) => update(ctx));
  pi.on("session_compact", (_event, ctx) => update(ctx));
  pi.on("session_shutdown", (_event, ctx) => {
    cache?.dispose(); tasks?.dispose(); packages?.dispose();
    cache = tasks = packages = undefined;
    if (ctx.mode === "tui") ctx.ui.setWidget("agent-skills:usage", undefined);
  });
}
