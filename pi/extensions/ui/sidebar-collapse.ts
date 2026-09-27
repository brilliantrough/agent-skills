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
 * edits, no new Pi API. Panel blocks are recognised from the flat section
 * headers (`TITLE · counters ──────`, sidebar.ts 的 panelRows 输出格式)，
 * 块体到空行/下一个标题行为止，所以状态按标题首词做 key，计数器变化
 * 不影响折叠状态。
 *
 * Collapsed keys live in `agent-skills-ui.json` (`collapsedPanels`).
 * ponytail: one flat list of panel keys, no per-project overrides.
 */
const CONFIG_FILE = "agent-skills-ui.json";
const ANSI = /\u001b\[[0-9;]*m/g;
// 扁平分节标题行：大写标题开头，后接空格 + 至少两个 ─ 填充（sidebar.ts panelRows 的格式）。
// 前缀容忍 renderDock 的两格 edge 和 resize 时的 `│ `，与 DISCLOSURE 的容忍方式一致。
const HEADER = /^\s*(?:│\s*)?([A-Z][A-Z0-9 ·/]*?) +─{2,}\s*$/;

export interface PanelBlock {
	key: string;
	title: string;
	headerRow: number;
	endRow: number;
}

export interface MouseEventLike {
	type: string;
	y: number;
	button?: "left" | "middle" | "right" | "none";
	clickCount?: number;
}

/** pi-tui 的 `TuiMouseEventResult`：必须给 handled/capture/focus 之一，否则派发会被丢弃。 */
export interface MouseResult {
	handled?: boolean;
	capture?: boolean;
	focus?: boolean;
	render?: boolean;
}

/** TOOLS 面板的展开/收起行,如 `│ 39 / 45 active   ▸ │`(面板行带边框)。 */
const DISCLOSURE = /^[│|\s]*\d+\s*\/\s*\d+\s*active\s*[▸▾][│|\s]*$/;

export interface CollapsibleComponent {
	render(width: number): string[];
	invalidate(): void;
	handleMouse?(event: MouseEventLike): MouseResult | undefined;
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
		// 扁平分节没有底框：空行即块尾（空行本身留给版面间距，不算进块体）。
		if (text.trim() === "") {
			open = undefined;
			continue;
		}
		open.endRow = row;
	}
	return blocks;
}

/** Rewrite the header row so the collapsed state is visible (keeps its colors). */
function collapsedHeader(line: string, title: string): string {
	const index = line.indexOf(title);
	const prefix = index > 0 ? line.slice(0, index) : "";
	const tail = line.slice(index + title.length);
	return `${prefix}${title} \u001b[2m▸\u001b[0m${tail}`;
}

export function shapeLines(
	lines: readonly string[],
	collapsed: ReadonlySet<string>,
): { lines: string[]; panelRows: Map<number, string>; disclosureRows: Set<number> } {
	const blocks = panelBlocks(lines);
	const skip = new Set<number>();
	const output: string[] = [];
	const panelRows = new Map<number, string>();
	const disclosureRows = new Set<number>();
	for (const [row, line] of lines.entries()) {
		if (skip.has(row)) continue;
		const block = blocks.find((candidate) => candidate.headerRow === row);
		if (block) {
			panelRows.set(output.length, block.key);
			if (collapsed.has(block.key)) {
				output.push(collapsedHeader(line, block.title));
				// 只折掉块体；块后的空行留下做版面间距。
				for (let drop = row + 1; drop <= block.endRow; drop += 1) skip.add(drop);
				continue;
			}
		} else if (DISCLOSURE.test(line.replace(ANSI, ""))) {
			disclosureRows.add(output.length);
		}
		output.push(line);
	}
	return { lines: output, panelRows, disclosureRows };
}

export interface CollapsibleOptions {
	/** 点 TOOLS 的 `n / m active ▸` 行时调用（上游 /ui sidebar tools 的同一动作）。 */
	onToggleToolNames?(): void;
	/** 返回 selectedBg 的 ANSI 起始序列；提供了才启用悬浮高亮。 */
	getHoverBgOpen?(): string | undefined;
}

/** 行内可能带 \x1b[0m 重置，重置后重新铺上背景色，保证整行都在高亮里。 */
function hoverHighlight(line: string, bgOpen: string): string {
	return bgOpen + line.replaceAll("\u001b[0m", `\u001b[0m${bgOpen}`) + "\u001b[0m";
}

function configuredSidebarHover(): boolean {
	try {
		const config = JSON.parse(readFileSync(configPath(), "utf8"));
		return typeof config?.sidebarHover === "boolean" ? config.sidebarHover : true;
	} catch {
		return true;
	}
}

/**
 * 面板头/TOOLS 行的悬浮高亮：Pi fullscreen（非 tmux）会把无按键的 move 事件按
 * 组件本地坐标分发下来，行号与点击折叠用的是同一套输出坐标，命中逻辑直接复用。
 * 已知取舍：指针直接离开侧栏时没有 leave 事件，高亮会停留到下一次侧栏内移动。
 */
export function withCollapsiblePanels(
	inner: CollapsibleComponent,
	options: CollapsibleOptions = {},
): CollapsibleComponent {
	let panelRows = new Map<number, string>();
	let disclosureRows = new Set<number>();
	let hoverRow: number | undefined;
	return {
		render(width: number): string[] {
			const shaped = shapeLines(inner.render(width), readCollapsedPanels());
			panelRows = shaped.panelRows;
			disclosureRows = shaped.disclosureRows;
			const bgOpen = configuredSidebarHover() ? options.getHoverBgOpen?.() : undefined;
			if (bgOpen && hoverRow !== undefined && (panelRows.has(hoverRow) || disclosureRows.has(hoverRow))) {
				const lines = shaped.lines.slice();
				lines[hoverRow] = hoverHighlight(lines[hoverRow], bgOpen);
				return lines;
			}
			return shaped.lines;
		},
		invalidate(): void {
			inner.invalidate();
		},
		handleMouse(event: MouseEventLike): MouseResult | undefined {
			// move 事件的 button 恒为 "none"，按钮守卫只能挡 press/click，放在 move 分支前面会把
			// 所有悬浮事件全部挡掉。
			if (event.type === "move") {
				if (!configuredSidebarHover() || !options.getHoverBgOpen) return undefined;
				const next = panelRows.has(event.y) || disclosureRows.has(event.y) ? event.y : undefined;
				if (next === hoverRow) return { handled: true };
				hoverRow = next;
				return { handled: true, render: true };
			}
			if (event.button && event.button !== "left") return undefined;
			if (event.type === "press" && (panelRows.has(event.y) || disclosureRows.has(event.y))) {
				// 吃掉 press：不要再开始文本选区；同时让 pi-tui 记住按下的目标，
				// 这样松手时的 click 会回到这里。
				return { handled: true };
			}
			if (event.type !== "click") return undefined;
			if (disclosureRows.has(event.y)) {
				options.onToggleToolNames?.();
				return { handled: true, render: true };
			}
			const key = panelRows.get(event.y);
			if (!key) return undefined;
			const collapsed = readCollapsedPanels();
			if (collapsed.has(key)) collapsed.delete(key);
			else collapsed.add(key);
			writeCollapsedPanels(collapsed);
			return { handled: true, render: true };
		},
	};
}
