import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { WrappedPolishedEditor } from "./editor/ui.js";
import { loadConfig } from "./editor/config.js";
import { installCopyCleanup } from "./editor/copy-clean.js";
import { installUserMessageStyle } from "./editor/user-message.js";
import { installWheelScrollLines } from "./wheel.js";
import { installClearSelectionOnRelease } from "./selection.js";

const CTRL_J = "\x1b[106;5u";
const PASTE_START = "\x1b[200~";
const PASTE_END = "\x1b[201~";

/**
 * `ask_user_question` builds its own headless `Editor` and routes keys itself, so the LF
 * rewrite in the composer below never reaches a typed custom answer: pi-tui's keys.js
 * matches raw LF against `tui.input.newLine` (as `enter`, or as `shift+enter` under the
 * Kitty protocol), the questionnaire's key router treats it as a newline and forwards it
 * to that editor's raw-LF branch — so no key can ever confirm the answer. The TUI's
 * terminal-input listeners run before any focused component (and can rewrite the data),
 * so normalize LF there while a questionnaire awaits input.
 */
function installQuestionnaireSubmitKey(pi: ExtensionAPI, ctx: ExtensionContext, submitIsCtrlJ: () => boolean) {
  let waiting = false;
  const offBlocked = pi.events.on("rpiv:ask-user:blocked", (payload) => {
    waiting = (payload as { active?: boolean } | undefined)?.active === true;
  });
  let pasting = false;
  const offInput = ctx.ui.onTerminalInput(data => {
    if (data.includes(PASTE_START)) pasting = true;
    const rewrite = !pasting && waiting && data === "\n" && submitIsCtrlJ();
    if (data.includes(PASTE_END)) pasting = false;
    return rewrite ? { data: CTRL_J } : undefined;
  });
  return () => {
    offBlocked();
    offInput();
  };
}

/** One editor owner: native Pi behavior, our LF fix, then the adopted frame. */
export function installComposer(pi: ExtensionAPI) {
  let cleanup: (() => void) | undefined;
  let cleanupSubmitKey: (() => void) | undefined;
  pi.on("session_start", (_event, ctx) => {
    cleanup?.();
    cleanupSubmitKey?.();
    cleanupSubmitKey = undefined;
    if (ctx.mode !== "tui") return;
    const config = loadConfig();
    let submitIsCtrlJ = false;
    ctx.ui.setEditorComponent((tui, theme, keys) => {
      submitIsCtrlJ = keys.matches(CTRL_J, "tui.input.submit");
      installWheelScrollLines(tui);
      installClearSelectionOnRelease(tui);
      installCopyCleanup(tui);
      const base = new CustomEditor(tui, theme, keys);
      const input = base.handleInput.bind(base);
      let pasting = false;
      base.handleInput = data => {
        if (data.includes(PASTE_START)) pasting = true;
        if (!pasting && data === "\n" && submitIsCtrlJ) data = CTRL_J;
        if (data.includes(PASTE_END)) pasting = false;
        input(data);
      };
      return new WrappedPolishedEditor(base, ctx.ui.theme, () => config, () => ({
        modelLabel: ctx.model?.name ?? ctx.model?.id ?? "no-model",
        modelId: ctx.model?.id,
        providerLabel: ctx.model?.provider ?? "",
      }), () => pi.getThinkingLevel());
    });
    cleanupSubmitKey = installQuestionnaireSubmitKey(pi, ctx, () => submitIsCtrlJ);
    if (config.components.userMessages.enabled) cleanup = installUserMessageStyle(() => ctx.ui.theme, () => config);
  });
  pi.on("session_shutdown", (_event, ctx) => {
    cleanup?.(); cleanup = undefined;
    cleanupSubmitKey?.(); cleanupSubmitKey = undefined;
    if (ctx.mode === "tui") ctx.ui.setEditorComponent(undefined);
  });
}
