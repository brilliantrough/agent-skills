// later — 延迟发送预设 prompt(挂机等实验结果):/later 5h 查看当前实验结果
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

export default function (pi: ExtensionAPI) {
  let nextId = 1;
  const pending = new Map<number, { id: number; at: number; timer: NodeJS.Timeout }>();

  function status(ctx: any) {
    if (pending.size === 0) return ctx.ui?.setStatus?.("later", undefined);
    const soonest = Math.min(...[...pending.values()].map((p) => p.at));
    ctx.ui?.setStatus?.("later", `⏰${pending.size} ${hhmm(soonest)}`);
  }

  pi.registerCommand("later", {
    description: "延迟发送 prompt:/later <时长> <prompt> | /later list | /later cancel <id|all>",
    handler: async (args: string, ctx: any) => {
      const arg = args.trim();

      if (arg === "" || arg === "list") {
        if (pending.size === 0) return ctx.ui.notify("没有待发送的 prompt", "info");
        const lines = [...pending.values()]
          .sort((a, b) => a.at - b.at)
          .map((p) => `#${p.id} ${hhmm(p.at)}(${dur(p.at - Date.now())}后)`);
        return ctx.ui.notify(lines.join("\n"), "info");
      }

      const cancel = arg.match(/^cancel\s+(\d+|all)$/);
      if (cancel) {
        const targets =
          cancel[1] === "all"
            ? [...pending.keys()]
            : [Number(cancel[1])].filter((id) => pending.has(id));
        if (targets.length === 0) return ctx.ui.notify("没有匹配的排程", "warning");
        for (const id of targets) {
          clearTimeout(pending.get(id)!.timer);
          pending.delete(id);
        }
        status(ctx);
        return ctx.ui.notify(`已取消 ${targets.map((id) => `#${id}`).join(" ")}`, "info");
      }

      const parsed = arg.match(/^(\d+)([smhd])\s+([\s\S]+)$/);
      if (!parsed) {
        return ctx.ui.notify("用法:/later 5h 查看当前实验结果 | /later list | /later cancel <id|all>", "warning");
      }

      const [, n, unit, text] = parsed;
      const ms = Number(n) * UNIT[unit];
      const id = nextId++;
      const at = Date.now() + ms;
      const timer = setTimeout(() => {
        pending.delete(id);
        // 挂机时 agent 可能正忙:followUp 在空闲时立即发送,忙时排队等本轮结束。
        pi.sendUserMessage(text, { deliverAs: "followUp" });
        status(ctx);
      }, ms);
      pending.set(id, { id, at, timer });
      status(ctx);
      ctx.ui.notify(`#${id} 将在 ${hhmm(at)}(${n}${unit}后)发送:${text}`, "info");
    },
  });

  // 会话被替换后旧 runtime 会失效,定时器必须先清掉。
  pi.on("session_shutdown", () => {
    for (const p of pending.values()) clearTimeout(p.timer);
    pending.clear();
  });
}
