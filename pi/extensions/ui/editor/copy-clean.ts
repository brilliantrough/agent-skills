import { readFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import { stripTerminalSequences } from "@earendil-works/pi-tui";

/**
 * 鼠标划词复制拿到的是屏幕文本，不是组件文本：pi-tui 的 `TuiAltScreen.getActiveSelectionText()`
 * 按行取 `previousScreen[row]`、去 ANSI、逐行 trimEnd 后 `join("\n")`。于是输入框和用户消息框
 * 左侧的装饰（`│ `）会跟着正文进剪贴板，输入框里的软折行也被写成硬换行。
 *
 * 这里在 `copySelection`（TuiAltScreen 的实例字段，运行时是普通属性）外面包一层：用我们自己
 * 渲染时登记的行对（`screen` ↔ `clean`）把复制文本还原成正文；输入框正文还带上逻辑行号与
 * "拼回下一行时要补的空白"，同一逻辑行的相邻行因此还原成用户真正敲进去的那一行。
 * 对不上的行原样保留（失败即放行），所以登记表坏了最坏退化成现在的行为。
 *
 * Toggle: `cleanCopiedText` in `agent-skills-ui.json` (default true).
 */
export const DEFAULT_CLEAN_COPIED_TEXT = true;

/** 登记太多会拖慢每次复制；最近的几十个渲染面足够覆盖可见区域。 */
const MAX_SURFACES = 80;

export type CopyRow = {
	/** 屏幕整行（去 ANSI、去行尾空白），用来和剪贴板里的行对齐。 */
	screen: string;
	/** 去掉装饰后的正文。 */
	clean: string;
	/** 逻辑行号；只有能可靠对齐的输入框正文行才有。 */
	logical?: number;
	/** 与"同一逻辑行的下一行"拼接时插入的文本（行尾被裁掉的空白 + 折行间隙）。 */
	join?: string;
};

export type VisualLine = {
	logicalLine: number;
	startCol: number;
	length: number;
};

type Surface = { key: string; chrome: string; rows: CopyRow[] };

const surfaces: Surface[] = [];
const INSTALLED = Symbol("agent-skills.clean-copied-text");

interface CopyRenderer {
	copySelection?: (text: string) => Promise<boolean | string>;
	[INSTALLED]?: boolean;
}

export function plainRow(line: string): string {
	return stripTerminalSequences(line).trimEnd();
}

export function registerCopySurface(key: string, chrome: string, rows: CopyRow[]): void {
	if (rows.length === 0) return;
	const existing = surfaces.findIndex((surface) => surface.key === key);
	if (existing >= 0) surfaces.splice(existing, 1);
	surfaces.unshift({ key, chrome, rows });
	if (surfaces.length > MAX_SURFACES) surfaces.length = MAX_SURFACES;
}

export function clearCopySurfaces(): void {
	surfaces.length = 0;
}

/**
 * 从输入框的渲染结果与编辑器自身的视觉行表构造登记行。
 *
 * `bodyRows` 是 base editor 渲染出的正文行（不含左侧装饰），`visualMap` 是
 * `Editor.buildVisualLineMap(width)` 的值。两者必须能互相印证：对不上就返回 undefined，
 * 让调用方放弃登记，而不是登记一份错的映射。
 */
export function composerCopyRows(input: {
	bodyRows: string[];
	chrome: string;
	logicalLines: string[];
	visualMap: VisualLine[] | undefined;
}): CopyRow[] | undefined {
	const { bodyRows, chrome, logicalLines, visualMap } = input;
	if (bodyRows.length === 0) return undefined;
	const bodies = bodyRows.map(plainRow);
	if (!visualMap || visualMap.length < bodyRows.length) {
		return bodies.map((clean) => ({ screen: `${chrome}${clean}`.trimEnd(), clean }));
	}
	const offset = findBodyWindow(visualMap, bodies, logicalLines);
	if (offset === undefined) return undefined;

	const visible = visualMap.slice(offset, offset + bodies.length);
	return bodies.map((clean, index) => {
		const line = logicalLines[visible[index].logicalLine] ?? "";
		const next = visible[index + 1];
		const sameLine = next !== undefined && next.logicalLine === visible[index].logicalLine;
		const chunk = line.slice(
			visible[index].startCol,
			visible[index].startCol + visible[index].length,
		);
		return {
			screen: `${chrome}${clean}`.trimEnd(),
			clean,
			logical: visible[index].logicalLine,
			join: sameLine
				? line.slice(visible[index].startCol + chunk.trimEnd().length, next.startCol)
				: undefined,
		};
	});
}

/**
 * 把一整帧输入框渲染结果登记成复制渲染面：先在帧里找到正文窗口，再用同一个视觉行表
 * 给正文行补上逻辑行号，最后把窗口两侧紧邻的装饰行（空行、元信息行）也纳进来。
 * 补全菜单等非装饰行不会进表，所以选中它们时不会被动进对齐。
 */
export function composerSurfaceRows(input: {
	frameRows: string[];
	bodyRows: string[];
	chrome: string;
	logicalLines: string[];
	visualMap: VisualLine[] | undefined;
}): CopyRow[] | undefined {
	const { frameRows, bodyRows, chrome } = input;
	if (!chrome || bodyRows.length === 0) return undefined;
	const plains = frameRows.map(plainRow);
	const expected = bodyRows.map((line) => `${chrome}${plainRow(line)}`.trimEnd());
	let window = -1;
	for (let start = 0; start + expected.length <= plains.length; start++) {
		if (expected.every((line, index) => plains[start + index] === line)) {
			window = start;
			break;
		}
	}
	if (window < 0) return undefined;
	const rows = composerCopyRows({
		bodyRows,
		chrome,
		logicalLines: input.logicalLines,
		visualMap: input.visualMap,
	});
	if (!rows || rows.length === 0) return undefined;
	const decorate = (screen: string): CopyRow => ({
		screen,
		clean: screen.startsWith(chrome) ? screen.slice(chrome.length) : "",
	});
	let low = window;
	let high = window + rows.length;
	while (low > 0 && isChromeRow(plains[low - 1], chrome)) low--;
	while (high < plains.length && isChromeRow(plains[high], chrome)) high++;
	return plains
		.slice(low, high)
		.map((screen, index) => rows[index - (window - low)] ?? decorate(screen));
}

/** 纯装饰行：只有左侧装饰（空行）也算。 */
function isChromeRow(screen: string, chrome: string): boolean {
	return screen.startsWith(chrome) || screen === chrome.trimEnd();
}

/** 在完整视觉行表里找到正好渲染成这批正文行的窗口；找不到说明映射不可信。 */
function findBodyWindow(
	visualMap: VisualLine[],
	bodies: string[],
	logicalLines: string[],
): number | undefined {
	for (let offset = 0; offset + bodies.length <= visualMap.length; offset++) {
		let match = true;
		for (let index = 0; index < bodies.length; index++) {
			const visual = visualMap[offset + index];
			const line = logicalLines[visual.logicalLine] ?? "";
			const chunk = line.slice(visual.startCol, visual.startCol + visual.length);
			// 行首可能有编辑器的 paddingX 空格，行尾被裁掉的空白不算差异。
			if (bodies[index].trimStart() !== chunk.trimEnd()) {
				match = false;
				break;
			}
		}
		if (match) return offset;
	}
	return undefined;
}

function stripRow(copied: string, row: CopyRow, chrome: string, first: boolean): string | undefined {
	if (copied === row.screen) return row.clean;
	// 选到了输入框右边界以外（同屏还有侧栏时）：去掉装饰，后面的内容原样留着。
	if (row.clean !== "" && copied.startsWith(row.screen)) {
		return `${row.clean}${copied.slice(row.screen.length)}`.trimEnd();
	}
	if (copied !== "" && row.clean) {
		// 选区在正文中间结束，或（第一行）从正文中间开始。
		if (row.clean.startsWith(copied)) return copied;
		if (first && row.clean.endsWith(copied)) return copied;
	}
	// 选区从左边缘开始：可能带上全部或一部分左侧装饰，逐级剥一级再对正文。
	for (let keep = 0; keep < chrome.length; keep++) {
		const prefix = chrome.slice(keep);
		if (!copied.startsWith(prefix)) continue;
		const rest = copied.slice(prefix.length);
		if (rest !== "" && row.clean.startsWith(rest)) return rest;
	}
	return undefined;
}

type Hit = { index: number; text: string; logical?: number; join?: string };
type Alignment = { skip: number; hits: Hit[] };

/** 只在前几个最近登记的渲染面里找对齐：可见内容总在表头，老消息不必扫。 */
const MAX_ALIGN_SURFACES = 16;
/** 允许跳过开头几行没登记过的内容（例如从消息框上边框里面开始拖）。 */
const MAX_SKIPPED_LINES = 3;

/** 选区必须落在同一个渲染面的连续行上；跨面板时只有对得上的那一段会被清洗。 */
function align(lines: string[]): Alignment | undefined {
	let best: Alignment | undefined;
	const skips = Math.min(MAX_SKIPPED_LINES, Math.max(0, lines.length - 1));
	for (let skip = 0; skip <= skips; skip++) {
		for (const surface of surfaces.slice(0, MAX_ALIGN_SURFACES)) {
			for (let start = 0; start < surface.rows.length; start++) {
				if (best && best.hits.length === lines.length) return best;
				const hits = runFrom(surface, start, lines, skip);
				if (hits && (!best || hits.length > best.hits.length)) best = { skip, hits };
			}
		}
	}
	return best;
}

function runFrom(surface: Surface, start: number, lines: string[], skip: number): Hit[] | undefined {
	const hits: Hit[] = [];
	for (let index = skip; index < lines.length; index++) {
		const row = surface.rows[start + index - skip];
		if (!row) break;
		const text = stripRow(lines[index], row, surface.chrome, index === skip);
		if (text === undefined) break;
		hits.push({ index: start + index - skip, text, logical: row.logical, join: row.join });
	}
	if (hits.length === 0) return undefined;
	// 单行匹配必须真把装饰去掉了，或整行与登记行完全相同。
	if (hits.length === 1 && lines.length === skip + 1) {
		const first = lines[skip];
		if (hits[0].text === first && first !== surface.rows[start].screen) return undefined;
	}
	return hits;
}

export function cleanCopiedText(text: string): string {
	if (surfaces.length === 0) return text;
	const lines = text.split("\n");
	const alignment = align(lines);
	if (!alignment) return text;
	const { skip, hits } = alignment;
	const out: string[] = [];
	for (let index = 0; index < lines.length; index++) {
		const hit = index >= skip ? hits[index - skip] : undefined;
		if (!hit) {
			out.push(lines[index]);
			continue;
		}
		const previous = index > skip ? hits[index - skip - 1] : undefined;
		const continues =
			previous !== undefined &&
			hit.index === previous.index + 1 &&
			hit.logical !== undefined &&
			hit.logical === previous.logical;
		if (out.length === 0) out.push(hit.text);
		else if (continues) out[out.length - 1] += `${previous.join ?? ""}${hit.text}`;
		else out.push(hit.text);
	}
	return out.join("\n");
}

function configuredCleanCopiedText(): boolean {
	try {
		const config = JSON.parse(readFileSync(join(getAgentDir(), "agent-skills-ui.json"), "utf8"));
		return typeof config?.cleanCopiedText === "boolean"
			? config.cleanCopiedText
			: DEFAULT_CLEAN_COPIED_TEXT;
	} catch {
		return DEFAULT_CLEAN_COPIED_TEXT;
	}
}

export function installCopyCleanup(
	tui: unknown,
	enabled: boolean = configuredCleanCopiedText(),
): void {
	if (!enabled) return;
	const target = tui as CopyRenderer | undefined;
	if (typeof target?.copySelection !== "function" || target[INSTALLED]) return;
	const base = target.copySelection;
	target[INSTALLED] = true;
	target.copySelection = (text: string) => base.call(target, cleanCopiedText(text));
}
