import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import {
	createPowerShellToolDefinition,
	type ExtensionAPI,
	type PowerShellOperations,
} from "@earendil-works/pi-coding-agent";

const PWSH_PATH = "C:\\Program Files\\PowerShell\\7\\pwsh.exe";
const PWSH_ARGS = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"];
const UTF8_OUTPUT_PREFIX = "try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}\n";
const MAX_TIMEOUT_MS = 2_147_483_647;

function killProcessTree(pid: number): void {
	const taskkill = spawn(
		join(process.env.SystemRoot ?? "C:\\Windows", "System32", "taskkill.exe"),
		["/F", "/T", "/PID", String(pid)],
		{ stdio: "ignore", windowsHide: true },
	);
	taskkill.once("error", () => {});
}

const operations: PowerShellOperations = {
	exec(command, cwd, { onData, signal, timeout, env }) {
		return new Promise((resolve, reject) => {
			if (signal?.aborted) {
				reject(new Error("aborted"));
				return;
			}

			let timeoutMs: number | undefined;
			if (timeout !== undefined) {
				if (!Number.isFinite(timeout) || timeout <= 0) {
					reject(new Error("Invalid timeout: must be a finite number of seconds"));
					return;
				}
				timeoutMs = timeout * 1000;
				if (timeoutMs > MAX_TIMEOUT_MS) {
					reject(new Error(`Invalid timeout: maximum is ${MAX_TIMEOUT_MS / 1000} seconds`));
					return;
				}
			}

			const child = spawn(PWSH_PATH, [...PWSH_ARGS, `${UTF8_OUTPUT_PREFIX}${command}`], {
				cwd,
				env,
				stdio: ["ignore", "pipe", "pipe"],
				windowsHide: true,
			});
			let timedOut = false;
			let settled = false;
			let timeoutHandle: ReturnType<typeof setTimeout> | undefined;

			const cleanup = () => {
				if (timeoutHandle) clearTimeout(timeoutHandle);
				if (signal) signal.removeEventListener("abort", onAbort);
			};
			const fail = (error: Error) => {
				if (settled) return;
				settled = true;
				cleanup();
				reject(error);
			};
			const onAbort = () => {
				if (child.pid) killProcessTree(child.pid);
			};

			child.stdout?.on("data", onData);
			child.stderr?.on("data", onData);
			child.once("error", fail);
			child.once("close", (exitCode) => {
				if (settled) return;
				settled = true;
				cleanup();
				if (signal?.aborted) {
					reject(new Error("aborted"));
				} else if (timedOut) {
					reject(new Error(`timeout:${timeout}`));
				} else {
					resolve({ exitCode });
				}
			});

			if (signal) signal.addEventListener("abort", onAbort, { once: true });
			if (timeoutMs !== undefined) {
				timeoutHandle = setTimeout(() => {
					timedOut = true;
					if (child.pid) killProcessTree(child.pid);
				}, timeoutMs);
			}
		});
	},
};

export default function (pi: ExtensionAPI) {
	if (process.platform !== "win32") {
		return;
	}

	if (!existsSync(PWSH_PATH)) {
		throw new Error(`Fixed PowerShell executable not found: ${PWSH_PATH}`);
	}

	pi.registerTool(createPowerShellToolDefinition(process.cwd(), { operations }));

	// getActiveTools/setActiveTools 属于 action 方法，不能在扩展加载阶段调用，
	// 需延迟到 session_start 事件中执行
	pi.on("session_start", async () => {
		const active = pi.getActiveTools();
		if (active.includes("bash")) {
			pi.setActiveTools(active.filter((name) => name !== "bash"));
		}
	});
}
