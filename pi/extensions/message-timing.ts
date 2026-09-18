import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

interface Timing {
  finishedAt: string;
  durationMs: number;
}

// 只在整次运行稳定结束后写一行；不轮询、不进入模型上下文。
export default function (pi: ExtensionAPI) {
  let startedAt: number | undefined;

  pi.registerEntryRenderer<Timing>("agent-skills-timing", (entry, _options, theme) => ({
    render: (width) => {
      if (!entry.data) return [];
      const { finishedAt, durationMs } = entry.data;
      return [theme.fg("dim", truncateToWidth(`${finishedAt} ${(durationMs / 1000).toFixed(3)}s`, width))];
    },
    invalidate() {},
  }));

  pi.on("session_start", () => { startedAt = undefined; });
  pi.on("agent_start", () => { startedAt ??= performance.now(); });
  pi.on("agent_settled", (_event, ctx) => {
    const start = startedAt;
    startedAt = undefined;
    if (ctx.mode !== "tui" || start === undefined) return;
    pi.appendEntry<Timing>("agent-skills-timing", {
      finishedAt: new Date().toLocaleString("sv-SE"),
      durationMs: performance.now() - start,
    });
  });
}
