import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Current response only. ~TPS estimates UTF-8 bytes / 5, not tokenizer counts. */
export default function (pi: ExtensionAPI) {
  const key = "agent-skills:tps";
  let publish: ((text: string | undefined) => void) | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;
  let first: number | undefined;
  let last = 0;
  let bytes = 0;
  let shown: string | undefined;

  const show = (text: string | undefined) => {
    if (shown === text) return;
    shown = text;
    publish?.(text);
  };
  const stop = () => {
    if (timer) clearInterval(timer);
    timer = undefined;
  };
  const reset = () => {
    stop();
    first = undefined;
    last = 0;
    bytes = 0;
  };

  pi.on("session_start", (_event, ctx) => {
    reset();
    shown = undefined;
    publish = ctx.mode === "tui" ? (text) => ctx.ui.setStatus(key, text) : undefined;
  });
  pi.on("message_start", (event) => {
    if (event.message.role !== "assistant") return;
    reset();
    show(undefined);
  });
  pi.on("message_update", (event) => {
    if (!publish) return;
    const delta = event.assistantMessageEvent;
    if (delta.type !== "text_delta" && delta.type !== "thinking_delta" && delta.type !== "toolcall_delta") return;
    if (!delta.delta) return;
    last = performance.now();
    first ??= last;
    // Sum bytes before division: no per-chunk rounding/minimum-token inflation.
    // ponytail: bytes/5 is language-dependent; use tokenizer only if exact live TPS is needed.
    bytes += Buffer.byteLength(delta.delta, "utf8");
    timer ??= setInterval(() => {
      const seconds = (performance.now() - first!) / 1000;
      show(`~TPS ${(bytes / 5 / seconds).toFixed(1)}`);
    }, 1000);
  });
  pi.on("message_end", (event) => {
    if (event.message.role !== "assistant") return;
    stop();
    const seconds = first === undefined ? 0 : (last - first) / 1000;
    const output = event.message.usage.output;
    // Tiny/buffered bursts cannot provide a meaningful generation-speed sample.
    if (seconds < 0.25 || output <= 0 || event.message.stopReason === "error" || event.message.stopReason === "aborted") {
      show("TPS —");
    } else {
      show(`TPS ${(output / seconds).toFixed(1)} (last)`);
    }
    first = undefined;
  });
  pi.on("agent_settled", () => { stop(); });
  pi.on("session_shutdown", () => {
    reset();
    show(undefined);
    publish = undefined;
  });
}
