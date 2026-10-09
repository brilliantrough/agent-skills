import { fileURLToPath } from "node:url";
import ponytail from "./ponytail.js";
import legacy from "./legacy-tools.js";
import affinity from "./request-affinity.js";
import context from "./context-rewrite.js";

export default {
  id: "agent-skills",
  async setup(ctx) {
    const cleanups = [];
    const cleanup = async () => { for (const stop of cleanups.reverse()) await stop?.(); };
    try {
      cleanups.push(await ponytail.setup({ ...ctx, options: { packagePath: ctx.options.ponytailPackage ?? fileURLToPath(new URL("./ponytail/", import.meta.url)) } }));
      for (const plugin of [legacy, affinity, context]) cleanups.push(await plugin.setup(ctx));
      return cleanup;
    } catch (error) { await cleanup(); throw error; }
  },
};
