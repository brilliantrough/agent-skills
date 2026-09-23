/**
 * AGENTS.md Loader Extension
 *
 * Reads AGENTS.md from ~/.agents/AGENTS.md and injects its content
 * into the system prompt on every agent turn.
 *
 * This makes pi load AGENTS.md from the custom ~/.agents/ directory
 * in addition to the built-in context file locations.
 *
 * Usage:
 * - Place AGENTS.md at ~/.agents/AGENTS.md
 * - This extension auto-discovers from ~/.pi/agent/extensions/
 * - Reload with /reload after making changes
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function getAgentsMdPath(): string {
  return path.join(os.homedir(), ".agents", "AGENTS.md");
}

function getPlatformName(): string {
  switch (os.platform()) {
    case "win32":
      return "Windows";
    case "darwin":
      return "macOS";
    case "linux":
      return "Linux";
    default:
      return os.platform();
  }
}

export default function agentsMdLoader(pi: ExtensionAPI) {
  let agentsMdContent: string | null = null;
  let agentsMdPath: string = "";

  pi.on("session_start", async (_event, ctx) => {
    agentsMdPath = getAgentsMdPath();

    try {
      agentsMdContent = fs.readFileSync(agentsMdPath, "utf-8");
    } catch {
      agentsMdContent = null;
    }
  });

  pi.on("before_agent_start", async (event) => {
    const platformName = getPlatformName();

    let extra = `\n\n## 当前操作系统\n\n当前操作系统是 ${platformName}。执行 shell 命令时必须使用该系统的命令语法以及目录结构：Windows 使用 PowerShell 命令，macOS/Linux 使用 Unix 命令。`;

    if (agentsMdContent) {
      extra += `\n\n## Additional Instructions (${agentsMdPath})\n\n${agentsMdContent}`;
    }

    return {
      systemPrompt: event.systemPrompt + extra,
    };
  });
}
