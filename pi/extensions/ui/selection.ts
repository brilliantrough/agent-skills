/**
 * Pi keeps the fullscreen text-selection highlight after a copy-on-select release,
 * so the box lingers over the transcript (and over the composer) until the next click.
 * `clearTextSelection` is private in the type but a plain method at runtime; the
 * clipboard text is read synchronously before the base call returns, so clearing
 * right after the release cannot lose the copy.
 */
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

export function installClearSelectionOnRelease(tui: unknown): void {
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
