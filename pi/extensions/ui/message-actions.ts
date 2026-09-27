import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
	AssistantMessageComponent,
	UserMessageComponent,
	copyToClipboard,
	getAgentDir,
	type ExtensionAPI,
	type ExtensionContext,
	type Theme,
} from "@earendil-works/pi-coding-agent";
import { compositeTuiLine, visibleWidth } from "@earendil-works/pi-tui";
import {
	installPrototypePatch,
	removePrototypePatch,
	type PatchInvocation,
	type PrototypeResultLike,
} from "./editor/prototype-patch-registry.js";

/**
 * 主栏消息悬浮按钮：指针悬停某条消息时，把按钮覆写到该消息的【第一行】右端
 * （用户消息：⧉ 复制 / ⟲ 回撤；助手消息：⧉ 复制），指针悬停在按钮上时只高亮
 * 那一个按钮。消息块本身不做高亮——用户明确只要"按钮高亮"，块级高亮会干扰阅读。
 *
 * 「⟲ 回撤」不是回填编辑，而是把会话 leaf 移回该用户消息之前：该消息及其后的
 * 上下文全部离开当前分支（等价 OpenCode /undo、Pi /tree 选中用户消息），消息
 * 文本由 navigateTree 自动回到输入框（仅当输入框为空时）。原分支不删除，
 * /tree 仍可找回。实现走 /rewind 命令中转：pi.sendUserMessage("/rewind <id>",
 * {expandPromptTemplates:true}) 在 prompt() 里先于模型校验派发扩展命令，零模型轮、
 * 不写会话；命令 handler 拿到 ExtensionCommandContext.navigateTree —— 该 API 只在
 * 命令语境存在，扩展事件/UI 回调里都够不到。
 *
 * 组件实例 → entry id 的映射：转录渲染严格按 buildContextEntries() 顺序为每条
 * 可渲染用户消息建一个 UserMessageComponent（skill 块消息按 parseSkillBlock 规则
 * 只为内嵌 userMessage 建组件）。点击时从 tui 向下 DFS 数出该组件在同类中的序号，
 * 对齐到第 N 个可渲染用户 entry；序号校验失败再退回全文唯一匹配，仍不唯一则拒绝。
 *
 * 关键设计约束：
 * ① 不改行数。第一版在消息尾部追加按钮行，会让 hovered 消息高一行，pretty-tui 的
 *    Running/Done 折叠块按行号做命中，行号一偏就点不开；覆写首行不动布局。
 * ② 不拦截的事件一律转交前任链。第一版对 press/click 直接 return undefined，
 *    跳过了前任（Container 的子组件派发），pretty-tui 的折叠点击随之失效。
 * ③ 离开高亮靠中枢兜底：组件只收得到"在自己身上"的 move，所以在 TUI 实例的
 *    handleMouseEvent 外包一层（installMessageActionsViewportHook），每次 move
 *    若没有消息认领就清除悬停。
 *
 * Toggle: `messageActions` in `agent-skills-ui.json` (default true)。
 * tmux 下 Pi 不上报 move，按钮不会出现；点击路由不受影响。
 */

type ActionId = "copy" | "rewind";
type MessageKind = "user" | "assistant";

interface ButtonSpan {
	action: ActionId;
	start: number;
	end: number;
}

interface MessageLike {
	text?: unknown;
	lastMessage?: { content?: unknown };
}

interface MouseEventLike {
	type: string;
	x: number;
	y: number;
	button?: string;
}

interface ViewportMouseTarget {
	handleMouseEvent?: (raw: { button: number; release?: boolean }) => void;
	requestRender?: () => void;
	[key: symbol]: unknown;
}

let hovered: object | undefined;
let hoveredButton: ActionId | undefined;
let ctxRef: ExtensionContext | undefined;
let themeRef: (() => Theme | undefined) | undefined;
let piRef: ExtensionAPI | undefined;
let tuiRef: unknown;

/** 中枢 move 计数：handleMouseEvent 每见一次无按键 move 就 +1；消息组件认领时同步。 */
let moveTick = 0;
let moveClaim = 0;

/** 每条实例当前按钮行的命中表（覆写首行，y 恒为 0）。 */
const buttonSpans = new WeakMap<WeakKey, ButtonSpan[]>();

function configuredEnabled(): boolean {
	try {
		const config = JSON.parse(readFileSync(join(getAgentDir(), "agent-skills-ui.json"), "utf8"));
		return typeof config?.messageActions === "boolean" ? config.messageActions : true;
	} catch {
		return true;
	}
}

function isObject(value: unknown): value is object {
	return typeof value === "object" && value !== null;
}

function messageText(kind: MessageKind, receiver: MessageLike): string {
	if (kind === "user") return typeof receiver.text === "string" ? receiver.text : "";
	const content = receiver.lastMessage?.content;
	if (!Array.isArray(content)) return "";
	return content
		.filter((part): part is { type: string; text: string } =>
			Boolean(part && typeof part === "object" && (part as { type?: unknown }).type === "text" && typeof (part as { text?: unknown }).text === "string"))
		.map((part) => part.text)
		.join("\n\n");
}

function buttonDefs(kind: MessageKind): { action: ActionId; text: string }[] {
	return kind === "user"
		? [{ action: "copy", text: "⧉ 复制" }, { action: "rewind", text: "⟲ 回撤" }]
		: [{ action: "copy", text: "⧉ 复制" }];
}

/**
 * 把按钮右对齐覆写到首行：保留左半与最右一列（气泡的右边框），中间换成按钮。
 * 终端太窄时放弃覆写（返回 undefined），消息保持原样。
 */
function overlayButtons(
	line: string,
	width: number,
	kind: MessageKind,
): { line: string; spans: ButtonSpan[] } | undefined {
	const theme = themeRef?.();
	const defs = buttonDefs(kind);
	const plain = defs.map((d) => `[${d.text}]`).join("  ");
	const buttonsWidth = visibleWidth(plain);
	const startCol = width - buttonsWidth - 3;
	if (startCol < 4) return undefined;

	let styled = "";
	let cursor = startCol + 1;
	const spans: ButtonSpan[] = [];
	defs.forEach((def, index) => {
		const label = `[${def.text}]`;
		spans.push({ action: def.action, start: cursor, end: cursor + visibleWidth(label) });
		const hoveredThis = hoveredButton === def.action;
		styled += (index > 0 ? "  " : "") + (theme
			? hoveredThis ? theme.bg("selectedBg", theme.fg("accent", label)) : theme.fg("muted", label)
			: label);
		cursor += visibleWidth(label) + 2;
	});

	return {
		line: compositeTuiLine(line, ` ${styled} `, startCol, buttonsWidth + 2, width),
		spans,
	};
}

function hitButton(receiver: WeakKey, event: MouseEventLike): ButtonSpan | undefined {
	if (event.y !== 0) return undefined;
	return buttonSpans.get(receiver)?.find((span) => event.x >= span.start && event.x < span.end);
}

/** 与 core parseSkillBlock 同一正则：skill 块消息只为内嵌 userMessage 建用户组件。 */
const SKILL_BLOCK_RE = /^<skill name="([^"]+)" location="([^"]+)">\n([\s\S]*?)\n<\/skill>(?:\n\n([\s\S]+))?$/;

/** 镜像 AgentSession.getUserMessageText：字符串 content 原样，数组只拼 text 块。 */
function entryUserText(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.filter((part): part is { type: "text"; text: string } =>
			Boolean(part && typeof part === "object" && (part as { type?: unknown }).type === "text" && typeof (part as { text?: unknown }).text === "string"))
		.map((part) => part.text)
		.join("");
}

interface RenderableUserEntry {
	id: string;
	/** 该 entry 渲染出的 UserMessageComponent 的文本（skill 块为内嵌 userMessage）。 */
	componentText: string;
}

/** 按转录渲染规则枚举当前分支上会产生 UserMessageComponent 的用户 entry。 */
function renderableUserEntries(): RenderableUserEntry[] {
	const out: RenderableUserEntry[] = [];
	for (const entry of ctxRef?.sessionManager.buildContextEntries() ?? []) {
		if (entry.type !== "message") continue;
		const message = entry.message as { role?: string; content?: unknown } | undefined;
		if (!message || message.role !== "user") continue;
		const text = entryUserText(message.content);
		if (!text) continue; // 纯图片等无文本：不建组件
		const skill = text.match(SKILL_BLOCK_RE);
		if (skill) {
			const userMessage = skill[4]?.trim() || undefined;
			if (userMessage) out.push({ id: entry.id, componentText: userMessage });
		} else {
			out.push({ id: entry.id, componentText: text });
		}
	}
	return out;
}

/** 从 tui 向下 DFS 收集转录里的 UserMessageComponent（显示顺序）。 */
function transcriptUserComponents(): object[] {
	const order: object[] = [];
	const visit = (node: unknown): void => {
		const children = (node as { children?: unknown } | undefined)?.children;
		if (!Array.isArray(children)) return;
		for (const child of children) {
			if (child instanceof UserMessageComponent) order.push(child);
			else visit(child);
		}
	};
	visit(tuiRef);
	return order;
}

/** 悬停组件 → 会话 entry id：序号对齐优先，全文唯一匹配兜底，无法唯一定位则 undefined。 */
function resolveUserEntryId(receiver: MessageLike): string | undefined {
	const text = messageText("user", receiver).trim();
	if (!text) return undefined;
	const candidates = renderableUserEntries();
	const index = transcriptUserComponents().indexOf(receiver);
	if (index >= 0 && index < candidates.length && candidates[index].componentText.trim() === text) {
		return candidates[index].id;
	}
	const byText = candidates.filter((candidate) => candidate.componentText.trim() === text);
	return byText.length === 1 ? byText[0].id : undefined;
}

async function runAction(kind: MessageKind, receiver: MessageLike, action: ActionId): Promise<void> {
	const ui = ctxRef?.ui;
	if (!ui) return;
	if (action === "rewind") {
		if (kind !== "user") return;
		if (!ctxRef?.isIdle()) {
			ui.notify("等当前回复结束后再回撤", "warning");
			return;
		}
		const entryId = resolveUserEntryId(receiver);
		if (!entryId) {
			ui.notify("无法唯一定位该消息在会话中的位置，请用 /tree 回退", "error");
			return;
		}
		// 经 /rewind 命令中转拿 navigateTree：命令在 prompt() 里先于模型校验派发，零模型轮。
		piRef?.sendUserMessage(`/rewind ${entryId}`, { expandPromptTemplates: true });
		return;
	}
	const text = messageText(kind, receiver);
	if (!text) {
		ui.notify("该消息没有可复制的文本", "warning");
		return;
	}
	try {
		await copyToClipboard(text);
		ui.notify("已复制该消息原文", "info");
	} catch (error) {
		ui.notify(`复制失败：${error instanceof Error ? error.message : String(error)}`, "error");
	}
}

function renderWithHover(behavior: PatchInvocation, kind: MessageKind): PrototypeResultLike {
	const { predecessor, receiver, args } = behavior;
	const lines = predecessor.apply(receiver, args);
	if (!Array.isArray(lines) || lines.length === 0) return lines;
	if (!configuredEnabled() || hovered !== receiver || typeof args[0] !== "number" || !isObject(receiver)) {
		return lines;
	}
	const overlaid = overlayButtons(String(lines[0]), args[0], kind);
	if (!overlaid) return lines;
	buttonSpans.set(receiver, overlaid.spans);
	const next = lines.slice();
	next[0] = overlaid.line;
	return next;
}

function handleMouseWithActions(behavior: PatchInvocation, kind: MessageKind): PrototypeResultLike {
	const { predecessor, receiver, args } = behavior;
	const event = args[0] as MouseEventLike | undefined;
	if (!event || !isObject(receiver) || !configuredEnabled()) {
		return predecessor.apply(receiver, args);
	}
	if (event.type === "move") {
		moveClaim = moveTick; // 指针在本消息上：中枢兜底据此保留悬停
		const hit = hitButton(receiver, event)?.action;
		const changed = hovered !== receiver || hoveredButton !== hit;
		hovered = receiver;
		hoveredButton = hit;
		// 始终转交前任链（pretty-tui 的 markdown/折叠行有自己的 move 逻辑），只合并 render 标记。
		const pre = predecessor.apply(receiver, args);
		if (pre && typeof pre === "object") return changed ? { ...pre, render: true } : pre;
		return changed ? { handled: true, render: true } : { handled: true };
	}
	if (event.type === "press") {
		// 吃掉按钮上的 press：不要开始文本选区，松手的 click 才会派回本组件。
		if (hovered === receiver && hitButton(receiver, event)) return { handled: true };
		return predecessor.apply(receiver, args);
	}
	if (event.type === "click") {
		const button = hovered === receiver ? hitButton(receiver, event) : undefined;
		if (button) {
			void runAction(kind, receiver as MessageLike, button.action);
			return { handled: true, render: true };
		}
		return predecessor.apply(receiver, args);
	}
	return predecessor.apply(receiver, args);
}

/**
 * 中枢悬停兜底：组件收不到"指针去了别处"的事件，在 TUI 实例的 handleMouseEvent 外包一层，
 * 每次无按键 move 若没有任何消息组件认领（moveClaim 未同步到 moveTick），清除悬停并重绘。
 */
export function installMessageActionsViewportHook(tui: unknown): void {
	tuiRef = tui;
	// SAFETY: Pi fullscreen 的 TUI 实例运行时是 TuiAltScreen，handleMouseEvent 是普通类方法。
	const target = tui as ViewportMouseTarget;
	if (typeof target?.handleMouseEvent !== "function") return;
	const MARK = Symbol.for("agent-skills.message-actions-viewport-hook");
	if (target[MARK]) return;
	const base = target.handleMouseEvent;
	target[MARK] = true;
	target.handleMouseEvent = (raw: { button: number; release?: boolean }) => {
		const isPlainMove = !raw.release && (raw.button & 32) !== 0 && (raw.button & 3) === 3;
		if (!isPlainMove) {
			base.call(target, raw);
			return;
		}
		moveTick += 1;
		base.call(target, raw);
		if (hovered !== undefined && moveClaim !== moveTick) {
			hovered = undefined;
			hoveredButton = undefined;
			target.requestRender?.();
		}
	};
}

/**
 * 注册 /rewind 命令：悬浮按钮点击经 sendUserMessage 派发到此处，借此拿到只存在于
 * 命令语境的 ExtensionCommandContext.navigateTree（interactive 绑定会同步刷新转录并
 * 在输入框为空时回填消息文本）。参数是目标用户消息的 entry id；手动执行亦可。
 */
export function registerRewindCommand(pi: ExtensionAPI): void {
	pi.registerCommand("rewind", {
		description: "回撤会话到指定用户消息之前（悬浮按钮内部使用，参数为 entry id）",
		handler: async (args, ctx) => {
			const entryId = args.trim();
			if (!entryId) {
				ctx.ui.notify("用法：/rewind <entryId>", "warning");
				return;
			}
			try {
				const result = await ctx.navigateTree(entryId, { summarize: false });
				if (result.cancelled) {
					ctx.ui.notify("回撤已取消", "warning");
					return;
				}
				ctx.ui.notify("已回撤：该消息及其后的上下文已离开当前分支（/tree 可找回，文本已回到输入框）", "info");
			} catch (error) {
				ctx.ui.notify(`回撤失败：${error instanceof Error ? error.message : String(error)}`, "error");
			}
		},
	});
}

/**
 * 安装主栏消息的悬浮按钮补丁。返回清理函数（session_shutdown 时调用）。
 * 补丁走注册表的命名适配器；必须最后安装（气泡分支会丢弃前任 render 输出）。
 */
export function installMessageActions(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	getTheme: () => Theme | undefined,
): () => void {
	ctxRef = ctx;
	themeRef = getTheme;
	piRef = pi;
	const userPrototype = UserMessageComponent.prototype as never;
	const assistantPrototype = AssistantMessageComponent.prototype as never;
	const registrations = [
		installPrototypePatch(userPrototype, "render", "message-actions-user-render", (b) => renderWithHover(b, "user")),
		installPrototypePatch(userPrototype, "handleMouse", "message-actions-user-mouse", (b) => handleMouseWithActions(b, "user")),
		installPrototypePatch(assistantPrototype, "render", "message-actions-assistant-render", (b) => renderWithHover(b, "assistant")),
		installPrototypePatch(assistantPrototype, "handleMouse", "message-actions-assistant-mouse", (b) => handleMouseWithActions(b, "assistant")),
	];
	let cleaned = false;
	return () => {
		if (cleaned) return;
		cleaned = true;
		hovered = undefined;
		hoveredButton = undefined;
		ctxRef = undefined;
		themeRef = undefined;
		piRef = undefined;
		for (const registration of registrations) registration();
	};
}

/** 供显式拆除（与 installMessageActions 的返回清理等价，按需使用）。 */
export function removeMessageActions(): void {
	const userPrototype = UserMessageComponent.prototype as never;
	const assistantPrototype = AssistantMessageComponent.prototype as never;
	removePrototypePatch(userPrototype, "render", "message-actions-user-render");
	removePrototypePatch(userPrototype, "handleMouse", "message-actions-user-mouse");
	removePrototypePatch(assistantPrototype, "render", "message-actions-assistant-render");
	removePrototypePatch(assistantPrototype, "handleMouse", "message-actions-assistant-mouse");
	hovered = undefined;
	hoveredButton = undefined;
	ctxRef = undefined;
	themeRef = undefined;
	piRef = undefined;
}
