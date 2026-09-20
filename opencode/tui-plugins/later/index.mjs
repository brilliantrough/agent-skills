// later — 延迟发送预设 prompt(挂机等实验结果;TUI 插件,opencode)
//
// 用法(在输入框里直接输入,不是 slash 命令):
//   later 5h 查看当前实验的运行结果      # 5 小时后把这句话作为用户消息发出去
//   later 5h /status                     # 内容可以任意
//   later list                           # 看排程
//   later cancel 2 | later cancel all    # 取消
//
// 原理:输入框拿到评测(prompt ref)后在 TUI 层拦 Enter —— 命中关键字就自己排程并把输入清空,
//      不产生任何模型请求(零开销);到点用 client.session.promptAsync 注入这条用户消息。
// 边界:计时器只活在当前 TUI 进程内,退出 opencode / 重开会丢未触发的排程(挂机请放 tmux)。
export default {
  id: "later",
  tui: async (api) => {
    const UNIT = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
    const jobs = new Map();
    let nextId = 1;

    const hhmm = (t) => new Date(t).toTimeString().slice(0, 5);
    const dur = (ms) => {
      if (ms < 60000) return `${Math.max(0, Math.round(ms / 1000))}s`;
      const h = Math.floor(ms / 3600000);
      const m = Math.round((ms % 3600000) / 60000);
      return h ? `${h}h${m}m` : `${m}m`;
    };
    const toast = (message, variant = "info") => api.ui.toast({ message, variant });

    function schedule(sessionID, ms, text) {
      const id = nextId++;
      const at = Date.now() + ms;
      const timer = setTimeout(() => {
        jobs.delete(id);
        api.client.session
          .promptAsync({ sessionID, parts: [{ type: "text", text }] })
          .then((res) => {
            if (res?.error) throw new Error(JSON.stringify(res.error));
          })
          .catch((e) => toast(`later #${id} 发送失败:${e?.message ?? e}`, "error"));
      }, ms);
      jobs.set(id, { id, at, text, sessionID, timer });
      return { id, at };
    }

    function cancel(id) {
      const job = jobs.get(id);
      if (!job) return false;
      clearTimeout(job.timer);
      jobs.delete(id);
      return true;
    }

    // 命中并处理 /later 关键字:返回 true 表示这条输入归插件管(不再发给模型)
    function consume(text, sessionID) {
      const add = text.match(/^\/?later\s+(\d+)([smhd])\s+([\s\S]+)$/i);
      if (add) {
        if (!sessionID) {
          toast("later:请先进入一个会话再排程(home 界面没有会话可注入)", "warning");
          return true;
        }
        const body = add[3].trim();
        const { id, at } = schedule(sessionID, Number(add[1]) * UNIT[add[2].toLowerCase()], body);
        toast(`later #${id} → ${hhmm(at)}(${add[1]}${add[2]} 后):${body}`);
        return true;
      }
      if (/^\/?later\s+list$/i.test(text)) {
        if (jobs.size === 0) toast("later:没有待发送的排程");
        else
          toast(
            [...jobs.values()]
              .sort((a, b) => a.at - b.at)
              .map((j) => `#${j.id} ${hhmm(j.at)}(${dur(j.at - Date.now())}后) ${j.text.slice(0, 40)}`)
              .join("  |  "),
          );
        return true;
      }
      const del = text.match(/^\/?later\s+cancel\s+(\d+|all)$/i);
      if (del) {
        const ids = del[1].toLowerCase() === "all" ? [...jobs.keys()] : [Number(del[1])];
        const done = ids.filter(cancel);
        toast(done.length ? `later:已取消 ${done.map((i) => `#${i}`).join(" ")}` : "later:没有匹配的排程", done.length ? "info" : "warning");
        return true;
      }
      return false;
    }

    // 拿到输入框的 ref(自己渲染宿主 Prompt,保留原有的右侧槽位)
    const refs = { session: null, home: null };
    const render = (key) => (_ctx, props) =>
      api.ui.Prompt({
        sessionID: props.session_id,
        visible: props.visible,
        disabled: props.disabled,
        onSubmit: () => props.on_submit?.(),
        ref: (r) => {
          refs[key] = r ?? null;
          props.ref?.(r);
        },
        right: props.session_id ? api.ui.Slot({ name: "session_prompt_right", session_id: props.session_id }) : undefined,
      });
    api.slots.register({ order: 1000, slots: { session_prompt: render("session"), home_prompt: render("home") } });

    const isEnter = (e) => e && !e.ctrl && !e.shift && !e.meta && !e.super && !e.hyper &&
      (e.name === "enter" || e.name === "return" || e.sequence === "\r");
    api.keymap.intercept(
      "key",
      (ctx) => {
        if (!isEnter(ctx.event)) return;
        const onSession = api.route.current?.name === "session";
        const ref = onSession ? refs.session : refs.home;
        const text = ref?.current?.input ?? "";
        if (!text || !ref?.focused) return;
        if (!consume(text, onSession ? api.route.current?.params?.sessionID : undefined)) return;
        ctx.consume({ preventDefault: true, stopPropagation: true });
        ref.reset();
      },
      { priority: 100 },
    );

    api.lifecycle.onDispose(() => {
      for (const job of jobs.values()) clearTimeout(job.timer);
      jobs.clear();
    });
  },
};
