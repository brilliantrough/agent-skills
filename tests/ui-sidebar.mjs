#!/usr/bin/env node
// 检查侧栏两个新功能:面板点击折叠/展开(sidebar-collapse.ts)与插件列表(panels.ts installedPackages)。
// 需要 --experimental-strip-types(Node 22.23 自带类型剥离)。
// 模块是 TS 且 import 了 Pi 运行时包(仓库里没有 node_modules),所以这里做最小改写后再加载:
// 把 getAgentDir() 换成 $AGENT_DIR,既不改源文件,也不装依赖。
import { readFileSync, writeFileSync, mkdtempSync, rmSync, readdirSync, existsSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const dir = mkdtempSync(join(tmpdir(), "ui-test-"));
process.env.AGENT_DIR = dir;

function load(rel) {
  const source = readFileSync(join(root, rel), "utf8")
    .replace(/^import \{[^}]*\} from "@earendil-works\/pi-coding-agent";$/gm, "")
    // 同级 atelier 模块(只有注册函数):给个空实现,避免临时目录里解析相对路径
    .replace(/^import \{ registerSidebarPanel \} from "[^"]*";$/gm, "const registerSidebarPanel = () => ({ update() {}, dispose() {} });")
    .replace(/^import \{ aggregateMetrics, formatTokens \} from "[^"]*";$/gm, "const aggregateMetrics = () => ({}), formatTokens = () => \"\";")
    .replace(/getAgentDir\(\)/g, "process.env.AGENT_DIR");
  const file = join(dir, rel.split("/").pop().replace(/\.ts$/, "") + ".ts");
  writeFileSync(file, source);
  return import(`file://${file}`);
}

const C = "\u001b[36m";
const R = "\u001b[0m";
const panel = (title, body) => [
  `${C}╭─ ${C}${title}${R} ${C}${"─".repeat(20)}╮${R}`,
  ...body.map((line) => `│ ${line} │`),
  `╰${"─".repeat(26)}╯`,
  "",
];
const lines = [...panel("✦ TASKS · 1/2", ["▶ do a thing"]), ...panel("✦ TOOLS", ["bash 3", "read 2"])];
const config = join(dir, "agent-skills-ui.json");
writeFileSync(config, JSON.stringify({ clearSelectionOnRelease: true }, null, 2));

const { shapeLines, panelBlocks, withCollapsiblePanels, readCollapsedPanels } = await load("pi/extensions/ui/sidebar-collapse.ts");

// pi-tui 只接受 handled/capture/focus 之一，否则整条派发结果会被丢弃(曾因此完全点不动)。
let dispatchMouseEvent = null;
try {
  const mod = await import("@earendil-works/pi-tui");
  dispatchMouseEvent = mod.dispatchMouseEvent ?? null;
  if (!dispatchMouseEvent) {
    // 包入口没再导出它，按包目录直接取 dist/tui.js
    const { createRequire } = await import("node:module");
    const { pathToFileURL } = await import("node:url");
    const { dirname, join: j } = await import("node:path");
    const pkg = createRequire(import.meta.url).resolve("@earendil-works/pi-tui/package.json");
    dispatchMouseEvent = (await import(pathToFileURL(j(dirname(pkg), "dist/tui.js")).href)).dispatchMouseEvent;
  }
} catch { /* 仓库无 node_modules 软链时跳过(pi-setup.sh 第 9 步会补) */ }
const evt = (type, y) => ({ type, y, x: 0, screenX: 0, screenY: y, width: 40, height: 12, button: 0, shift: false });
let failures = 0;
const check = (name, ok, detail = "") => {
  console.log(`${ok ? "  ok  " : "  FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures += 1;
};

const blocks = panelBlocks(lines);
check("识别 2 个面板块", blocks.length === 2, JSON.stringify(blocks.map((b) => b.key)));

// 回归:相对 import 必须能解析到真实文件(否则 Pi 加载扩展即崩,如 ../../../sidebar-collapse.js)
{
  const bad = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.name.endsWith(".ts")) {
        for (const [, rel] of readFileSync(path, "utf8").matchAll(/from "(\.[^"]+)"/g)) {
          const target = join(dir, rel);
          if (![target, target.replace(/\.js$/, ".ts"), `${target}.ts`].some((c) => existsSync(c)))
            bad.push(`${path.slice(root.length + 1)} -> ${rel}`);
        }
      }
    }
  };
  walk(join(root, "pi/extensions/ui"));
  check("ui 树相对 import 全部可解析", bad.length === 0, bad.join("; "));
}
check("键取标题首词", blocks[0]?.key === "TASKS" && blocks[1]?.key === "TOOLS");

const expanded = shapeLines(lines, new Set());
check("默认不折叠", expanded.lines.length === lines.length && expanded.panelRows.size === 2);

const collapsed = shapeLines(lines, new Set(["TASKS"]));
check("折叠后行数减少", collapsed.lines.length === lines.length - 3, `${collapsed.lines.length} vs ${lines.length}`);
check("折叠行有 ▸ 标记", collapsed.lines[0].includes("▸") && collapsed.lines[0].includes("TASKS"));
check("另一块保留正文", collapsed.lines.some((line) => line.includes("bash 3")));
check("折叠块不再是表头行", collapsed.panelRows.get(0) === "TASKS");

const inner = { render: () => lines, invalidate() {} };
const component = withCollapsiblePanels(inner);
const first = component.render(80);check("包装后渲染一致(未折叠)", first.length === lines.length);

check("点击表头 → 折叠", component.handleMouse({ type: "click", y: 0 })?.render === true);
check("配置已写入", readCollapsedPanels().has("TASKS"));
check("点击后重渲染变短", component.render(80).length === lines.length - 3);
check("其他键保留", JSON.parse(readFileSync(config, "utf8")).clearSelectionOnRelease === true);

check("再次点击 → 展开", component.handleMouse({ type: "click", y: 0 })?.render === true);
check("配置已清空", !readCollapsedPanels().has("TASKS") && component.render(80).length === lines.length);

check("press 被吞掉(不启动选择)", component.handleMouse({ type: "press", y: 0 })?.handled === true);
check("非表头点击忽略", component.handleMouse({ type: "click", y: 1 }) === undefined);
check("其他事件忽略", component.handleMouse({ type: "wheel", y: 0 }) === undefined);

// TOOLS 的 `n / m active ▸` 行：点它应触发上游的 tool list 开关，而不是整块折叠。
const toolLines = [...panel("✦ TOOLS", ["39 / 45 active  ▸"]), ...panel("✦ PLUGINS · 8", ["pi-lens 4.2.1"])];
let toggled = 0;
const toolComponent = withCollapsiblePanels({ render: () => toolLines, invalidate() {} }, {
  onToggleToolNames: () => { toggled += 1; },
});
toolComponent.render(80);
check("识别 disclosure 行", shapeLines(toolLines, new Set()).disclosureRows.has(1));
check("click 触发 tool list 开关", toolComponent.handleMouse({ type: "click", y: 1 })?.render === true && toggled === 1);
check("press 被吞掉", toolComponent.handleMouse({ type: "press", y: 1 })?.handled === true);
check("disclosure 不写成折叠状态", !readCollapsedPanels().has("TOOLS"));
check("普通正文行不是 disclosure", !shapeLines(toolLines, new Set()).disclosureRows.has(2));

if (dispatchMouseEvent) {
  const fresh = withCollapsiblePanels({ render: () => lines, invalidate() {} });
  fresh.render(80);
  const press = dispatchMouseEvent(fresh, evt("press", 0));
  check("真实派发:press 被接受(handled)", press?.handled === true);
  check("真实派发:press 记住目标", press?.target?.component === fresh);
  check("单击表头 → 折叠状态写入", dispatchMouseEvent(fresh, evt("click", 0))?.handled === true && readCollapsedPanels().has("TASKS"));
  const body = dispatchMouseEvent(fresh, evt("click", 2));
  check("真实派发:正文行不拦截(仍可选中文本)", body === undefined);
} else {
  console.log("(跳过 pi-tui 真实派发检查:未解析到 @earendil-works/pi-tui;跑 pi-setup.sh 第 9 步可补齐软链)");
}

// 真实环境:插件列表能不能读出来(用真实 agent 目录)
const { installedPackages } = await load("pi/extensions/ui/panels.ts");
const testDir = process.env.AGENT_DIR;
process.env.AGENT_DIR = join(homedir(), ".pi/agent");
const packages = installedPackages();
check("插件列表非空", packages.length > 0, `${packages.length} 个`);
check("每项都有名字和版本", packages.every((p) => p.name && p.version), JSON.stringify(packages.slice(0, 3)));
check("含本仓库包", packages.some((p) => p.name === "agent-skills"), JSON.stringify(packages.map((p) => `${p.name} ${p.version}`)));
process.env.AGENT_DIR = testDir;
console.log(`\n插件列表实测(真实 ~/.pi/agent): ${packages.map((p) => `${p.name} ${p.version}`).join(" · ")}`);

rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\nFAIL: ${failures} 项未通过` : "\nPASS: 侧栏折叠 + 插件列表");
process.exit(failures ? 1 : 0);
