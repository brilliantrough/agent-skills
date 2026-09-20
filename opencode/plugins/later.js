// later — agent 可调用的定时自唤醒工具(opencode server 插件,与 TUI 输入框版互补)
// agent 调 later 工具排程:实验挂后台,估时+冗余,到点把 prompt 作为真实用户消息注入同一会话
// (prompt_async:空闲立即开跑,忙时排队等本轮结束),无需人在场;超时就从实际进度重估再排。
// 计时器只活在当前 opencode server 进程内:退出/重启会丢未触发的排程(挂机请放 tmux)。
// 部署:agent-skills 仓 opencode-setup.sh 从 dot_file 下载到 ~/.config/opencode/plugins/。
import { tool } from "@opencode-ai/plugin";

const UNIT = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
const hhmm = (t) => new Date(t).toTimeString().slice(0, 5);
const dur = (ms) => {
  if (ms < 60000) return `${Math.max(0, Math.round(ms / 1000))}s`;
  const h = Math.floor(ms / 3600000);
  const m = Math.round((ms % 3600000) / 60000);
  return h ? `${h}h${m}m` : `${m}m`;
};
const parseDelay = (s) => {
  const m = String(s ?? "").trim().match(/^(\d+(?:\.\d+)?)([smhd])$/);
  return m ? Number(m[1]) * UNIT[m[2]] : undefined;
};

export default async function LaterPlugin({ client }) {
  const jobs = new Map();
  let nextId = 1;

  function schedule(sessionID, ms, text) {
    const id = nextId++;
    const at = Date.now() + ms;
    const timer = setTimeout(() => {
      jobs.delete(id);
      client.session
        .promptAsync({ path: { id: sessionID }, body: { parts: [{ type: "text", text }] } })
        .then((res) => {
          if (res?.error) throw new Error(JSON.stringify(res.error));
        })
        .catch(() => {}); // 触发时会话可能已删或服务将退,静默丢弃(server 侧没有通知面)
    }, ms);
    jobs.set(id, { id, at, sessionID, timer });
    return { id, at };
  }

  function cancel(ids) {
    const done = ids.filter((i) => {
      const j = jobs.get(i);
      if (!j) return false;
      clearTimeout(j.timer);
      jobs.delete(i);
      return true;
    });
    return done;
  }

  const list = () =>
    [...jobs.values()]
      .sort((a, b) => a.at - b.at)
      .map((j) => `#${j.id} ${hhmm(j.at)}(${dur(j.at - Date.now())}后)`);

  return {
    tool: {
      later: tool({
        description:
          "Schedule a prompt to be sent back to THIS session after a delay, as a real user message " +
          "(fires immediately if idle, queued until the current turn finishes if busy). " +
          "Use it to wait on long-running background work without a human present: estimate the duration, " +
          "add ~10% margin, and write the prompt as a complete next-step instruction to yourself " +
          "(e.g. an experiment needs ~5h → schedule 'check the run results and decide the next step' in 5.5h). " +
          "If the work overruns, re-estimate the remainder from observed progress and schedule again. " +
          "Timers live only in this opencode process: exit/restart loses them. " +
          "Actions: schedule (default, needs delay+prompt), list, cancel (needs id or all=true).",
        args: {
          action: tool.schema.enum(["schedule", "list", "cancel"]).optional(),
          delay: tool.schema.string().optional().describe('Wait time, e.g. "30s", "45m", "5.5h", "1d" (schedule only)'),
          prompt: tool.schema.string().optional().describe("The full message to send to this session when the timer fires (schedule only)"),
          id: tool.schema.number().optional().describe("Schedule id to cancel"),
          all: tool.schema.boolean().optional().describe("Cancel all pending schedules"),
        },
        async execute(args, ctx) {
          const action = args.action ?? "schedule";

          if (action === "list") {
            const lines = list();
            return lines.length ? lines.join("\n") : "没有待发送的排程";
          }

          if (action === "cancel") {
            const done = cancel(args.all ? [...jobs.keys()] : [Number(args.id)]);
            if (done.length === 0) throw new Error("没有匹配的排程(用 action=list 查看现有 id)");
            return `已取消 ${done.map((i) => `#${i}`).join(" ")}`;
          }

          const ms = parseDelay(args.delay);
          const text = (args.prompt ?? "").trim();
          if (!ms || !text) throw new Error('action=schedule 需要 delay(如 "5.5h")和非空 prompt');
          const { id, at } = schedule(ctx.sessionID, ms, text);
          return `#${id} 已排程:${hhmm(at)}(${dur(ms)}后)发送 —— ${text}`;
        },
      }),
    },
  };
}
