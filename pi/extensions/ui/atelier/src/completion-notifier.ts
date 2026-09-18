import { spawn as nodeSpawn, type SpawnOptions } from "node:child_process";

export type CompletionNotificationKind = "turn-settled" | "input-requested";

export interface CompletionNotification {
	kind: CompletionNotificationKind;
	projectName: string;
	sessionName?: string;
	completedToolCount?: number;
	failedToolCount?: number;
}

export interface NotificationProcess {
	kill(): boolean;
	once(event: "error" | "exit", listener: (...args: unknown[]) => void): this;
	unref(): void;
}

export type SpawnNotificationProcess = (
	command: string,
	args: string[],
	options: SpawnOptions,
) => NotificationProcess;

export interface CompletionNotifierOptions {
	isEnabled(): boolean;
	platform?: NodeJS.Platform;
	spawn?: SpawnNotificationProcess;
}

export interface CompletionNotifier {
	runStarted(): void;
	inputRequested(toolCallId: string, notification: CompletionNotification): void;
	turnSettled(notification: CompletionNotification): void;
	reset(): void;
}

const PROCESS_TIMEOUT_MS = 5_000;
const APPLE_SCRIPT = [
	"on run argv",
	"display notification (item 2 of argv) with title (item 1 of argv)",
	"end run",
];
const WINDOWS_TOAST_SCRIPT = [
	"$ErrorActionPreference = 'Stop'",
	"[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null",
	"[Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null",
	"$template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02",
	"$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)",
	"$texts = $xml.GetElementsByTagName('text')",
	"$texts.Item(0).AppendChild($xml.CreateTextNode($env:PI_ATELIER_NOTIFICATION_TITLE)) > $null",
	"$texts.Item(1).AppendChild($xml.CreateTextNode($env:PI_ATELIER_NOTIFICATION_BODY)) > $null",
	"$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)",
	"[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Agent Skills UI').Show($toast)",
].join("; ");

const defaultSpawn: SpawnNotificationProcess = (command, args, options) => nodeSpawn(command, args, options);

export function createCompletionNotifier(options: CompletionNotifierOptions): CompletionNotifier {
	const platform = options.platform ?? process.platform;
	const spawn = options.spawn ?? defaultSpawn;
	let settledNotified = false;
	let inputRequests = new Set<string>();
	const pendingSystemNotifications = new Set<() => void>();

	const deliver = (notification: CompletionNotification): void => {
		if (!options.isEnabled()) return;
		const title = formatTitle(notification);
		const body = formatBody(notification);
		let cancel: (() => void) | undefined;
		cancel = deliverSystemNotification(platform, spawn, title, body, () => {
			if (cancel) pendingSystemNotifications.delete(cancel);
		});
		if (cancel) pendingSystemNotifications.add(cancel);
	};

	return {
		runStarted() {
			settledNotified = false;
			inputRequests = new Set<string>();
		},
		inputRequested(toolCallId, notification) {
			const id = sanitize(toolCallId, 160);
			if (id.length === 0 || inputRequests.has(id)) return;
			inputRequests.add(id);
			deliver({ ...notification, kind: "input-requested" });
		},
		turnSettled(notification) {
			if (settledNotified) return;
			settledNotified = true;
			deliver({ ...notification, kind: "turn-settled" });
		},
		reset() {
			settledNotified = false;
			inputRequests = new Set<string>();
			for (const cancel of pendingSystemNotifications) cancel();
			pendingSystemNotifications.clear();
		},
	};
}

export function formatTitle(notification: CompletionNotification): string {
	const project = sanitize(notification.projectName, 80);
	return project.length > 0 ? `Agent Skills UI · ${project}` : "Agent Skills UI";
}

export function formatBody(notification: CompletionNotification): string {
	const parts = [notification.kind === "input-requested" ? "Input requested" : "Turn settled"];
	const session = sanitize(notification.sessionName ?? "", 100);
	if (session.length > 0) parts.push(session);
	if (notification.kind === "turn-settled") {
		const completed = normalizeCount(notification.completedToolCount);
		const failed = normalizeCount(notification.failedToolCount);
		if (completed > 0) parts.push(`${completed} done`);
		if (failed > 0) parts.push(`${failed} failed`);
	}
	return parts.join(" · ");
}

function deliverSystemNotification(
	platform: NodeJS.Platform,
	spawn: SpawnNotificationProcess,
	title: string,
	body: string,
	onFinished: () => void,
): (() => void) | undefined {
	if (platform === "darwin") {
		return spawnDetached(
			spawn,
			"osascript",
			[...APPLE_SCRIPT.flatMap((line) => ["-e", line]), "--", title, body],
			{},
			onFinished,
		);
	}
	if (platform === "win32") {
		return spawnDetached(
			spawn,
			"powershell.exe",
			["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", WINDOWS_TOAST_SCRIPT],
			{
				env: {
					...process.env,
					PI_ATELIER_NOTIFICATION_TITLE: title,
					PI_ATELIER_NOTIFICATION_BODY: body,
				},
				windowsHide: true,
			},
			onFinished,
		);
	}
	return undefined;
}

function spawnDetached(
	spawn: SpawnNotificationProcess,
	command: string,
	args: string[],
	extra: Pick<SpawnOptions, "env" | "windowsHide"> = {},
	onFinished: () => void,
): (() => void) | undefined {
	try {
		const child = spawn(command, args, { detached: true, stdio: "ignore", ...extra });
		let timer: ReturnType<typeof setTimeout> | undefined;
		let finished = false;
		const finish = (kill: boolean) => {
			if (finished) return;
			finished = true;
			if (timer) clearTimeout(timer);
			timer = undefined;
			if (kill) {
				try {
					child.kill();
				} catch {
					// System notifications are best effort and fail silently.
				}
			}
			onFinished();
		};
		child.once("error", () => finish(false));
		child.once("exit", () => finish(false));
		child.unref();
		timer = setTimeout(() => finish(true), PROCESS_TIMEOUT_MS);
		timer.unref?.();
		return () => finish(true);
	} catch {
		// System notifications are best effort and fail silently.
		return undefined;
	}
}

function sanitize(value: string, maximumLength: number): string {
	return value
		.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
		.replace(/\s+/g, " ")
		.trim()
		.slice(0, maximumLength);
}

function normalizeCount(value: number | undefined): number {
	return Number.isFinite(value) ? Math.max(0, Math.trunc(value ?? 0)) : 0;
}
