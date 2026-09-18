import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import layout from "./atelier/extensions/index.js";
import { installComposer } from "./composer.js";
import panels from "./panels.js";
import tps from "./tps.js";

/** Agent Skills UI: one owner for composer, sidebar and footer. */
export default function (pi: ExtensionAPI) {
  installComposer(pi);
  layout(pi);
  panels(pi);
  tps(pi);
}
