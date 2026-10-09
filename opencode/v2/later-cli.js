export default {
  id: "agent-skills.later-cli",
  setup(ctx) {
    const jobs = new Map();
    let nextId = 1;
    const toast = (message, variant = "info") => ctx.ui.toast.show({ message, variant });
    function consume(text) {
      const match = text.trim().match(/^\/?later\s+(\d+)([smhd])\s+([\s\S]+)$/i);
      if (match) {
        const route = ctx.ui.router.current();
        if (route.type !== "session") { toast("later：请先进入一个会话", "warning"); return true; }
        const ms = Number(match[1]) * { s: 1000, m: 60000, h: 3600000, d: 86400000 }[match[2].toLowerCase()];
        if (!Number.isSafeInteger(ms) || ms < 1 || ms > 2147483647) { toast("later：延迟须在 1 秒至约 24 天之间", "warning"); return true; }
        const id = nextId++, at = Date.now() + ms, prompt = match[3].trim();
        const timer = setTimeout(async () => {
          jobs.delete(id);
          try { await ctx.client.session.prompt({ sessionID: route.sessionID, text: prompt, delivery: "queue" }); }
          catch (error) { toast(`later #${id} 发送失败：${error.message}`, "error"); }
        }, ms);
        jobs.set(id, { timer, at, prompt });
        toast(`later #${id} → ${new Date(at).toLocaleTimeString()}：${prompt}`);
        return true;
      }
      if (/^\/?later\s+list$/i.test(text.trim())) {
        toast(jobs.size ? [...jobs].map(([id, j]) => `#${id} ${new Date(j.at).toLocaleTimeString()} ${j.prompt.slice(0, 60)}`).join("\n") : "later：没有待发送的排程");
        return true;
      }
      const cancel = text.trim().match(/^\/?later\s+cancel\s+(\d+|all)$/i);
      if (!cancel) return false;
      const ids = cancel[1].toLowerCase() === "all" ? [...jobs.keys()] : [Number(cancel[1])];
      for (const id of ids) { clearTimeout(jobs.get(id)?.timer); jobs.delete(id); }
      toast("later：已取消匹配的排程");
      return true;
    }
    ctx.keymap.layer(() => ({ mode: "global", priority: 100, commands: [
      { id: "agent-skills.later", title: "延迟发送 prompt", group: "later", palette: true, slash: { name: "later", arguments: true },
        run: (text) => { if (!consume(`later ${text ?? ""}`)) toast("later 5h 检查结果 / later list / later cancel all"); } },
      { bind: "enter", run: () => {
        const input = ctx.renderer.currentFocusedRenderable;
        if (typeof input?.getClipboardText !== "function" || typeof input.plainText !== "string" || !consume(input.plainText)) return false;
        input.setText("");
      } },
    ] }));
    return () => { for (const job of jobs.values()) clearTimeout(job.timer); jobs.clear(); };
  },
};
