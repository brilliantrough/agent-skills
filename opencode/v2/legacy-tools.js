import { existsSync } from "node:fs";
import { tool } from "@opencode-ai/plugin";
import claude from "../plugins/claude-mem-wrapper.js";
import later from "../plugins/later.js";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const config = process.env.OPENCODE_CONFIG_DIR ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "opencode");
const load = (path) => import(pathToFileURL(path).href);

export default {
  id: "agent-skills.legacy-tools",
  async setup(ctx) {
    const registrations = [];
    const sessions = new Set();
    const models = new Map();
    const client = {
      app: { log: async ({ body }) => { if (body.level === "error" || body.level === "warn") console.error(`[${body.service}] ${body.message}`); } },
      session: {
        get: async ({ path }) => ({ data: await ctx.session.get({ sessionID: path.id }) }),
        promptAsync: async ({ path, body }) => { await ctx.session.prompt({ sessionID: path.id, text: body.parts.filter((p) => p.type === "text").map((p) => p.text).join("\n"), delivery: "queue" }); return {}; },
      },
    };
    const input = { client, directory: ctx.location.directory, worktree: ctx.location.directory, project: { name: ctx.location.directory.split(/[\\/]/).filter(Boolean).at(-1) } };
    const cm = await load(join(config, "vendor/context-mode/build/adapters/opencode/plugin.js"));
    const hooks = [await cm.ContextModePlugin(input), await later(input)];
    if (existsSync(join(config, "lib/claude-mem.js"))) hooks.push(await claude(input));
    registrations.push(await ctx.tool.transform((editor) => {
      for (const h of hooks) for (const [name, def] of Object.entries(h.tool ?? {})) editor.add({
        name, description: def.description, input: tool.schema.object(def.args), options: { codemode: true, pinned: true },
        async execute(args, c) {
          const result = await def.execute(args, { sessionID: c.sessionID, messageID: c.messageID, callID: c.id, directory: ctx.location.directory, abort: c.signal, metadata: (metadata) => { void c.progress(metadata); } });
          return typeof result === "string" ? { content: result } : { content: result.output, metadata: result.metadata };
        },
      });
    }));
    registrations.push(await ctx.tool.hook("execute.before", async (e) => {
      const output = { args: e.input };
      for (const h of hooks) await h["tool.execute.before"]?.({ tool: e.tool, sessionID: e.sessionID, callID: e.id }, output);
      e.input = output.args;
    }));
    registrations.push(await ctx.tool.hook("execute.after", async (e) => {
      sessions.add(e.sessionID);
      const output = e.status === "completed" ? e.result.content : e.error.message;
      const text = typeof output === "string" ? output : (output ?? []).filter((p) => p.type === "text").map((p) => p.text).join("\n");
      for (const h of hooks) await h["tool.execute.after"]?.({ tool: e.tool, sessionID: e.sessionID, callID: e.id, args: e.input }, { args: e.input, output: text });
    }));
    registrations.push(await ctx.session.hook("prompt", async (e) => {
      sessions.add(e.sessionID);
      for (const h of hooks) await h["chat.message"]?.({ sessionID: e.sessionID }, { message: { role: "user", sessionID: e.sessionID }, parts: [{ type: "text", text: e.prompt.text ?? "" }] });
    }));
    registrations.push(await ctx.session.hook("context", async (e) => {
      sessions.add(e.sessionID);
      models.set(e.sessionID, e.model);
      const output = { system: e.system.map((p) => p.text) };
      for (const h of hooks) await h["experimental.chat.system.transform"]?.({ sessionID: e.sessionID, model: e.model }, output);
      e.system = output.system.map((text, i) => ({ ...e.system[i], type: "text", text }));
    }));
    registrations.push(await ctx.session.hook("compaction", async (e) => {
      const output = { context: [] };
      for (const h of hooks) await h["experimental.session.compacting"]?.({ sessionID: e.sessionID }, output);
      if (output.context.length) e.system.push({ type: "text", text: output.context.join("\n\n") });
    }));
    const abort = new AbortController();
    const events = (async () => {
      for await (const e of ctx.event.subscribe({ signal: abort.signal })) {
        if (!["session.execution.succeeded", "session.deleted", "session.step.ended", "session.step.failed"].includes(e.type)) continue;
        const sessionID = e.data.sessionID;
        if (!sessions.has(sessionID)) continue;
        if (e.type === "session.deleted") { sessions.delete(sessionID); models.delete(sessionID); }
        if (e.type === "session.execution.succeeded") {
          const last = (await ctx.session.context({ sessionID })).findLast((m) => m.type === "assistant");
          const text = last?.content.filter((p) => p.type === "text").map((p) => p.text).join("\n");
          if (text) for (const h of hooks) await h["experimental.text.complete"]?.({ sessionID }, { text });
        }
        const model = models.get(sessionID);
        const event = e.type.startsWith("session.step.")
          ? { type: "message.updated", properties: { info: { role: "assistant", id: e.data.assistantMessageID, sessionID,
            modelID: model?.id, providerID: model?.providerID, tokens: e.data.tokens, cost: e.data.cost } } }
          : { type: e.type === "session.deleted" ? e.type : "session.idle", properties: { sessionID, info: { id: sessionID } } };
        for (const h of hooks) await h.event?.({ event });
      }
    })().catch((error) => { if (!abort.signal.aborted) console.error("[legacy-tools] event capture failed", error); });
    return async () => { abort.abort(); await events; for (const r of registrations.reverse()) await r.dispose(); for (const h of hooks) await h.dispose?.(); };
  },
};
