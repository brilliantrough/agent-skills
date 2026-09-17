// claude-mem bridge for Pi.
// 与 OpenCode 插件共用同一套 claude-mem worker API 契约:
//   POST /api/sessions/init | /api/sessions/observations | /api/sessions/summarize
// 采集范围:工具调用、助手消息、以及用户 prompt(经 init 写入 user_prompts/FTS/Chroma,
// 供 observer 的 <user_request> 和后续会话注入使用),并提供与 skills 里同名的
// claude_mem_search 工具(直连 worker,无需 MCP)。
// 作为 agent-skills Pi 包(pi.extensions)自动加载,随 `pi install` 分发。
import { readFileSync } from "node:fs";
import { basename, join } from "node:path";
import { homedir } from "node:os";

const MAX_TOOL_RESPONSE_LENGTH = 1000;
const MAX_ASSISTANT_LENGTH = 5000;

function resolveWorkerBaseUrl(): string {
  const dataDir = process.env.CLAUDE_MEM_DATA_DIR?.trim() || join(homedir(), ".claude-mem");
  let settings: Record<string, string> = {};
  try {
    settings = JSON.parse(readFileSync(join(dataDir, "settings.json"), "utf-8"));
  } catch {
    // worker 未装时按默认值继续,POST 失败会静默忽略
  }
  const host = process.env.CLAUDE_MEM_WORKER_HOST || settings.CLAUDE_MEM_WORKER_HOST || "127.0.0.1";
  const port =
    process.env.CLAUDE_MEM_WORKER_PORT ||
    settings.CLAUDE_MEM_WORKER_PORT ||
    String(37700 + ((process.getuid?.() ?? 77) % 100));
  return `http://${host}:${port}`;
}

const WORKER_BASE_URL = resolveWorkerBaseUrl();

// CLAUDE_MEM_SKIP_TOOLS 里以 "*" 结尾的条目按前缀匹配(worker 只做精确匹配,
// 这里在 POST 之前提前过滤,省掉无谓的本地请求)。
function loadSkipPrefixes(): string[] {
  try {
    const dataDir = process.env.CLAUDE_MEM_DATA_DIR?.trim() || join(homedir(), ".claude-mem");
    const settings = JSON.parse(readFileSync(join(dataDir, "settings.json"), "utf-8"));
    return String(settings.CLAUDE_MEM_SKIP_TOOLS || "")
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.endsWith("*"))
      .map((s) => s.slice(0, -1));
  } catch {
    return [];
  }
}

const SKIP_PREFIXES = loadSkipPrefixes();

function truncate(text: string, limit = MAX_TOOL_RESPONSE_LENGTH): string {
  return text.length > limit ? text.slice(0, limit) : text;
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((p: any) => p && p.type === "text" && typeof p.text === "string")
    .map((p: any) => p.text as string)
    .join("\n");
}

function post(path: string, body: Record<string, unknown>): void {
  fetch(`${WORKER_BASE_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...body, platformSource: "pi" }),
  }).catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes("ECONNREFUSED")) console.warn(`[claude-mem] POST ${path} failed: ${message}`);
  });
}

async function workerGetText(path: string): Promise<string | null> {
  try {
    const response = await fetch(`${WORKER_BASE_URL}${path}`, {
      headers: { "Content-Type": "application/json" },
    });
    if (!response.ok) return null;
    return await response.text();
  } catch {
    return null;
  }
}

function parseSearchResponse(text: string, query: string): string {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return "Failed to parse search results.";
  }
  const content = (data as { content?: Array<{ type?: string; text?: string }> }).content;
  if (!Array.isArray(content) || content.length === 0) return `No results found for "${query}".`;
  const rendered = content
    .filter((block) => block.type === "text" && typeof block.text === "string")
    .map((block) => block.text as string)
    .join("\n")
    .trim();
  return rendered || `No results found for "${query}".`;
}

export default function (pi: any) {
  let contentSessionId: string | undefined;
  let initialized = false;

  function ensure(ctx: any, prompt = ""): string {
    if (!contentSessionId) contentSessionId = `pi-${ctx.sessionManager.getSessionId()}-${Date.now()}`;
    if (!initialized) {
      initialized = true;
      post("/api/sessions/init", { contentSessionId, project: basename(ctx.cwd), prompt });
    }
    return contentSessionId;
  }

  pi.on("tool_execution_end", async (event: any, ctx: any) => {
    const toolName = String(event.toolName ?? "");
    if (SKIP_PREFIXES.some((p) => toolName.startsWith(p))) return;
    const id = ensure(ctx);
    const raw = event.result?.content !== undefined ? textOf(event.result.content) : String(event.result ?? "");
    post("/api/sessions/observations", {
      contentSessionId: id,
      tool_name: event.toolName,
      tool_input: event.args ?? {},
      tool_response: truncate(raw),
      cwd: ctx.cwd,
      tool_use_id: event.toolCallId,
    });
  });

  pi.on("message_end", async (event: any, ctx: any) => {
    const role = event.message?.role;
    if (role !== "assistant" && role !== "user") return;
    const text = textOf(event.message.content);
    if (!text) return;

    if (role === "user") {
      const hadSession = contentSessionId !== undefined;
      const id = ensure(ctx, text); // 会话第一条:init 直接带上 prompt,避免 [media prompt] 占位
      if (hadSession) {
        post("/api/sessions/init", { contentSessionId: id, project: basename(ctx.cwd), prompt: text });
      }
      return;
    }

    const id = ensure(ctx);
    post("/api/sessions/observations", {
      contentSessionId: id,
      tool_name: "assistant_message",
      tool_input: {},
      tool_response: truncate(text, MAX_ASSISTANT_LENGTH),
      cwd: ctx.cwd,
    });
  });

  const summarize = () => {
    if (!contentSessionId) return;
    post("/api/sessions/summarize", { contentSessionId, last_assistant_message: "" });
  };

  pi.on("agent_settled", async () => summarize());
  pi.on("session_shutdown", async () => {
    summarize();
    contentSessionId = undefined;
    initialized = false;
  });

  pi.registerTool({
    name: "claude_mem_search",
    label: "claude-mem search",
    description:
      "Search claude-mem memory database for past observations, sessions, and context (semantic search over captured tool activity and assistant messages).",
    promptSnippet: "Search claude-mem observations",
    parameters: {
      type: "object",
      properties: { query: { type: "string", description: "Search query for memory observations" } },
      required: ["query"],
    },
    async execute(_toolCallId: string, params: any) {
      const query = String(params?.query ?? "");
      if (!query) return { content: [{ type: "text", text: "Please provide a search query." }] };
      const text = await workerGetText(
        `/api/search/observations?query=${encodeURIComponent(query)}&limit=10`,
      );
      if (!text) {
        return {
          content: [
            {
              type: "text",
              text: `claude-mem worker is not reachable at ${WORKER_BASE_URL}. Start it with: cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart`,
            },
          ],
        };
      }
      return { content: [{ type: "text", text: parseSearchResponse(text, query) }] };
    },
  });
}
