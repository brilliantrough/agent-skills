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
const first = component.render(80);
check("包装后渲染一致(未折叠)", first.length === lines.length);

check("点击表头 → 折叠", component.handleMouse({ type: "click", y: 0 })?.render === true);
check("配置已写入", readCollapsedPanels().has("TASKS"));
check("点击后重渲染变短", component.render(80).length === lines.length - 3);
check("其他键保留", JSON.parse(readFileSync(config, "utf8")).clearSelectionOnRelease === true);

check("再次点击 → 展开", component.handleMouse({ type: "click", y: 0 })?.render === true);
check("配置已清空", !readCollapsedPanels().has("TASKS") && component.render(80).length === lines.length);

check("press 被吞掉(不启动选择)", component.handleMouse({ type: "press", y: 0 })?.consume === true);
check("非表头点击忽略", component.handleMouse({ type: "click", y: 1 }) === undefined);
check("其他事件忽略", component.handleMouse({ type: "wheel", y: 0 }) === undefined);

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
