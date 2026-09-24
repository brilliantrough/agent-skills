#!/usr/bin/env node
// 划词复制清洗(copy-clean.ts)的回归。用真实的 pi-tui Editor 渲染出正文行,
// 再按 Pi 的 getActiveSelectionText() 的方式(按列切片、逐行 join("\n"))造出"剪贴板文本",
// 检查清洗结果恰好是用户输入文本的连续片段。最后一节直接加载真扩展的依赖闭包,验证登记链路。
if (!process.execArgv.includes("--experimental-transform-types")) {
	// ui.ts 的类用了 TS 参数属性,strip-only 模式加载不了;自己带标志重跑一遍。
	const { spawnSync } = await import("node:child_process");
	const child = spawnSync(
		process.execPath,
		["--experimental-transform-types", ...process.argv.slice(1)],
		{ stdio: "inherit" },
	);
	process.exit(child.status ?? 1);
}
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const root = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const require = createRequire(join(root, "package.json"));
const piTui = pathToFileURL(
	join(require.resolve("@earendil-works/pi-tui/package.json").replace(/package\.json$/, ""), "dist/index.js"),
).href;
const { Editor, sliceByColumn, stripTerminalSequences, truncateToWidth, visibleWidth } = await import(piTui);

const dir = mkdtempSync(join(tmpdir(), "copy-clean-"));
process.env.AGENT_DIR = dir;
process.on("exit", () => rmSync(dir, { recursive: true, force: true }));

function load(rel) {
	const source = readFileSync(join(root, rel), "utf8")
		.replace(/^import \{[^}]*\} from "@earendil-works\/pi-coding-agent";\n/gm, "")
		.replace(/from "@earendil-works\/pi-tui"/g, `from "${piTui}"`)
		.replace(/getAgentDir\(\)/g, "process.env.AGENT_DIR");
	const file = join(dir, rel.split("/").pop().replace(/\.ts$/, "") + ".ts");
	writeFileSync(file, source);
	return import(`file://${file}`);
}

const { cleanCopiedText, clearCopySurfaces, composerSurfaceRows, registerCopySurface, installCopyCleanup } =
	await load("pi/extensions/ui/editor/copy-clean.ts");

/**
 * 把 ui.ts 的依赖闭包摊平拷到仓内的临时目录(留在仓内才能解析 @earendil-works/pi-tui),
 * 把相对导入改成显式 .ts、把 getAgentDir 换成环境变量,就能在 Node 里直接加载真扩展。
 */
const closureDir = join(root, "tests", ".copy-clean-closure");
rmSync(closureDir, { recursive: true, force: true });
process.on("exit", () => rmSync(closureDir, { recursive: true, force: true }));

async function loadEditorClosure(entry) {
	mkdirSync(closureDir, { recursive: true });
	const queue = [join(root, entry)];
	const seen = new Set();
	while (queue.length > 0) {
		const file = queue.pop();
		if (seen.has(file)) continue;
		seen.add(file);
		const original = readFileSync(file, "utf8");
		writeFileSync(
			join(closureDir, basename(file)),
			original
				.replace(
					/^import \{ getAgentDir \} from "@earendil-works\/pi-coding-agent";\n/gm,
					"const getAgentDir = () => process.env.AGENT_DIR;\n",
				)
				.replace(
					/from "(\.\.?\/[^"]+)"/g,
					(_match, spec) => `from "./${basename(spec.replace(/\.js$/, ""))}.ts"`,
				),
		);
		for (const match of original.matchAll(/from "(\.\.?\/[^"]+)"/g)) {
			const spec = match[1];
			queue.push(
				join(
					dirname(file),
					spec.endsWith(".js") ? spec.replace(/\.js$/, ".ts") : `${spec}.ts`,
				),
			);
		}
	}
	return import(pathToFileURL(join(closureDir, basename(entry))).href);
}

const CHROME = "\u2502 ";
const theme = { borderColor: (s) => s, selectList: {} };
const plain = (text) => stripTerminalSequences(text).trimEnd();

let failures = 0;
const check = (name, ok, detail = "") => {
	console.log(`${ok ? "  ok  " : "  FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
	if (!ok) failures += 1;
};

/**
 * 用真实 editor 渲染正文行,再拼出一帧 opencode 风格的输入框
 * (上边框 → 空行 → 正文 → 空行 → 元信息行 → 下边框 → 补全菜单),
 * 走生产路径 composerSurfaceRows 登记渲染面。
 */
function composerSurface(text, width) {
	const editor = new Editor({ terminal: { rows: 40 }, requestRender() {}, invalidate() {} }, theme, {
		paddingX: 0,
	});
	editor.focused = true;
	editor.setText(text);
	// 生产里基编辑器按 innerWidth 渲染（railWidth 之外全给正文）。
	const innerWidth = Math.max(1, width - visibleWidth(CHROME));
	const rendered = editor.render(innerWidth);
	const bodyRows = rendered.slice(1, -1).map(plain);
	const meta = `${CHROME}meta line`;
	const completion = ["  completion item", "  another item"];
	// 生产里每行都被填充到面板宽度（fillLine），边框撑满整宽。这样跟真实屏幕一致，
	// 侧栏内容从第 width 列开始，裁掉就能对上本面板这一行。
	const fill = (line) => truncateToWidth(`${line}${" ".repeat(Math.max(0, width - visibleWidth(line)))}`, width, "");
	const frame = [
		"─".repeat(width),
		fill(CHROME.trimEnd()),
		...bodyRows.map((row) => fill(`${CHROME}${row}`)),
		fill(CHROME.trimEnd()),
		fill(meta),
		"─".repeat(width),
		...completion,
	];
	const rows = composerSurfaceRows({
		frameRows: frame,
		bodyRows,
		chrome: CHROME,
		logicalLines: editor.getLines(),
		visualMap: editor.buildVisualLineMap(editor.lastWidth),
	});
	if (!rows) return undefined;
	registerCopySurface("composer", CHROME, rows);
	return {
		screenRows: rows.map((row) => row.screen),
		// 正文行 = 带逻辑行号的那几行。
		bodyStart: rows.findIndex((row) => row.logical !== undefined),
		bodyEnd: rows.findLastIndex((row) => row.logical !== undefined),
		frame,
		width,
		frameBodyStart: 2,
		completion: completion.map(plain),
		logical: editor.getLines().join("\n"),
	};
}

/** Pi 的 getActiveSelectionText():按列切片 → 去 ANSI → 每行 trimEnd → join("\n")。 */
function clipboard(screenRows, startRow, startCol, endRow, endCol) {
	const lines = [];
	for (let row = startRow; row <= endRow; row++) {
		const line = screenRows[row] ?? "";
		const from = row === startRow ? startCol : 0;
		const to = row === endRow ? endCol : visibleWidth(line);
		lines.push(plain(sliceByColumn(line, from, Math.max(0, to - from), true)));
	}
	return lines.join("\n");
}

const TEXTS = [
	"这是一个很长的一次性提示词，全程没有按回车，只是被输入框自然折行显示成两行而已，后面还有一些字。",
	"the quick brown fox jumps over the lazy dog and keeps running past the edge of the terminal width",
	"第一行比较短\n第二行很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长",
	"\nabc 中文 mixed 混排 content with 空格 and more words to force wrapping at boundary",
	"trailing spaces    here and then a long tail that must wrap somewhere near the boundary",
	"hello world",
	"一\n二\n三",
];

// 1) 选中整段正文(含左侧装饰)必须还原成用户输入的原文。
//    frame 才是真实屏幕:上/下边框 + 空行 + 正文 + 元信息行;同屏有侧栏时右侧还会接上侧栏内容。
const sidebarOf = (index) =>
	["", "╭─ TOOLS ──╮", "│ 40/46 active ▸ │", "╰──────────╯", "", "", "side 3", ""][index] ?? "侧栏";
/** 拖到上下边框的一半（选中的只有 ─）：也是装饰，应当丢掉。 */
const cleanupCase = (surface, width) => {
	const rows = surface.frame.slice(0, surface.frame.length - 2);
	const lines = rows.map((row, index) => {
		const padded = `${row}${" ".repeat(Math.max(0, width - visibleWidth(row)))}`;
		if (index === 0) return padded.slice(4);
		if (index === rows.length - 1) return padded.slice(0, 20);
		return padded;
	});
	return cleanCopiedText(lines.join("\n"));
};

const dragWholeBox = (surface, width, withSidebar) => {
	// frame = [上边框, 空行, 正文…, 空行, 元信息行, 下边框, 补全项 x2];
	// 只拖输入框自己的那几行（补全菜单是浮层）。
	const composerRows = surface.frame.slice(0, surface.frame.length - 2);
	const rows = composerRows.map((row, index) => {
		const padded = `${row}${" ".repeat(Math.max(0, width - visibleWidth(row)))}`;
		return withSidebar ? `${padded}${sidebarOf(index)}` : row;
	});
	return clipboard(rows, 0, 0, rows.length - 1, 1000);
};

for (const text of TEXTS) {
	for (const width of [39, 60, 79]) {
		clearCopySurfaces();
		const surface = composerSurface(text, width);
		if (!surface) {
			check(`登记失败 ${width}`, false, JSON.stringify(text));
			continue;
		}
		const copied = clipboard(surface.screenRows, surface.bodyStart, 0, surface.bodyEnd, 1000);
		const cleaned = cleanCopiedText(copied);
		check(`整段还原 @${width} ${JSON.stringify(text.slice(0, 12))}`, cleaned === text, JSON.stringify(cleaned));
		// 拖到边框的一半(上下边框都是 ─):也是装饰,不该混进正文。
		clearCopySurfaces();
		const partial = cleanupCase(composerSurface(text, width), width);
		check(
			`半截边框不混进正文 @${width} ${JSON.stringify(text.slice(0, 8))}`,
			partial === text,
			JSON.stringify(partial),
		);
		// 真实现场:拖过整个输入框(带边框/空行/元信息行),右侧还拼着侧栏。
		for (const withSidebar of [false, true]) {
			clearCopySurfaces();
			const fresh = composerSurface(text, width);
			const whole = cleanCopiedText(dragWholeBox(fresh, width, withSidebar));
			check(
				`拖过整个输入框${withSidebar ? "(有侧栏)" : ""} @${width} ${JSON.stringify(text.slice(0, 8))}`,
				whole === text,
				JSON.stringify(whole),
			);
		}
	}
}

// 2) 任意选区清洗后,必须仍然是原文的连续片段(不出现装饰、不丢字、不多字)。
for (const text of TEXTS) {
	for (const width of [39, 60, 79]) {
		const surface = composerSurface(text, width);
		if (!surface) continue;
		const first = surface.bodyStart;
		const last = surface.bodyEnd;
		const cuts = [
			[first, 0, last, 1000],
			[first, 1, last, 1000],
			[first, 2, last, 1000],
			[first, 3, last, 1000],
			[first, 0, last, 7],
			[first, 2, last, 7],
			[first, 5, last, 1000],
			[Math.min(first + 1, last), 0, last, 1000],
			[first, 0, Math.max(first, last - 1), 1000],
			[first, 4, Math.max(first, last - 1), 9],
		];
		for (const [startRow, startCol, endRow, endCol] of cuts) {
			if (endRow < startRow) continue;
			clearCopySurfaces();
			const fresh = composerSurface(text, width);
			const copied = clipboard(fresh.screenRows, startRow, startCol, endRow, endCol);
			const cleaned = cleanCopiedText(copied);
			const inside = text.includes(cleaned) || cleaned === "";
			check(
				`片段 ${JSON.stringify(text.slice(0, 8))} @${width} [${startRow},${startCol}→${endRow},${endCol}]`,
				inside && !cleaned.includes("\u2502"),
				JSON.stringify(cleaned),
			);
		}
	}
}

// 2b) 从正文一直选到补全菜单:补全行的文本必须原样保留(它不在登记表里,不能被当成装饰清空)。
{
	clearCopySurfaces();
	const surface = composerSurface("一\n二", 60);
	const copied = clipboard(
		surface.frame,
		surface.frameBodyStart,
		0,
		surface.frame.length - 1,
		1000,
	);
	const cleaned = cleanCopiedText(copied);
	check(
		"补全行不被清空",
		surface.completion.every((line) => cleaned.includes(line)),
		JSON.stringify(cleaned),
	);
}

// 3) 单行选区(拖一行)也要把行首装饰去掉。
{
	clearCopySurfaces();
	const surface = composerSurface("单独一行短文本", 60);
	const copied = clipboard(surface.screenRows, surface.bodyStart, 0, surface.bodyStart, 1000);
	check("单行去装饰", cleanCopiedText(copied) === "单独一行短文本", JSON.stringify(cleanCopiedText(copied)));
}

// 4) 用户消息框(framed 风格):去装饰,上下两条分隔线整行清空,不做折行合并。
{
	clearCopySurfaces();
	const rule = "\u2500".repeat(40);
	const rows = [rule, CHROME.trimEnd(), `${CHROME}第一段`, `${CHROME}折行的第二段`, CHROME.trimEnd(), rule];
	registerCopySurface("message:1", CHROME, rows.map((line) => {
		const screen = plain(line);
		return { screen, clean: screen.startsWith(CHROME) ? screen.slice(CHROME.length) : "" };
	}));
	const copied = rows.map(plain).join("\n");
	const cleaned = cleanCopiedText(copied);
	check(
		"用户消息去装饰(从正文第一行拖)",
		cleaned === "\n\n第一段\n折行的第二段\n\n",
		JSON.stringify(cleaned),
	);
	// 从上边框里面开始拖：选中的只有半截 ─，也是装饰，一起丢掉。
	const fromRule = [plain(rows[0]).slice(0, 20), ...rows.slice(1).map(plain)].join("\n");
	const cleanedRule = cleanCopiedText(fromRule);
	check(
		"用户消息去装饰(从上边框内起拖)",
		cleanedRule === "\n\n第一段\n折行的第二段\n\n",
		JSON.stringify(cleanedRule),
	);
}

// 5) 不认识的内容原样返回,绝不误伤。
{
	clearCopySurfaces();
	const text = "assistant 输出里的普通文本\n第二行\n第三行";
	check("无关文本不动", cleanCopiedText(text) === text, JSON.stringify(cleanCopiedText(text)));
	clearCopySurfaces();
	const surface = composerSurface("hello world", 60);
	check("无登记面时不动", cleanCopiedText("hello\nworld") === "hello\nworld");
	check("登记面存在但行不匹配时不动", cleanCopiedText("完全无关的一行") === "完全无关的一行", String(surface));
}

// 6) 钩子:包装 copySelection 后落到剪贴板的必须是清洗过的文本。
{
	clearCopySurfaces();
	const surface = composerSurface("钩子测试文本", 60);
	// 同屏有侧栏时，输入框那一行的右边会接上侧栏内容：裁掉别人的，只留本面板的。
	const SIDEBAR = ["", "", "  ╭─ TOOLS ─╮", "  │ 40/46 active ▸ │", "  ╰───╯", "", ""];
	const composed = surface.screenRows.map((row, index) => {
		const pad = " ".repeat(Math.max(0, 60 - visibleWidth(row)));
		return `${row}${pad}${SIDEBAR[index] ?? " 新内容"}`;
	});
	const composedCopy = clipboard(composed, surface.bodyStart, 0, surface.bodyStart, 1000);
	check(
		"侧栏内容不混进正文",
		cleanCopiedText(composedCopy) === "钩子测试文本",
		JSON.stringify(cleanCopiedText(composedCopy)),
	);
	const captured = [];
	const fakeTui = { copySelection: async (text) => (captured.push(text), true) };
	installCopyCleanup(fakeTui, true);
	await fakeTui.copySelection(clipboard(surface.screenRows, surface.bodyStart, 0, surface.bodyStart, 1000));
	check("copySelection 钩子", captured[0] === "钩子测试文本", JSON.stringify(captured[0]));
	const off = { copySelection: async (text) => (captured.push(text), true) };
	installCopyCleanup(off, false);
	await off.copySelection("不清洗");
	check("开关关闭时不包装", captured[1] === "不清洗", JSON.stringify(captured[1]));
}

// 7) 集成:真正的 WrappedPolishedEditor 渲染一帧 → 自助登记 → 从帧里模拟拖选复制。
//    这一节证明 ui.ts 里的登记链路确实生效(而不只是纯函数对)。
{
	const closure = await loadEditorClosure("pi/extensions/ui/editor/ui.ts");
	const closureCopy = await import(pathToFileURL(join(closureDir, "copy-clean.ts")).href);
	const closureConfig = await import(pathToFileURL(join(closureDir, "config.ts")).href);
	const uiTheme = { fg: (_color, text) => text, bold: (t) => t, italic: (t) => t, underline: (t) => t };
	const text = "集成测试用的一段提示词，不按回车、被输入框自然折行显示成多行。";
	for (const style of ["opencode", "accent-rail"]) {
		// accent-rail 的装饰字符与 icons.rail 不同,单独跑一遍证明取的是同一个来源。
		const chrome = style === "accent-rail" ? "\u258e " : CHROME;
		for (const width of [60, 79]) {
			closureCopy.clearCopySurfaces();
			const editor = new Editor({ terminal: { rows: 40 }, requestRender() {}, invalidate() {} }, theme, {
				paddingX: 0,
			});
			editor.focused = true;
			editor.setText(text);
			const baseConfig = closureConfig.loadConfig();
			const config = {
				...baseConfig,
				components: {
					...baseConfig.components,
					editor: { ...baseConfig.components.editor, style },
				},
			};
			const wrapped = new closure.WrappedPolishedEditor(
				editor,
				uiTheme,
				() => config,
				() => ({ modelLabel: "m", modelId: "m", providerLabel: "p" }),
				() => "high",
			);
			const frame = wrapped.render(width);
			const bodyIndexes = frame
				.map((line, index) => ({ line: plain(line), index }))
				.filter((row) => row.line.startsWith(chrome))
				.map((row) => row.index);
			const copied = clipboard(frame, bodyIndexes[0], 0, bodyIndexes.at(-1), 1000);
			const cleaned = closureCopy.cleanCopiedText(copied);
			check(
				`集成:${style} 渲染帧已登记并清洗 @${width}`,
				cleaned.includes(text) && !cleaned.includes(chrome.slice(0, 1)),
				JSON.stringify(cleaned),
			);
		}
	}
}

console.log(failures === 0 ? "\nALL OK" : `\n${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
