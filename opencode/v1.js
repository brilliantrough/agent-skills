import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import claude from "./plugins/claude-mem-wrapper.js";
export { default as LaterPlugin } from "./plugins/later.js";
export { default as ContextRewritePlugin } from "./plugins/context-rewrite.js";

export const ClaudeMemPlugin = (ctx) => {
  const config = process.env.OPENCODE_CONFIG_DIR ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "opencode");
  return existsSync(join(config, "lib/claude-mem.js")) ? claude(ctx) : {};
};
