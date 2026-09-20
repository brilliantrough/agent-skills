// later — 延迟发送 prompt(挂机等实验结果):/later 5h 查看当前实验结果
// 同一套排程同时暴露为 LLM 工具 `later`:agent 可自己排程(如实验要跑 5h,排一个 5.5h 后的
// "查看运行结果并决定下一步"),到点以 followUp 注入当前会话,无需人在场。
// 计时器只活在当前 pi 进程内:退出/重启/切换会话(/new、/resume、/reload)会丢掉未触发的排程。
// 作为 agent-skills Pi 包(pi.extensions)自动加载。
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const UNIT: Record<string, number> = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 };

const hhmm = (t: number) => new Date(t).toTimeString().slice(0, 5);
const dur = (ms: number) => {
  if (ms < 60_000) return `${Math.max(0, Math.round(ms / 1000))}s`;
  const h = Math.floor(ms / 3_600_000);
  const m = Math.round((ms % 3_600_000) / 60_000);
  return h ? `${h}h${m}m` : `${m}m`;
};
const parseDelay = (s: string) => {
  const m = s.trim().match(/^(\d+(?:\.\d+)?)([smhd])$/);
  return m ? Number(m[1]) * UNIT[m[2]] : undefined;
};

export default function (pi: ExtensionAPI) {
  let nextId = 1;
  const pending = new Map<number, { id: number; at: number; timer: NodeJS.Timeout }>();
  let lastCtx: any;

  function status(ctx: any) {
    if (ctx) lastCtx = ctx;
    const c = ctx ?? lastCtx;
    if (pending.size === 0) return c?.ui?.setStatus?.("later", undefined);
    const soonest = Math.min(...[...pending.values()].map((p) => p.at));
    c?.ui?.setStatus?.("later", `⏰${pending.size} ${hhmm(soonest)}`);
  }

  function schedule(text: string, ms: number) {
    const id = nextId++;
    const at = Date.now() + ms;
    const timer = setTimeout(() => {
      pending.delete(id);
      // 挂机时 agent 可能正忙:followUp 在空闲时立即发送,忙时排队等本轮结束。
      pi.sendUserMessage(text, { deliverAs: "followUp" });
      status();
    }, ms);
    pending.set(id, { id, at, timer });
    status();
    return { id, at };
  }

  function cancel(ids: number[] | "all") {
    const targets =
      ids === "all" ? [...pending.keys()] : ids.filter((id) => pending.has(id));
    for (const id of targets) {
      clearTimeout(pending.get(id)!.timer);
      pending.delete(id);
    }
    status();
    return targets;
  }

  function listLines() {
    return [...pending.values()]
      .sort((a, b) => a.at - b.at)
      .map((p) => `#${p.id} ${hhmm(p.at)}(${dur(p.at - Date.now())}后)`);
  }

  pi.registerCommand("later", {
    description: "延迟发送 prompt:/later <时长> <prompt> | /later list | /later cancel <id|all>",
    handler: async (args: string, ctx: any) => {
      const arg = args.trim();

      if (arg === "" || arg === "list") {
        if (pending.size === 0) return ctx.ui.notify("没有待发送的 prompt", "info");
        return ctx.ui.notify(listLines().join("\n"), "info");
      }

      const cancelMatch = arg.match(/^cancel\s+(\d+|all)$/);
      if (cancelMatch) {
        const targets = cancel(cancelMatch[1] === "all" ? "all" : [Number(cancelMatch[1])]);
        if (targets.length === 0) return ctx.ui.notify("没有匹配的排程", "warning");
        return ctx.ui.notify(`已取消 ${targets.map((id) => `#${id}`).join(" ")}`, "info");
      }

      const parsed = arg.match(/^(\d+(?:\.\d+)?)([smhd])\s+([\s\S]+)$/);
      if (!parsed) {
        return ctx.ui.notify("用法:/later 5h 查看当前实验结果 | /later list | /later cancel <id|all>", "warning");
      }

      const [, n, unit, text] = parsed;
      const { id, at } = schedule(text, Number(n) * UNIT[unit]);
      ctx.ui.notify(`#${id} 将在 ${hhmm(at)}(${n}${unit}后)发送:${text}`, "info");
    },
  });

  pi.registerTool({
    name: "later",
    label: "later (定时自我唤醒)",
    description:
      "Schedule a prompt to be sent back to THIS session after a delay, as a real user message " +
      "(deliverAs=followUp: fires immediately if idle, queued until the current turn finishes if busy). " +
      "Use it to wait on long-running background work without a human present: estimate the duration, " +
      "add a safety margin, and schedule the next instruction to yourself (e.g. an experiment needs ~5h " +
      "→ schedule 'check the run results and decide the next step' in 5.5h). " +
      "Timers live only in this pi process: exit/restart/reload/session switch loses them. " +
      "Actions: schedule (default, needs delay+prompt), list, cancel (needs id or all=true).",
    promptSnippet: "Schedule a delayed follow-up prompt to this session (self wake-up for long waits)",
    promptGuidelines: [
      "Use later when you must wait a long, roughly known time (e.g. background experiments) and should resume this session automatically with a pre-written next-step prompt instead of blocking or polling.",
      "When calling later with action=schedule, write the prompt as a complete instruction to your future self: what to check, what to decide, what to run next.",
    ],
    parameters: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["schedule", "list", "cancel"], description: "Default: schedule" },
        delay: { type: "string", description: "Wait time, e.g. \"30s\", \"45m\", \"5.5h\", \"1d\" (schedule only)" },
        prompt: { type: "string", description: "The full message to send to this session when the timer fires (schedule only)" },
        id: { type: "number", description: "Schedule id to cancel" },
        all: { type: "boolean", description: "Cancel all pending schedules" },
      },
    },
    async execute(_toolCallId: string, params: any) {
      const action = params?.action ?? "schedule";

      if (action === "list") {
        const lines = listLines();
        return { content: [{ type: "text", text: lines.length ? lines.join("\n") : "没有待发送的排程" }] };
      }

      if (action === "cancel") {
        const targets = cancel(params?.all ? "all" : [Number(params?.id)]);
        if (targets.length === 0) throw new Error("没有匹配的排程(用 action=list 查看现有 id)");
        return { content: [{ type: "text", text: `已取消 ${targets.map((id) => `#${id}`).join(" ")}` }] };
      }

      const ms = typeof params?.delay === "string" ? parseDelay(params.delay) : undefined;
      const text = typeof params?.prompt === "string" ? params.prompt.trim() : "";
      if (!ms || !text) throw new Error("action=schedule 需要 delay(如 \"5.5h\")和非空 prompt");
      const { id, at } = schedule(text, ms);
      return {
        content: [{ type: "text", text: `#${id} 已排程:${hhmm(at)}(${dur(ms)}后)发送 —— ${text}` }],
        details: { id, at },
      };
    },
  });

  // 会话被替换后旧 runtime 会失效,定时器必须先清掉。
  pi.on("session_shutdown", () => {
    for (const p of pending.values()) clearTimeout(p.timer);
    pending.clear();
  });
}
