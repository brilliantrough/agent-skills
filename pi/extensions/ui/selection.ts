import { readFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

/**
 * Pi keeps the fullscreen text-selection highlight after a copy-on-select release,
 * so the box lingers over the transcript (and over the composer) until the next click.
 * `clearTextSelection` is private in the type but a plain method at runtime; the
 * clipboard text is read synchronously before the base call returns, so clearing
 * right after the release cannot lose the copy.
 *
 * Toggle: `clearSelectionOnRelease` in `agent-skills-ui.json` (default true).
 * ponytail: read from the user config only; a project-level override would need
 * the trust-aware loader, and there is no demand for per-project mouse behavior.
 */
export const DEFAULT_CLEAR_SELECTION_ON_RELEASE = true;

function configuredClearOnRelease(): boolean {
	try {
		const config = JSON.parse(readFileSync(join(getAgentDir(), "agent-skills-ui.json"), "utf8"));
		return typeof config?.clearSelectionOnRelease === "boolean"
			? config.clearSelectionOnRelease
			: DEFAULT_CLEAR_SELECTION_ON_RELEASE;
	} catch {
		return DEFAULT_CLEAR_SELECTION_ON_RELEASE;
	}
}
const INSTALLED = Symbol("agent-skills.clear-selection-on-release");
const SGR_RELEASE = /^\u001b\[<\d+;\d+;\d+m$/;

interface SelectionRenderer {
	[INSTALLED]?: boolean;
	handleViewportInput?: (data: string) => unknown;
	clearTextSelection?: () => void;
	hasActiveSelection?: () => boolean;
	getCopyOnSelect?: () => boolean;
	requestRender?: () => void;
}

export function installClearSelectionOnRelease(
	tui: unknown,
	enabled: boolean = configuredClearOnRelease(),
): void {
	if (!enabled) return;
	const target = tui as SelectionRenderer | undefined;
	if (typeof target?.handleViewportInput !== "function" || typeof target.clearTextSelection !== "function") return;
	if (target[INSTALLED]) return;
	const base = target.handleViewportInput;
	target[INSTALLED] = true;
	target.handleViewportInput = function (data: string) {
		const result = base.call(target, data);
		// copyOnSelect=false means nothing was copied; keep the user's selection intact.
		if (SGR_RELEASE.test(data) && target.getCopyOnSelect?.() !== false && target.hasActiveSelection?.() === true) {
			queueMicrotask(() => {
				target.clearTextSelection?.();
				target.requestRender?.();
			});
		}
		return result;
	};
}
