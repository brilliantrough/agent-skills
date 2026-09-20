// Wrapper for claude-mem's OpenCode plugin. Three jobs:
// 1) Upstream bug fix (thedotmack/claude-mem#2854/#3328): the bundle exports
//    non-function constants and opencode's loader requires every export to be a
//    plugin function, so we re-export only the plugin function.
// 2) User-prompt capture: upstream's chat.message handler returns early unless
//    role === "assistant", but opencode delivers UserMessage objects to that
//    hook, so upstream never records user input. We record every user prompt
//    through the same /api/sessions/init route Claude Code uses (user_prompts +
//    FTS + Chroma + the observer's <user_request>), and pin one
//    contentSessionId per session so our init and the plugin's observations
//    share one session row. No extra LLM requests are made.
// 3) Prefix filtering: upstream's CLAUDE_MEM_SKIP_TOOLS only does exact
//    matches, so entries ending in "*" (e.g. "mcphub-web_*") are honored here,
//    before the observation is POSTed.
// 4) Assistant capture: upstream's assistant branch is dead code, so we stash
//    the last completed assistant text of a turn and post it as one
//    observation when the session goes idle — one observer request per turn
//    instead of one per model step.
// 源文件就在本仓(agent-skills)opencode/plugins/claude-mem-wrapper.js,由 opencode-setup.sh 下载部署。
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
// 上游 lib/claude-mem.js 在 import 时就把 worker 地址算成 env ?? 内置默认公式(不读 settings.json),
// 所以必须在 import 之前把 settings 里的 host/port 喂给 env,否则只改 settings 的端口会让上游请求打到旧端口。

const JSON_HEADERS = { "Content-Type": "application/json" };

function loadSkipPrefixes() {
  try {
    const dataDir = process.env.CLAUDE_MEM_DATA_DIR || join(homedir(), ".claude-mem");
    const value =
      JSON.parse(readFileSync(join(dataDir, "settings.json"), "utf-8")).CLAUDE_MEM_SKIP_TOOLS || "";
    return value
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.endsWith("*"))
      .map((s) => s.slice(0, -1));
  } catch {
    return [];
  }
}

const SKIP_PREFIXES = loadSkipPrefixes();
const MAX_ASSISTANT_CHARS = 5000;

// 与 claude-mem 本身的优先级一致:环境变量 > ~/.claude-mem/settings.json > 默认公式
function workerSetting(key) {
  try {
    const p = join(process.env.CLAUDE_MEM_DATA_DIR || join(homedir(), ".claude-mem"), "settings.json");
    return JSON.parse(readFileSync(p, "utf8"))[key] || "";
  } catch {
    return "";
  }
}

for (const key of ["CLAUDE_MEM_WORKER_HOST", "CLAUDE_MEM_WORKER_PORT"]) {
  if (!process.env[key]) {
    const fromSettings = workerSetting(key);
    if (fromSettings) process.env[key] = fromSettings;
  }
}

const { ClaudeMemPlugin } = await import("../lib/claude-mem.js");

function resolveWorkerBaseUrl() {
  const host =
    process.env.CLAUDE_MEM_WORKER_HOST ||
    workerSetting("CLAUDE_MEM_WORKER_HOST") ||
    "127.0.0.1";
  const port =
    process.env.CLAUDE_MEM_WORKER_PORT ||
    workerSetting("CLAUDE_MEM_WORKER_PORT") ||
    String(37700 + ((process.getuid?.() ?? 77) % 100));
  return `http://${host}:${port}`;
}

const WORKER_BASE_URL = resolveWorkerBaseUrl();

function sessionIdFromContentSessionId(contentSessionId) {
  return String(contentSessionId).replace(/^opencode-/, "").replace(/-\d+$/, "");
}

function textOf(parts) {
  return (parts || [])
    .filter((p) => p && p.type === "text" && typeof p.text === "string")
    .map((p) => p.text)
    .join("\n")
    .trim();
}

export default async function (ctx) {
  const project = ctx?.project?.name || "opencode";
  const sessions = new Map(); // opencode sessionID -> { cid, lastPrompt }
  let chatMessageWorks = false;

  function sessionFor(sessionID) {
    let s = sessions.get(sessionID);
    if (!s) {
      s = { cid: `opencode-${sessionID}-${Date.now()}`, lastPrompt: "" };
      sessions.set(sessionID, s);
    }
    return s;
  }

  function recordPrompt(sessionID, text) {
    if (!sessionID || !text) return;
    const s = sessionFor(sessionID);
    if (text === s.lastPrompt) return;
    s.lastPrompt = text;
    fetch(`${WORKER_BASE_URL}/api/sessions/init`, {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({ contentSessionId: s.cid, project, prompt: text }),
    }).catch(() => {});
  }

  function recordAssistant(sessionID, text) {
    if (!sessionID || !text) return;
    const s = sessionFor(sessionID);
    fetch(`${WORKER_BASE_URL}/api/sessions/observations`, {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({
        contentSessionId: s.cid,
        tool_name: "assistant_message",
        tool_input: {},
        tool_response: text.length > MAX_ASSISTANT_CHARS ? text.slice(0, MAX_ASSISTANT_CHARS) : text,
        cwd: ctx?.directory || "",
      }),
    }).catch(() => {});
  }

  // Rewrite the plugin's worker-bound bodies: one contentSessionId per session
  // (so init + observations land on the same row) and fill the plugin's empty
  // init prompt with the latest user text (the route dedupes repeats).
  const originalFetch = globalThis.fetch;
  globalThis.fetch = function (input, init) {
    try {
      if (init && typeof init.body === "string" && String(input).includes("/api/sessions/")) {
        const body = JSON.parse(init.body);
        if (body && typeof body.contentSessionId === "string") {
          const s = sessions.get(sessionIdFromContentSessionId(body.contentSessionId));
          if (s) {
            body.contentSessionId = s.cid;
            if (!body.prompt && s.lastPrompt) body.prompt = s.lastPrompt;
            init = { ...init, body: JSON.stringify(body) };
          }
        }
      }
    } catch {}
    return originalFetch.call(this, input, init);
  };

  const hooks = await ClaudeMemPlugin(ctx);
  const upstreamChatMessage = hooks["chat.message"];
  const upstreamDispose = hooks.dispose;

  hooks["chat.message"] = async (input, output) => {
    try {
      if (output?.message?.role === "user") {
        const text = textOf(output.parts);
        if (text) {
          chatMessageWorks = true;
          recordPrompt(input?.sessionID, text);
        }
      }
    } catch {}
    if (upstreamChatMessage) return upstreamChatMessage(input, output);
  };

  // Backup for opencode builds where chat.message no longer fires. Used only
  // until the primary hook proves alive, so synthetic compaction/title user
  // messages are never captured.
  hooks["experimental.chat.messages.transform"] = async (_input, output) => {
    if (chatMessageWorks) return;
    try {
      const messages = output?.messages || [];
      for (let i = messages.length - 1; i >= 0; i--) {
        const entry = messages[i];
        if (entry?.info?.role === "user") {
          recordPrompt(entry.info.sessionID, textOf(entry.parts));
          break;
        }
      }
    } catch {}
  };

  // Assistant capture, part 1: stash every completed assistant text part.
  // Kept out of the observer until the turn ends (see below) to avoid one
  // request per model step.
  hooks["experimental.text.complete"] = async (input, output) => {
    try {
      const s = sessionFor(input?.sessionID);
      const text = String(output?.text ?? "").trim();
      if (text && text !== s.lastPrompt) s.pendingAssistant = text;
    } catch {}
  };

  // Assistant capture, part 2: on session idle, post the turn's final text as
  // one observation.
  const upstreamEvent = hooks.event;
  hooks.event = async (input) => {
    try {
      const event = input?.event;
      if (event?.type === "session.idle") {
        const sessionID = event.properties?.sessionID || event.properties?.info?.id;
        const s = sessionID ? sessions.get(sessionID) : undefined;
        if (s?.pendingAssistant) {
          const text = s.pendingAssistant;
          s.pendingAssistant = "";
          recordAssistant(sessionID, text);
        }
      }
    } catch {}
    if (upstreamEvent) return upstreamEvent(input);
  };

  const upstreamToolAfter = hooks["tool.execute.after"];
  if (upstreamToolAfter) {
    hooks["tool.execute.after"] = async (input, output) => {
      if (input?.tool && SKIP_PREFIXES.some((p) => input.tool.startsWith(p))) return;
      return upstreamToolAfter(input, output);
    };
  }

  hooks.dispose = async () => {
    globalThis.fetch = originalFetch;
    if (upstreamDispose) await upstreamDispose();
  };

  return hooks;
}
