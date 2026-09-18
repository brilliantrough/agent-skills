import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import layout from "./atelier/extensions/index.js";
import { installComposer } from "./composer.js";
import panels from "./panels.js";
import tps from "./tps.js";

/** Agent Skills UI: one owner for composer, sidebar and footer. */
/**
 * Agent Skills UI: one owner for composer, sidebar and footer.
 *
 * Magic Context 的 historian/dreamer 是 `pi` 子进程（带 MAGIC_CONTEXT_PI_SUBAGENT=1），
 * 默认也会加载本扩展。子进程里没有可交互 UI，加载它只会浪费启动时间，而且一旦
 * 这里抛错（曾发生：相对 import 写错 → 子进程 exit 1）就会连带把 historian 拖挂。
 */
export default function (pi: ExtensionAPI) {
  if (process.env.MAGIC_CONTEXT_PI_SUBAGENT === "1") return;
  installComposer(pi);
  layout(pi);
  panels(pi);
  tps(pi);
}
