import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { WrappedPolishedEditor } from "./editor/ui.js";
import { loadConfig } from "./editor/config.js";
import { installUserMessageStyle } from "./editor/user-message.js";
import { installWheelScrollLines } from "./wheel.js";

/** One editor owner: native Pi behavior, our LF fix, then the adopted frame. */
export function installComposer(pi: ExtensionAPI) {
  let cleanup: (() => void) | undefined;
  pi.on("session_start", (_event, ctx) => {
    cleanup?.();
    if (ctx.mode !== "tui") return;
    const config = loadConfig();
    ctx.ui.setEditorComponent((tui, theme, keys) => {
      installWheelScrollLines(tui);
      const base = new CustomEditor(tui, theme, keys);
      const input = base.handleInput.bind(base);
      let pasting = false;
      base.handleInput = data => {
        if (data.includes("\x1b[200~")) pasting = true;
        if (!pasting && data === "\n" && keys.matches("\x1b[106;5u", "tui.input.submit")) data = "\x1b[106;5u";
        if (data.includes("\x1b[201~")) pasting = false;
        input(data);
      };
      return new WrappedPolishedEditor(base, ctx.ui.theme, () => config, () => ({
        modelLabel: ctx.model?.name ?? ctx.model?.id ?? "no-model",
        modelId: ctx.model?.id,
        providerLabel: ctx.model?.provider ?? "",
      }), () => pi.getThinkingLevel());
    });
    if (config.components.userMessages.enabled) cleanup = installUserMessageStyle(() => ctx.ui.theme, () => config);
  });
  pi.on("session_shutdown", (_event, ctx) => {
    cleanup?.(); cleanup = undefined;
    if (ctx.mode === "tui") ctx.ui.setEditorComponent(undefined);
  });
}
