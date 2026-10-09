export default {
  id: "agent-skills.request-affinity",
  async setup(ctx) {
    const models = new Map();
    const keyFor = (e, headers = {}) => (process.env.OPENCODE_PROMPT_CACHE_KEY || process.env.OPENCODE_STICKY_SESSION_ID || headers["x-session-id"] || headers.conversation_id || headers.session_id || e.sessionID).trim();
    const registrations = [await ctx.model.transform((editor) => {
      models.clear();
      for (const model of editor.list()) {
        const provider = editor.provider.get(model.providerID)?.provider;
        if (!/openai|open-responses/.test(model.package ?? provider?.package ?? "")) continue;
        models.set(`${model.providerID}/${model.id}`, model.headers ?? {});
        editor.update(model.providerID, model.id, (m) => { m.compatibility = { ...m.compatibility, supportsPromptCacheKey: true }; });
      }
    })];
    registrations.push(await ctx.session.hook("context", (e) => {
      const headers = models.get(`${e.model.providerID}/${e.model.id}`);
      if (headers) e.options.promptCacheKey = keyFor(e, headers);
    }));
    registrations.push(await ctx.session.hook("model.request", (e) => {
      if (!models.has(`${e.model.providerID}/${e.model.id}`)) return;
      const value = keyFor(e, e.headers);
      Object.assign(e.headers, { "x-session-id": value, conversation_id: value, session_id: value });
    }));
    return async () => { for (const r of registrations.reverse()) await r.dispose(); };
  },
};
