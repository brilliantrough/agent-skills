import { createRequire } from "node:module";
import { join } from "node:path";
import { homedir } from "node:os";
import { pathToFileURL } from "node:url";

export default {
  id: "agent-skills.ponytail",
  async setup(ctx) {
    const root = ctx.options.packagePath;
    if (typeof root !== "string") throw new Error("ponytail packagePath 必须指向已安装包");
    const require = createRequire(join(root, "package.json"));
    const { getPonytailInstructions } = require("./hooks/ponytail-instructions");
    const { getDefaultMode, normalizePersistedMode } = require("./hooks/ponytail-config");
    const fs = await import("node:fs");
    const state = join(process.env.OPENCODE_CONFIG_DIR ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "opencode"), ".ponytail-active");
    const readMode = () => fs.existsSync(state) ? normalizePersistedMode(fs.readFileSync(state, "utf8").trim()) || getDefaultMode() : getDefaultMode();
    const registrations = [];
    registrations.push(await ctx.session.hook("context", (e) => {
      const mode = readMode();
      if (mode !== "off") e.system.push({ type: "text", text: getPonytailInstructions(mode) });
    }));
    const { default: legacy } = await import(pathToFileURL(join(root, ".opencode/plugins/ponytail.mjs")).href);
    const hooks = await legacy();
    const config = {};
    await hooks.config(config);
    registrations.push(await ctx.command.transform((editor) => {
      for (const [name, command] of Object.entries(config.command)) editor.add({ name, description: command.description,
        async execute(e) {
          const args = e.prompt.text.replace(new RegExp(`^/?${name}\\s*`), "");
          if (name === "ponytail") {
            const mode = args.trim() ? normalizePersistedMode(args.trim()) : getDefaultMode();
            if (!mode) throw new Error("ponytail 模式：lite / full / ultra / off");
            fs.writeFileSync(state, mode);
          }
          await ctx.session.prompt({ sessionID: e.sessionID, ...e.prompt, text: command.template.replace(/\$ARGUMENTS/g, args), delivery: e.delivery });
        },
      });
    }));
    return async () => { for (const r of registrations.reverse()) await r.dispose(); };
  },
};
