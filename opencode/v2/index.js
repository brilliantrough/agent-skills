import legacy from "./legacy-tools.js";
import affinity from "./request-affinity.js";
import context from "./context-rewrite.js";

export default {
  id: "agent-skills",
  async setup(ctx) {
    const cleanups = [];
    const cleanup = async () => { for (const stop of cleanups.reverse()) await stop?.(); };
    try {
      for (const plugin of [legacy, affinity, context]) cleanups.push(await plugin.setup(ctx));
      return cleanup;
    } catch (error) { await cleanup(); throw error; }
  },
};
