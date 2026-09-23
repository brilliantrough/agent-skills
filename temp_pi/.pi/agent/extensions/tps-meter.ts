/**
 * tps-meter.ts
 *
 * 参考 OpenCode 的 oc-tps 插件，在 TUI 右下角 footer 状态栏显示：
 *
 *   TPS 42.5 | AVG 38.2 | TTFT 0.8s | yolo | 0.0%/1.0M (auto) | ↑0 ↓0 | $0.000
 *
 * 指标口径（对齐 oc-tps）：
 *   - TPS ：实时出词速度。5 秒滚动窗口内的 delta 采样
 *           （token 估算 = UTF-8 字节数 / 5 向上取整，至少 1），
 *           TPS = 窗口内估算 tokens / 活跃时长；1.5s 无新数据、
 *           工具执行期间或空闲时显示 "-"
 *   - AVG ：会话累计平均出词速度。每条完成的 assistant 消息贡献
 *           usage.output 个 token 与（首 token → 末 token）时长
 *   - TTFT：会话平均首 token 延迟（provider 请求发出 → 首个
 *           text/thinking delta）的平均值
 *
 * 显示实现：ctx.ui.setStatus() 将状态写入 footer 状态栏。pi-zentui
 * 会把 extension status 拼在 yolo | context% | ↑↓ | $cost 一行的
 * 左侧（内置 footer 则渲染为独立状态行）。setStatus 内部自动
 * requestRender；delta 到达与每秒定时器刷新文本。
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const STREAM_WINDOW_MS = 5_000;
const LIVE_STALE_MS = 1_500;
const SINGLE_SAMPLE_MS = 1_000;

type StreamSample = { at: number; tokens: number };

/** token 估算：UTF-8 字节数 / 5，向上取整，至少 1（与 oc-tps 一致） */
function estimateTokens(delta: string): number {
	return Math.max(1, Math.ceil(Buffer.byteLength(delta, "utf8") / 5));
}

function formatRate(value: number): string {
	if (!Number.isFinite(value) || value <= 0) return "-";
	if (value >= 100) return String(Math.round(value));
	if (value >= 10) return value.toFixed(1);
	return value.toFixed(2);
}

function formatTtft(valueMs: number): string {
	if (!Number.isFinite(valueMs) || valueMs < 0) return "-";
	return `${(valueMs / 1000).toFixed(1)}s`;
}

/** 窗口内活跃时长：相邻采样间隔求和 + 尾段时间，总量钳制到 >= 1s */
function activeDurationMs(samples: StreamSample[], now: number): number {
	if (samples.length === 0) return 0;
	if (samples.length === 1) {
		const tail = Math.max(0, now - samples[0]!.at);
		return Math.min(Math.max(tail, 250), SINGLE_SAMPLE_MS);
	}
	let duration = 0;
	for (let i = 1; i < samples.length; i++) {
		duration += Math.max(0, samples[i]!.at - samples[i - 1]!.at);
	}
	duration += Math.max(0, now - samples[samples.length - 1]!.at);
	return Math.max(duration, SINGLE_SAMPLE_MS);
}

class TpsTracker {
	/** 实时滚动窗口采样 */
	private samples: StreamSample[] = [];
	/** 最近一次 provider 请求发出时刻（before_provider_request） */
	private requestAt: number | undefined;
	/** 当前流式消息：首 token / 末 token / 首 token 对应的请求发出时刻 */
	private firstTokenAt: number | undefined;
	private lastTokenAt: number | undefined;
	private firstTokenRequestAt: number | undefined;
	/** 会话累计（来自已完成的 assistant 消息） */
	private totalTokens = 0;
	private totalDurationMs = 0;
	private totalTtftMs = 0;
	private messageCount = 0;

	onProviderRequest(): void {
		this.requestAt = Date.now();
	}

	onDelta(delta: string): void {
		const now = Date.now();
		this.prune(now);
		this.samples.push({ at: now, tokens: estimateTokens(delta) });
		if (this.firstTokenAt === undefined) {
			this.firstTokenAt = now;
			this.firstTokenRequestAt = this.requestAt;
			this.requestAt = undefined;
		}
		this.lastTokenAt = now;
	}

	onMessageEnd(outputTokens: number | undefined): void {
		const { firstTokenAt, lastTokenAt, firstTokenRequestAt } = this;
		this.firstTokenAt = undefined;
		this.lastTokenAt = undefined;
		this.firstTokenRequestAt = undefined;
		if (firstTokenAt === undefined) return; // 未流出任何 token，不累计
		const endAt = lastTokenAt ?? Date.now();
		this.totalDurationMs += Math.max(endAt - firstTokenAt, 1);
		if (firstTokenRequestAt !== undefined) {
			this.totalTtftMs += Math.max(firstTokenAt - firstTokenRequestAt, 0);
		}
		if (typeof outputTokens === "number" && outputTokens > 0) {
			this.totalTokens += outputTokens;
		}
		this.messageCount++;
	}

	clearLive(): void {
		this.samples = [];
	}

	resetSession(): void {
		this.clearLive();
		this.requestAt = undefined;
		this.firstTokenAt = undefined;
		this.lastTokenAt = undefined;
		this.firstTokenRequestAt = undefined;
		this.totalTokens = 0;
		this.totalDurationMs = 0;
		this.totalTtftMs = 0;
		this.messageCount = 0;
	}

	private prune(now: number): void {
		const cutoff = now - STREAM_WINDOW_MS;
		let drop = 0;
		while (drop < this.samples.length && this.samples[drop]!.at <= cutoff) drop++;
		if (drop > 0) this.samples.splice(0, drop);
	}

	liveTps(): string {
		const now = Date.now();
		this.prune(now);
		const samples = this.samples;
		if (samples.length === 0) return "-";
		if (now - samples[samples.length - 1]!.at > LIVE_STALE_MS) return "-";
		const total = samples.reduce((sum, sample) => sum + sample.tokens, 0);
		const seconds = activeDurationMs(samples, now) / 1000;
		if (seconds <= 0) return "-";
		return formatRate(total / seconds);
	}

	averageTps(): string {
		if (this.totalTokens <= 0 || this.totalDurationMs <= 0) return "-";
		return formatRate(this.totalTokens / (this.totalDurationMs / 1000));
	}

	averageTtft(): string {
		if (this.messageCount <= 0) return "-";
		return formatTtft(this.totalTtftMs / this.messageCount);
	}

	statusText(): string {
		return `TPS ${this.liveTps()} | AVG ${this.averageTps()} | TTFT ${this.averageTtft()}`;
	}
}

export default function (pi: ExtensionAPI) {
	const tracker = new TpsTracker();
	let setStatus: ((text: string) => void) | undefined;
	let timer: ReturnType<typeof setInterval> | undefined;

	const update = () => setStatus?.(tracker.statusText());

	// provider 请求发出（含重试；自动压缩的摘要请求也会触发，同样计入）
	pi.on("before_provider_request", () => {
		tracker.onProviderRequest();
	});

	// 流式 delta：只统计 text / thinking 增量
	pi.on("message_update", (event) => {
		const streamEvent = event.assistantMessageEvent;
		if (!streamEvent) return;
		if (streamEvent.type !== "text_delta" && streamEvent.type !== "thinking_delta") return;
		tracker.onDelta(streamEvent.delta);
		update();
	});

	// 消息完成：累计 AVG / TTFT
	pi.on("message_end", (event) => {
		if (event.message.role !== "assistant") return;
		tracker.onMessageEnd(event.message.usage?.output);
		update();
	});

	// 工具执行期间无 token 流出，清空实时采样
	pi.on("tool_execution_start", () => {
		tracker.clearLive();
		update();
	});

	pi.on("agent_settled", () => {
		tracker.clearLive();
		update();
	});

	pi.on("session_start", (_event, ctx) => {
		tracker.resetSession();
		if (ctx.mode !== "tui") return;
		const key = "tps-meter";
		setStatus = (text) => ctx.ui.setStatus(key, text);
		update();
		// 每秒刷新：让 live TPS 随 5s 窗口滑动、过期后回落到 "-"
		// （setStatus 内部自带 requestRender）
		if (!timer) {
			timer = setInterval(() => update(), 1000);
		}
	});

	pi.on("session_shutdown", (_event, ctx) => {
		if (timer) {
			clearInterval(timer);
			timer = undefined;
		}
		setStatus = undefined;
		if (ctx.hasUI) ctx.ui.setStatus("tps-meter", undefined);
	});
}
