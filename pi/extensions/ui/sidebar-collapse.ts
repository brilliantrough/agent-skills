import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

/**
 * Click a sidebar panel's title row to collapse/expand it.
 *
 * Pi's fullscreen renderer dispatches mouse events to the component under the
 * cursor (`dispatchMouseToLayout` -> `dispatchMouseEvent` with component-local
 * x/y) and re-renders when a handler returns `{ render: true }`. The sidebar is
 * a plain layout component, so wrapping it here is enough: no upstream layout
 * edits, no new Pi API. Panel blocks are recognised from the rendered box
 * borders (`╭─ ✦ TITLE ──╮` … `╰──╯`), so the state is keyed by the title's
 * first word and survives title counters changing ("TASKS · 3/3").
 *
 * Collapsed keys live in `agent-skills-ui.json` (`collapsedPanels`).
 * ponytail: one flat list of panel keys, no per-project overrides.
 */
const CONFIG_FILE = "agent-skills-ui.json";
const ANSI = /\u001b\[[0-9;]*m/g;
const HEADER = /^╭─\s*[✦✧]\s*(.+?)\s*─*╮$/;
const FOOTER = /^╰─+╯$/;

export interface PanelBlock {
	key: string;
	title: string;
	headerRow: number;
	endRow: number;
}

export interface MouseEventLike {
	type: string;
	y: number;
	clickCount?: number;
}

export interface CollapsibleComponent {
	render(width: number): string[];
	invalidate?(): void;
	handleMouse?(event: MouseEventLike): { consume?: boolean; render?: boolean } | undefined;
}

function configPath(): string {
	return join(getAgentDir(), CONFIG_FILE);
}

export function readCollapsedPanels(): Set<string> {
	try {
		const config = JSON.parse(readFileSync(configPath(), "utf8"));
		const list = config?.collapsedPanels;
		return new Set(Array.isArray(list) ? list.filter((key: unknown): key is string => typeof key === "string") : []);
	} catch {
		return new Set();
	}
}

export function writeCollapsedPanels(keys: Iterable<string>): void {
	const path = configPath();
	let config: Record<string, unknown> = {};
	try {
		config = JSON.parse(readFileSync(path, "utf8")) ?? {};
	} catch {
		// Missing or broken config: rewrite it with just this key.
	}
	const sorted = [...new Set(keys)].sort();
	if (Array.isArray(config.collapsedPanels) && config.collapsedPanels.join("\u0000") === sorted.join("\u0000")) return;
	writeFileSync(path, `${JSON.stringify({ ...config, collapsedPanels: sorted }, null, 2)}\n`, "utf8");
}

/** Panel blocks in render order, keyed by the title's first word. */
export function panelBlocks(lines: readonly string[]): PanelBlock[] {
	const blocks: PanelBlock[] = [];
	let open: PanelBlock | undefined;
	for (const [row, line] of lines.entries()) {
		const text = line.replace(ANSI, "");
		const header = HEADER.exec(text);
		if (header) {
			const title = header[1];
			const key = (title.split(/[\s·]+/)[0] || title).toUpperCase();
			open = { key, title, headerRow: row, endRow: row };
			blocks.push(open);
			continue;
		}
		if (!open) continue;
		open.endRow = row;
		if (FOOTER.test(text)) open = undefined;
	}
	return blocks;
}

/** Rewrite the header row so the collapsed state is visible (keeps its colors). */
function collapsedHeader(line: string, title: string): string {
	const index = line.indexOf(title);
	const prefix = index > 0 ? line.slice(0, index) : "";
	const tail = line.slice(index + title.length);
	// Keep any trailing reset so the terminal does not leak the header color.
	const reset = tail.includes("\u001b[0m") ? "\u001b[0m" : "";
	return `${prefix}${title} \u001b[2m▸${reset}`;
}

export function shapeLines(
	lines: readonly string[],
	collapsed: ReadonlySet<string>,
): { lines: string[]; panelRows: Map<number, string> } {
	const blocks = panelBlocks(lines);
	const skip = new Set<number>();
	const output: string[] = [];
	const panelRows = new Map<number, string>();
	for (const [row, line] of lines.entries()) {
		if (skip.has(row)) continue;
		const block = blocks.find((candidate) => candidate.headerRow === row);
		if (block) {
			panelRows.set(output.length, block.key);
			if (collapsed.has(block.key)) {
				output.push(collapsedHeader(line, block.title));
				// Drop the body, the footer and the blank spacer after it.
				const rest = lines[block.endRow + 1]?.replace(ANSI, "");
				const stop = rest === "" ? block.endRow + 2 : block.endRow + 1;
				for (let drop = row + 1; drop < stop; drop += 1) skip.add(drop);
				continue;
			}
		}
		output.push(line);
	}
	return { lines: output, panelRows };
}

export function withCollapsiblePanels(inner: CollapsibleComponent): CollapsibleComponent {
	let panelRows = new Map<number, string>();
	return {
		render(width: number): string[] {
			const shaped = shapeLines(inner.render(width), readCollapsedPanels());
			panelRows = shaped.panelRows;
			return shaped.lines;
		},
		invalidate(): void {
			inner.invalidate?.();
		},
		handleMouse(event: MouseEventLike): { consume?: boolean; render?: boolean } | undefined {
			if (event.type !== "press" && event.type !== "click") return undefined;
			const key = panelRows.get(event.y);
			if (!key) return undefined;
			// Swallow the press so it cannot start a text selection over the panel.
			if (event.type === "press") return { consume: true };
			const collapsed = readCollapsedPanels();
			if (collapsed.has(key)) collapsed.delete(key);
			else collapsed.add(key);
			writeCollapsedPanels(collapsed);
			return { consume: true, render: true };
		},
	};
}
