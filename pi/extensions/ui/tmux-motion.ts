import { readFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

/**
 * 多路复用器(尤其 tmux)下 pi 只申请 1002(按下/拖动),不申请 1003(无按键移动)——
 * pi-tui 的理由是"每次指针移动都要经复用器转发会拖慢渲染",代价是悬浮按钮与侧栏
 * hover 高亮彻底不出现(它们只吃 move 事件)。
 *
 * tmux 本身支持 1003:pane 里跑一个只写 `\e[?1003h` 的进程,`tmux display-message -p
 * '#{mouse_all_flag}'` 就从 0 变 1。DECSET 里 1002/1003 互斥、谁最后写谁生效,所以在 pi
 * 写完它自己的按键模式之后补一次即可,不必改 pi 本体(改 node_modules 会被 `pi update`
 * 覆盖,改 pi-tui 上游则是为了一个本机偏好)。
 *
 * 代价照旧:指针每跨一格都会产生一次转发,SSH + 大窗口下可能发卡 —— 不喜欢就关。
 * Toggle: `tmuxMouseMotion` in `agent-skills-ui.json` (default true)。
 */
export const DEFAULT_TMUX_MOUSE_MOTION = true;
const ENABLE_ANY_MOTION = "\u001b[?1003h";
const INSTALLED = Symbol("agent-skills.tmux-mouse-motion");

function configuredTmuxMouseMotion(): boolean {
	try {
		const config = JSON.parse(readFileSync(join(getAgentDir(), "agent-skills-ui.json"), "utf8"));
		return typeof config?.tmuxMouseMotion === "boolean"
			? config.tmuxMouseMotion
			: DEFAULT_TMUX_MOUSE_MOTION;
	} catch {
		return DEFAULT_TMUX_MOUSE_MOTION;
	}
}

/** 与 pi-tui 的降级条件对齐:它降级了我们才补。 */
function multiplexed(): boolean {
	const term = process.env.TERM?.toLowerCase() ?? "";
	return (
		process.env.TMUX !== undefined ||
		process.env.ZELLIJ !== undefined ||
		process.env.STY !== undefined ||
		term.startsWith("tmux") ||
		term.startsWith("screen")
	);
}

interface AltScreenLike {
	terminal?: { write?: (data: string) => void };
	beforeTerminalStart?: (...args: unknown[]) => void;
	mouseEnabled?: boolean;
	[symbol: symbol]: unknown;
}

/** 只对 fullscreen 的 TuiAltScreen 生效:普通模式的 TUI 不解析鼠标序列,别把 raw 字节灌进去。 */
export function installTmuxMouseMotion(tui: unknown): void {
	if (!multiplexed() || !configuredTmuxMouseMotion()) return;
	const target = tui as AltScreenLike | undefined;
	if (!target || target[INSTALLED] || target.mouseEnabled === false) return;
	if (typeof target.beforeTerminalStart !== "function") return;

	const write = (data: string): void => {
		if (typeof target.terminal?.write === "function") target.terminal.write(data);
		else process.stdout.write(data);
	};
	// 立即补一次:setEditorComponent 可能已经晚于 alt screen 启动。
	write(ENABLE_ANY_MOTION);
	// pi 每次进 alt screen 都会重写按键模式(那时 1002 会盖掉上面的 1003),跟着补。
	const base = target.beforeTerminalStart;
	target.beforeTerminalStart = (...args: unknown[]) => {
		base.apply(target, args);
		write(ENABLE_ANY_MOTION);
	};
	target[INSTALLED] = true;
}
