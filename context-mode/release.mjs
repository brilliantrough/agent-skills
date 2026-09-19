#!/usr/bin/env node
// release.mjs — 把各宿主需要的那份产物打成发布包（context-mode/dist/），目标机用 releases/latest/download/ 稳定 URL 取
//
//   node release.mjs <clone 目录>              打包全部目标 + 更新 MANIFEST.json
//   node release.mjs <clone 目录> --check      只比对本地构建是否比上次打包更新（verify.mjs 用）
//   node release.mjs <clone 目录> --publish    确保包是新的，然后 gh release create
//
// 两个目标（都保持与 npm 包相同的相对布局：宿主按 dirname(import.meta.url)/../../.. 找 server.bundle.mjs 与 hooks/）：
//   pi        pi-context-mode-vendor.tar.gz        扩展 import 闭包 + server.bundle.mjs + hooks/auto-injection.mjs + skills/
//   opencode  opencode-context-mode-vendor.tar.gz  esbuild 打好的插件（依赖全内联）+ hooks 闭包 + skills/ + entry.js
//
// 资产名固定，打包可重现（tar 固定 mtime/owner 并按名排序）；包内 VENDORED.json 记录上游版本与文件哈希，
// 目标机靠比对它判断要不要替换目录。
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SELF_REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIST = path.join(SELF_REPO, "context-mode", "dist");
const REPO_URL = "https://github.com/brilliantrough/agent-skills";
const REPO_SLUG = "brilliantrough/agent-skills"; // 显式指定：gh 默认按 cwd 的 remote 解析，而 setup.sh 会在 clone 里跑
const UPSTREAM_URL = "https://github.com/mksglu/context-mode";

const [cloneArg, ...flags] = process.argv.slice(2);
const wantCheck = flags.includes("--check");
const wantPublish = flags.includes("--publish");
if (!cloneArg) {
  console.error("用法: node release.mjs <clone 目录> [--check|--publish]");
  process.exit(2);
}
const clone = path.resolve(cloneArg);
const sha = (buf) => createHash("sha256").update(buf).digest("hex").slice(0, 16);
const relify = (abs) => path.relative(clone, abs).split(path.sep).join("/");

function readJson(p, what) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    console.error(`[release] 读不了 ${what}（${p}）：${e.message}`);
    process.exit(2);
  }
}

function upstreamMeta() {
  const pkg = readJson(path.join(clone, "package.json"), "上游 package.json");
  let commit = "unknown";
  try {
    commit = execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd: clone }).toString().trim();
  } catch { /* clone 不是 git 仓库也能打包 */ }
  return { name: pkg.name, version: pkg.version, commit, license: pkg.license };
}

const upstream = upstreamMeta();

/** 从入口顺相对 import 走出的文件闭包 */
function importClosure(entry) {
  const seen = new Set();
  const queue = [path.join(clone, entry)];
  while (queue.length) {
    const full = queue.pop();
    if (seen.has(full) || !fs.existsSync(full)) continue;
    seen.add(full);
    const src = fs.readFileSync(full, "utf8");
    for (const m of src.matchAll(/(?:from|import)\s*\(?\s*["'](\.[^"']+)["']/g)) {
      const base = path.resolve(path.dirname(full), m[1]);
      for (const cand of [base, `${base}.js`, path.join(base, "index.js")]) {
        if (fs.existsSync(cand) && fs.statSync(cand).isFile()) { queue.push(cand); break; }
      }
    }
  }
  return [...seen];
}

/** clone 里存在的文件（不存在就大声失败：上游布局变了） */
function need(paths) {
  const out = [];
  for (const rel of paths) {
    const abs = path.join(clone, rel);
    if (!fs.existsSync(abs)) {
      console.error(`[release] 缺少 ${rel} —— 上游布局变了，改 release.mjs 里的文件清单`);
      process.exit(2);
    }
    out.push(abs);
  }
  return out;
}

function skillFiles() {
  const skills = path.join(clone, "skills");
  const out = [];
  for (const e of fs.readdirSync(skills, { withFileTypes: true, recursive: true })) {
    if (e.isFile()) out.push(path.join(e.parentPath ?? skills, e.name));
  }
  return out;
}

/** clone 里的文件 → Map(包内相对路径, 绝对路径) */
function collect(absFiles) {
  const m = new Map();
  for (const abs of absFiles) m.set(relify(abs), abs);
  return m;
}

/** esbuild 打包 OpenCode 插件入口（平台内联，只留原生 sqlite 外部；结果当生成内容处理） */
function bundleOpencodePlugin() {
  const esbuild = path.join(clone, "node_modules/.bin/esbuild");
  if (!fs.existsSync(esbuild)) {
    console.error(`[release] 找不到 ${path.relative(clone, esbuild)}（先 bun install）`);
    process.exit(2);
  }
  const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "cm-bundle-")), "plugin.js");
  try {
    execFileSync(esbuild, [
      "build/adapters/opencode/plugin.js",
      "--bundle", "--platform=node", "--target=node18", "--format=esm", "--minify",
      "--external:better-sqlite3", // 原生模块：OpenCode 跑在 Bun 上走 bun:sqlite，永远不加载它
      `--outfile=${out}`,
    ], { cwd: clone, stdio: "pipe" });
  } catch (e) {
    console.error(`[release] esbuild 打包 OpenCode 插件失败：${String(e.stderr ?? e.message).slice(0, 400)}`);
    process.exit(1);
  }
  const body = fs.readFileSync(out, "utf8");
  fs.rmSync(path.dirname(out), { recursive: true, force: true });
  return body;
}

/** 目标定义：files = clone 里的文件；generated = 打包时生成的内容 */
function buildTargets() {
  const vendorJson = (files, generated) => JSON.stringify({
    upstream,
    files: Object.fromEntries([...files].map(([rel, abs]) => [rel, sha(fs.readFileSync(abs))]).sort()),
    generated: Object.fromEntries([...generated].map(([rel, body]) => [rel, sha(Buffer.from(body))]).sort()),
  }, null, 2) + "\n";

  // ── Pi：扩展闭包 + MCP 子进程 + 它唯一 import 的 hook ──────────────────────
  const piEntry = "build/adapters/pi/extension.js";
  const piFiles = collect([
    ...importClosure(piEntry),
    ...need(["server.bundle.mjs", "hooks/auto-injection.mjs", "LICENSE"]),
    ...skillFiles(),
  ]);
  const piGenerated = new Map();
  piGenerated.set("package.json", JSON.stringify({
    name: "pi-context-mode-fork",
    version: upstream.version,
    private: true,
    type: "module",
    license: upstream.license,
    description: `context-mode ${upstream.version} fork: tools renamed to ctxm_* so it can coexist with pi-magic-context`,
    pi: { extensions: [`./${piEntry}`], skills: ["./skills"] },
    contextModeFork: { upstream: UPSTREAM_URL, commit: upstream.commit },
  }, null, 2) + "\n");
  piGenerated.set("VENDORED.json", vendorJson(piFiles, piGenerated));

  // ── OpenCode：esbuild 打好的插件 + 它运行期动态 import 的 hook + skills ────
  const ocEntry = "build/adapters/opencode/plugin.js";
  const ocHooks = [
    "hooks/core/routing.mjs", "hooks/core/tool-naming.mjs", "hooks/core/mcp-ready.mjs",
    "hooks/routing-block.mjs", "hooks/auto-injection.mjs", "hooks/security.bundle.mjs",
  ];
  const ocFiles = collect([...need([...ocHooks, "LICENSE"]), ...skillFiles()]);
  const ocGenerated = new Map();
  ocGenerated.set(ocEntry, bundleOpencodePlugin());
  // 入口 shim：OpenCode 只扫描 plugins/*.js 这一层，子目录不会被自动加载（实测）
  ocGenerated.set("entry.js", [
    "// OpenCode 只加载 plugins/ 这一层的文件；实际代码在 ./context-mode/ 下（保持包的相对布局）",
    `export { ContextModePlugin } from "./context-mode/${ocEntry}";`,
    "",
  ].join("\n"));
  ocGenerated.set("package.json", JSON.stringify({
    // 不给 main/exports：万一将来 OpenCode 递归扫子目录，也没有可加载的入口（我们靠 entry.js 那一层）
    name: "opencode-context-mode-fork",
    version: upstream.version,
    private: true,
    type: "module",
    license: upstream.license,
    description: `context-mode ${upstream.version} fork for OpenCode: tools renamed to ctxm_*`,
    contextModeFork: { upstream: UPSTREAM_URL, commit: upstream.commit },
  }, null, 2) + "\n");
  ocGenerated.set("VENDORED.json", vendorJson(ocFiles, ocGenerated));

  return {
    pi: { asset: "pi-context-mode-vendor.tar.gz", files: piFiles, generated: piGenerated },
    opencode: { asset: "opencode-context-mode-vendor.tar.gz", files: ocFiles, generated: ocGenerated },
  };
}

const targets = buildTargets();
const targetManifest = (t) => ({
  asset: t.asset,
  files: Object.fromEntries([...t.files].map(([rel, abs]) => [rel, sha(fs.readFileSync(abs))]).sort()),
  generated: Object.fromEntries([...t.generated].map(([rel, body]) => [rel, sha(Buffer.from(body))]).sort()),
});

// ── --check：本地构建有没有比上次打包更新（verify.mjs 调用） ────────────────
if (wantCheck) {
  const mfPath = path.join(DIST, "MANIFEST.json");
  const drift = [];
  let have = null;
  if (fs.existsSync(mfPath)) {
    try {
      have = readJson(mfPath, "MANIFEST.json");
    } catch {
      have = null; // 损坏的 MANIFEST 当作没打过包
    }
  }
  if (!have) drift.push(`没打过包（缺 ${path.relative(SELF_REPO, mfPath)}）`);
  else {
    if (have.upstream?.version !== upstream.version || have.upstream?.commit !== upstream.commit) {
      drift.push(`上游版本/提交变了：包内 ${have.upstream?.version}@${have.upstream?.commit} → 现在 ${upstream.version}@${upstream.commit}`);
    }
    for (const [name, t] of Object.entries(targets)) {
      const want = targetManifest(t);
      const got = have.assets?.[name];
      if (!got) { drift.push(`没打过 ${name} 包`); continue; }
      for (const [rel, h] of Object.entries(want.files)) {
        if (!got.files?.[rel]) drift.push(`${name} 缺: ${rel}`);
        else if (got.files[rel] !== h) drift.push(`${name} 旧: ${rel}`);
      }
      for (const rel of Object.keys(got.files ?? {})) if (!(rel in want.files)) drift.push(`${name} 多: ${rel}`);
      for (const [rel, h] of Object.entries(want.generated)) {
        if (got.generated?.[rel] !== h) drift.push(`${name} 需重新生成: ${rel}`);
      }
    }
  }
  if (drift.length) {
    console.error(`[release] 发布包与本次构建不一致（${drift.length} 项）：`);
    for (const d of drift.slice(0, 12)) console.error("  " + d);
    if (drift.length > 12) console.error(`  …还有 ${drift.length - 12} 项`);
    console.error("[release] 修：bash context-mode/setup.sh（要发到 GitHub 再加 --publish）");
    process.exit(1);
  }
  console.log(`[release] 发布包与本次构建一致（上游 ${upstream.version}@${upstream.commit}）`);
  process.exit(0);
}

// ── 打包 ────────────────────────────────────────────────────────────────────
fs.rmSync(DIST, { recursive: true, force: true });
const manifest = { upstream, assets: {} };
for (const [name, t] of Object.entries(targets)) {
  const staging = path.join(DIST, `.staging-${name}`);
  fs.mkdirSync(staging, { recursive: true });
  let raw = 0;
  for (const [rel, abs] of t.files) {
    const out = path.join(staging, rel);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.copyFileSync(abs, out);
    raw += fs.statSync(abs).size;
  }
  for (const [rel, body] of t.generated) {
    const out = path.join(staging, rel);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, body);
    raw += Buffer.byteLength(body);
  }
  const tarball = path.join(DIST, t.asset);
  // 可重现：固定 mtime/owner 并按名字排序，内容没变则产物字节一致
  execFileSync("tar", ["--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "-czf", tarball, "-C", staging, "."]);
  fs.rmSync(staging, { recursive: true, force: true });
  const bytes = fs.statSync(tarball).size;
  manifest.assets[name] = { ...targetManifest(t), bytes, sha256: createHash("sha256").update(fs.readFileSync(tarball)).digest("hex") };
  console.log(`[release] ${name.padEnd(8)} ${t.files.size + t.generated.size} 个文件 / ${(raw / 1024).toFixed(0)} KB → ${(bytes / 1024).toFixed(0)} KB 压缩`);
}
fs.writeFileSync(path.join(DIST, "MANIFEST.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`[release] 上游 ${upstream.name} ${upstream.version}@${upstream.commit}（${upstream.license}）→ ${path.relative(SELF_REPO, DIST)}/`);

if (!wantPublish) {
  console.log("[release] 发布：bash context-mode/setup.sh --publish");
  process.exit(0);
}

// ── --publish：gh release create（一个 release 带两个资产；同版本重建追加 -2/-3…） ──
const baseTag = `ctxm-${upstream.version}`;
let tag = baseTag;
for (let i = 2; i <= 9; i++) {
  try {
    execFileSync("gh", ["release", "view", tag, "--repo", REPO_SLUG], { stdio: "pipe" });
    tag = `${baseTag}-${i}`; // 已存在，换下一个后缀
  } catch {
    break; // 该 tag 不存在，可以用
  }
}
const piAsset = targets.pi.asset;
const ocAsset = targets.opencode.asset;
const notes = [
  `context-mode ${upstream.version}（上游 ${upstream.commit}）的 fork 产物，11 个工具已改名为 \`ctxm_*\`（避开与 pi-magic-context 的 \`ctx_search\` 撞名）。`,
  "",
  "**Pi**（装到本地路径包，再登记）：",
  "",
  "```bash",
  `curl -fsSL ${REPO_URL}/releases/latest/download/${piAsset} | tar -xz -C ~/.pi/agent/vendor/context-mode`,
  "pi install ~/.pi/agent/vendor/context-mode",
  "```",
  "",
  "**OpenCode**（插件目录，不写 opencode.json 的 plugin 字段）：",
  "",
  "```bash",
  `curl -fsSL ${REPO_URL}/releases/latest/download/${ocAsset} | tar -xz -C ~/.config/opencode/plugins/context-mode`,
  "cp ~/.config/opencode/plugins/context-mode/entry.js ~/.config/opencode/plugins/context-mode.js",
  "```",
  "",
  `重建方式：\`bash context-mode/setup.sh --publish\`。许可：${upstream.license}，见包内 LICENSE。`,
].join("\n");
try {
  execFileSync("gh", ["release", "create", tag, "--repo", REPO_SLUG, ...Object.values(targets).map((t) => path.join(DIST, t.asset)), "--title", `${upstream.name} fork ${upstream.version} (${upstream.commit})`, "--notes", notes], { stdio: "inherit" });
} catch (e) {
  console.error(`[release] gh release create 失败：${e.message}`);
  process.exit(1);
}
console.log(`[release] 已发布 ${tag}；稳定下载 URL：`);
for (const t of Object.values(targets)) console.log(`  ${REPO_URL}/releases/latest/download/${t.asset}`);
