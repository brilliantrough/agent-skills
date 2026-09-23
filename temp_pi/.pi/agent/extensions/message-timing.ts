/**
 * message-timing.ts
 *
 * 在 TUI 中，整个 agent loop 结束后在其结尾显示一行：
 *   YYYY-MM-DD HH:MM:SS S.fff s
 *   - YYYY-MM-DD：消息结束时刻的日期
 *   - HH:MM:SS ：消息结束时刻的当前时间（精确到秒）
 *   - S.fff s  ：这一步的执行耗时（单位秒，精确到毫秒）
 *
 * 计时口径：
 *   - 仅在整个 agent loop（一次输入触发的完整运行，含自动重试、
 *     自动压缩重试、排队后续消息）结束后显示一行
 *   - 耗时 = 整个 loop 的总耗时（agent_start → agent_settled），
 *     包含所有 LLM 调用与工具执行
 *
 * 显示实现：pi.appendEntry() 写入 custom entry，并由
 * pi.registerEntryRenderer() 渲染。custom entry 不参与 LLM 上下文，
 * 仅保存在会话文件中用于 TUI 显示（重启/恢复会话后依然可见）。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

interface StepTimingData {
	time: string;
	durationMs: number;
}

const pad2 = (n: number): string => String(n).padStart(2, "0");

function clockNow(): string {
	const d = new Date();
	const date = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
	return ` ${date} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

export default function (pi: ExtensionAPI) {
	pi.registerEntryRenderer<StepTimingData>(
		"step-timing",
		(entry, _options, theme) => ({
			render: (width: number) => {
				const data = entry.data ?? { time: "-:--:--", durationMs: 0 };
				const plain = `${data.time} ${(data.durationMs / 1000).toFixed(3)}s`;
				const line = theme.fg(
					"dim",
					plain.length <= width ? plain : plain.slice(0, width)
				);
				return [line];
			},
			invalidate: () => {},
		})
	);

	// loop 起点：agent_start 在每次底层运行开始时触发；自动重试/排队后续
	// 消息会触发新的运行，但属于同一个 loop，只在首个运行时记录起点。
	let loopStart: number | undefined;

	pi.on("agent_start", () => {
		if (loopStart === undefined) loopStart = performance.now();
	});

	// agent_settled：本次 loop 彻底结束（无自动重试、压缩重试或排队后续
	// 消息）。此时全部消息 entry 均已落盘，直接追加计时行即位于末尾。
	pi.on("agent_settled", (_event, ctx) => {
		if (ctx.mode !== "tui" || loopStart === undefined) return;
		const durationMs = Math.max(0, performance.now() - loopStart);
		loopStart = undefined;
		pi.appendEntry<StepTimingData>("step-timing", {
			time: clockNow(),
			durationMs,
		});
	});
}
