/**
 * Pi builds its fullscreen renderer without pi-tui's `wheelScrollLines` option,
 * so every wheel notch scrolls exactly one line (upstream asks are open:
 * earendil-works/pi#7765, #8370, #8446, #8471, #8741; 0.84.0 used to be 3).
 * The field is a plain instance property, so setting it needs no dist patch.
 */
export const WHEEL_SCROLL_LINES = 3;

export function installWheelScrollLines(tui: unknown, lines: number = WHEEL_SCROLL_LINES): void {
	const target = tui as { wheelScrollLines?: number } | undefined;
	if (typeof target?.wheelScrollLines !== "number") return; // regular mode: terminal owns scrolling
	target.wheelScrollLines = Math.max(1, Math.floor(lines));
}

