#!/usr/bin/env node
// release.mjs — 把 Pi 真正需要的那份产物打成发布包（路线 D：产物走 GitHub release，不进 git 历史）
//
//   node release.mjs <clone 目录>              打包到 context-mode/dist/pi-context-mode-vendor.tar.gz + MANIFEST.json
//   node release.mjs <clone 目录> --check      只比对：本地构建是不是比上次打包更新（verify.mjs 用）
//   node release.mjs <clone 目录> --publish    确保包是新的，然后 gh release create
//
// 包里有什么（其余一律不装）：
//   - 扩展的 import 闭包（从 build/adapters/pi/extension.js 顺着相对 import 走）
//   - server.bundle.mjs（扩展 spawn 的 MCP 子进程，按 pluginRoot 相对定位）
//   - hooks/auto-injection.mjs（扩展唯一会 import 的 hook；其它 hook 是别的宿主的）
//   - skills/（7 个 skill，改名与剪枝已生效的版本）
//   - LICENSE（Elastic-2.0，必须随产物分发）+ 生成的 package.json + VENDORED.json
// 为什么可行：扩展用 `pluginRoot = resolve(dirname(import.meta.url), "../../..")` 定位
// server.bundle.mjs 与 hooks/，所以保持包内相对布局就能整体搬走。
//
// 资产名固定为 pi-context-mode-vendor.tar.gz，这样目标机可以用稳定 URL 取最新版：
//   https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SELF_REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIST = path.join(SELF_REPO, "context-mode", "dist");
const ASSET = "pi-context-mode-vendor.tar.gz";
const ENTRY = "build/adapters/pi/extension.js";
const EXTRA = ["server.bundle.mjs", "hooks/auto-injection.mjs", "LICENSE"];
const REPO_URL = "https://github.com/brilliantrough/agent-skills";

const [cloneArg, ...flags] = process.argv.slice(2);
const wantCheck = flags.includes("--check");
const wantPublish = flags.includes("--publish");
if (!cloneArg) {
  console.error("用法: node release.mjs <clone 目录> [--check|--publish]");
  process.exit(2);
}
const clone = path.resolve(cloneArg);
const sha = (buf) => createHash("sha256").update(buf).digest("hex").slice(0, 16);

function readJson(p, what) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    console.error(`[release] 读不了 ${what}（${p}）：${e.message}`);
    process.exit(2);
  }
}

/** 从入口顺相对 import 走出的文件闭包（全在 build/ 内） */
function importClosure() {
  const seen = new Set();
  const queue = [path.join(clone, ENTRY)];
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

/** 发布包内的文件清单：相对路径 → clone 里的绝对路径 */
function packageFiles() {
  const files = new Map();
  for (const abs of importClosure()) files.set(path.relative(clone, abs).split(path.sep).join("/"), abs);
  for (const rel of EXTRA) {
    const abs = path.join(clone, rel);
    if (!fs.existsSync(abs)) {
      console.error(`[release] 缺少 ${rel} —— 上游布局变了，请检查 EXTRA 列表`);
      process.exit(2);
    }
    files.set(rel, abs);
  }
  const skills = path.join(clone, "skills");
  for (const e of fs.readdirSync(skills, { withFileTypes: true, recursive: true })) {
    if (e.isFile()) {
      const abs = path.join(e.parentPath ?? skills, e.name);
      files.set(path.relative(clone, abs).split(path.sep).join("/"), abs);
    }
  }
  return files;
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
const files = packageFiles();

/** 生成的包内 package.json：Pi 靠 pi.extensions / pi.skills 找入口 */
const innerPackage = () => JSON.stringify({
  name: "pi-context-mode-fork",
  version: upstream.version,
  private: true,
  type: "module",
  license: upstream.license,
  description: `context-mode ${upstream.version} fork: tools renamed to ctxm_* so it can coexist with pi-magic-context`,
  pi: { extensions: [`./${ENTRY}`], skills: ["./skills"] },
  contextModeFork: { upstream: REPO_URL.replace("agent-skills", "context-mode"), commit: upstream.commit },
}, null, 2) + "\n";

const generated = new Map([
  ["package.json", innerPackage()],
  ["VENDORED.json", JSON.stringify({
    upstream,
    files: Object.fromEntries([...files].map(([rel, abs]) => [rel, sha(fs.readFileSync(abs))]).sort()),
  }, null, 2) + "\n"],
]);

const manifestFor = () => ({
  upstream,
  asset: ASSET,
  files: Object.fromEntries([...files].map(([rel, abs]) => [rel, sha(fs.readFileSync(abs))]).sort()),
  generated: Object.fromEntries([...generated].map(([rel, body]) => [rel, sha(Buffer.from(body))])),
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
    const want = manifestFor();
    if (have.upstream?.version !== want.upstream.version || have.upstream?.commit !== want.upstream.commit) {
      drift.push(`上游版本/提交变了：包内 ${have.upstream?.version}@${have.upstream?.commit} → 现在 ${want.upstream.version}@${want.upstream.commit}`);
    }
    for (const [rel, h] of Object.entries(want.files)) {
      if (!have.files?.[rel]) drift.push(`缺: ${rel}`);
      else if (have.files[rel] !== h) drift.push(`旧: ${rel}`);
    }
    for (const rel of Object.keys(have.files ?? {})) if (!(rel in want.files)) drift.push(`多: ${rel}`);
    for (const [rel, h] of Object.entries(want.generated)) {
      if (have.generated?.[rel] !== h) drift.push(`需重新生成: ${rel}`);
    }
  }
  if (drift.length) {
    console.error(`[release] 发布包与本次构建不一致（${drift.length} 项）：`);
    for (const d of drift.slice(0, 12)) console.error("  " + d);
    if (drift.length > 12) console.error(`  …还有 ${drift.length - 12} 项`);
    console.error("[release] 修：bash context-mode/setup.sh --release（再 --publish 发到 GitHub）");
    process.exit(1);
  }
  console.log(`[release] 发布包与本次构建一致（上游 ${upstream.version}@${upstream.commit}）`);
  process.exit(0);
}

// ── 打包 ────────────────────────────────────────────────────────────────────
fs.rmSync(DIST, { recursive: true, force: true });
const staging = path.join(DIST, ".staging");
fs.mkdirSync(staging, { recursive: true });
let raw = 0;
for (const [rel, abs] of files) {
  const out = path.join(staging, rel);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.copyFileSync(abs, out);
  raw += fs.statSync(abs).size;
}
for (const [rel, body] of generated) {
  fs.writeFileSync(path.join(staging, rel), body);
  raw += Buffer.byteLength(body);
}
for (const rel of [".", ...fs.readdirSync(staging)]) void rel; // 保持 staging 结构清晰
const tarball = path.join(DIST, ASSET);
// 可重现：固定 mtime/owner 并按名字排序，内容没变则产物字节一致
execFileSync("tar", ["--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "-czf", tarball, "-C", staging, "."]);
fs.rmSync(staging, { recursive: true, force: true });
const manifest = { ...manifestFor(), bytes: fs.statSync(tarball).size, sha256: createHash("sha256").update(fs.readFileSync(tarball)).digest("hex") };
fs.writeFileSync(path.join(DIST, "MANIFEST.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`[release] ${files.size + generated.size} 个文件 / ${(raw / 1024).toFixed(0)} KB → ${(manifest.bytes / 1024).toFixed(0)} KB 压缩`);
console.log(`[release] ${path.relative(SELF_REPO, tarball)}（上游 ${upstream.version}@${upstream.commit}, ${upstream.license}）`);

if (!wantPublish) {
  console.log(`[release] 发布：bash context-mode/setup.sh --publish（或 node release.mjs <clone> --publish）`);
  process.exit(0);
}

// ── --publish：gh release create（同版本重建就追加 -2/-3…） ─────────────────
const baseTag = `ctxm-${upstream.version}`;
let tag = baseTag;
for (let i = 2; i <= 9; i++) {
  try {
    execFileSync("gh", ["release", "view", tag], { stdio: "pipe" });
    tag = `${baseTag}-${i}`; // 已存在，换下一个后缀
  } catch {
    break; // 该 tag 不存在，可以用
  }
}
const notes = [
  `context-mode ${upstream.version}（上游 ${upstream.commit}）的 fork 产物，工具名已改为 \`ctxm_*\`，可与 pi-magic-context 共存。`,
  "",
  "目标机安装（无需 bun / 无需 clone）：",
  "",
  "```bash",
  `curl -fsSL ${REPO_URL}/releases/latest/download/${ASSET} | tar -xz -C ~/.pi/agent/vendor/context-mode`,
  "pi install ~/.pi/agent/vendor/context-mode",
  "```",
  "",
  `重建方式：\`bash context-mode/setup.sh --release --publish\`（三层改动见仓库 context-mode/）。许可：${upstream.license}，见包内 LICENSE。`,
].join("\n");
try {
  execFileSync("gh", ["release", "create", tag, tarball, "--title", `${upstream.name} fork ${upstream.version} (${upstream.commit})`, "--notes", notes], { stdio: "inherit" });
} catch (e) {
  console.error(`[release] gh release create 失败：${e.message}`);
  process.exit(1);
}
console.log(`[release] 已发布 ${tag}；目标机稳定下载 URL：`);
console.log(`  ${REPO_URL}/releases/latest/download/${ASSET}`);
