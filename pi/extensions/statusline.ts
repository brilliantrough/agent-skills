// statusline — Pi 状态栏:git 分支(+ 脏标记)。
// 模型/thinking/上下文占比 Pi 原生 footer 已有(显示在底行右侧),这里只补原生没有的。
// 作为 agent-skills Pi 包(pi.extensions)自动加载;不注册工具,只写 ui.setStatus。
import { execFile } from "node:child_process";

function gitInfo(cwd: string): Promise<string | null> {
  return new Promise((resolve) => {
    execFile("git", ["status", "--porcelain=v1", "--branch"], { cwd, timeout: 2000 }, (error, stdout) => {
      if (error) return resolve(null);
      const lines = String(stdout).split("\n");
      const branch = (lines[0] ?? "").replace(/^##\s*/, "").split("...")[0].trim();
      if (!branch) return resolve(null);
      const dirty = lines.slice(1).some((line) => line.trim() !== "");
      resolve(`${branch}${dirty ? "*" : ""}`);
    });
  });
}

export default function (pi: any) {
  const KEY = "git";

  async function render(ctx: any) {
    if (!ctx.hasUI || !ctx.ui?.setStatus) return;
    const branch = await gitInfo(ctx.cwd);
    ctx.ui.setStatus(KEY, branch ? `⎇ ${branch}` : undefined);
  }

  pi.on("session_start", (_event: any, ctx: any) => render(ctx));
  pi.on("turn_end", (_event: any, ctx: any) => render(ctx));
  pi.on("session_shutdown", (_event: any, ctx: any) => ctx.ui?.setStatus?.(KEY, undefined));
}
