#!/usr/bin/env node
// 将官方 release-out 中本套件实际使用的自包含产物打成两个兼容资产。
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SELF_REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIST = path.join(SELF_REPO, "context-mode", "dist");
const REPO_URL = "https://github.com/brilliantrough/agent-skills";
const REPO_SLUG = "brilliantrough/agent-skills";
const UPSTREAM_URL = "https://github.com/mksglu/context-mode";
const [cloneArg, ...flags] = process.argv.slice(2);
const wantCheck = flags.includes("--check");
const wantPublish = flags.includes("--publish");
if (!cloneArg) {
  console.error("用法: node release.mjs <上游源码目录> [--check|--publish]");
  process.exit(2);
}
const clone = path.resolve(cloneArg);
const sha = (buffer) => createHash("sha256").update(buffer).digest("hex").slice(0, 16);
function readJson(file, what) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); }
  catch (error) { console.error(`[release] 读不了 ${what}（${file}）：${error.message}`); process.exit(2); }
}
function upstreamMeta() {
  const pkg = readJson(path.join(clone, "package.json"), "上游 package.json");
  let commit = `v${pkg.version}`;
  if (fs.existsSync(path.join(clone, ".git"))) {
    try { commit = execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd: clone, stdio: ["ignore", "pipe", "ignore"] }).toString().trim(); } catch { /* 保留 tag */ }
  }
  return { name: pkg.name, version: pkg.version, commit, license: pkg.license };
}
const upstream = upstreamMeta();
function need(rel) {
  const abs = path.join(clone, rel);
  if (!fs.existsSync(abs)) {
    console.error(`[release] 缺少 ${rel}；上游布局变化，停止打包`);
    process.exit(2);
  }
  return abs;
}
function targetManifest(target) {
  return {
    asset: target.asset,
    files: Object.fromEntries([...target.files].map(([rel, abs]) => [rel, sha(fs.readFileSync(abs))]).sort()),
    generated: Object.fromEntries([...target.generated].map(([rel, body]) => [rel, sha(Buffer.from(body))]).sort()),
  };
}
function buildTargets() {
  const files = new Map();
  for (const rel of ["pi/index.js", "opencode/plugin.js", "server.mjs", "cli.mjs", "LICENSE"]) files.set(rel, need(`release-out/${rel}`));
  for (const skill of ["ctx-stats", "ctx-doctor"]) files.set(`skills/${skill}/SKILL.md`, need(`release-out/pi/skills/${skill}/SKILL.md`));
  files.set("skills/context-mode/SKILL.md", path.join(SELF_REPO, "context-mode/guidance.md"));

  const packageJson = JSON.stringify({
    name: "agent-skills-context-mode",
    version: upstream.version,
    private: true,
    type: "module",
    engines: { node: ">=24.15.0" },
    license: upstream.license,
    description: `context-mode ${upstream.version} fork: ctxm_* tools and one automatic output-snapshot owner`,
    main: "./opencode/plugin.js",
    exports: { ".": "./opencode/plugin.js", "./server": "./opencode/plugin.js" },
    pi: { extensions: ["./pi/index.js"], skills: ["./skills"] },
    contextModeFork: { upstream: UPSTREAM_URL, commit: upstream.commit, outputOwner: "agent-skills/context-rewrite" },
  }, null, 2) + "\n";
  const readme = `# agent-skills context-mode fork\n\nUpstream: ${UPSTREAM_URL} ${upstream.commit} (${upstream.license}).\n\n- Nine tools are named \`ctxm_*\` to coexist with Magic Context.\n- The main host uses agent-skills' lossless context-output snapshots; context-mode's automatic result replacement and upstream routing denials are disabled there. Pi subagents keep upstream protection.\n- Pi loads \`pi/index.js\`; OpenCode calls the native v2 \`setup(ctx)\` in \`opencode/plugin.js\`; DSH runs \`server.mjs --agent opencode\`.\n- Requires Node >=24.15 when the host runs it under Node.\n- Do not call \`ctxm_upgrade\`; use the suite's build/release path.\n`;
  const generated = new Map([["package.json", packageJson], ["README.md", readme]]);
  const vendored = JSON.stringify({
    upstream,
    fork: { toolPrefix: "ctxm_", outputOwner: "agent-skills/context-rewrite" },
    files: Object.fromEntries([...files].map(([rel, abs]) => [rel, sha(fs.readFileSync(abs))]).sort()),
    generated: Object.fromEntries([...generated].map(([rel, body]) => [rel, sha(Buffer.from(body))]).sort()),
  }, null, 2) + "\n";
  generated.set("VENDORED.json", vendored);
  return {
    pi: { asset: "pi-context-mode-vendor.tar.gz", files, generated },
    opencode: { asset: "opencode-context-mode-vendor.tar.gz", files, generated },
  };
}
const targets = buildTargets();

if (wantCheck) {
  const manifestPath = path.join(DIST, "MANIFEST.json");
  const drift = [];
  const previous = fs.existsSync(manifestPath) ? readJson(manifestPath, "MANIFEST.json") : null;
  if (!previous) drift.push("尚未打包");
  else {
    if (previous.upstream?.version !== upstream.version || previous.upstream?.commit !== upstream.commit) drift.push("上游版本或提交变化");
    for (const [name, target] of Object.entries(targets)) {
      const wanted = targetManifest(target), actual = previous.assets?.[name];
      if (!actual) { drift.push(`缺少 ${name}`); continue; }
      for (const [rel, hash] of Object.entries(wanted.files)) if (actual.files?.[rel] !== hash) drift.push(`${name}:${rel}`);
      for (const rel of Object.keys(actual.files ?? {})) if (!(rel in wanted.files)) drift.push(`${name} 多余文件:${rel}`);
      for (const [rel, hash] of Object.entries(wanted.generated)) if (actual.generated?.[rel] !== hash) drift.push(`${name}:${rel} 需重新生成`);
    }
  }
  if (drift.length) {
    console.error(`[release] 发布包与本次构建不一致（${drift.length} 项）：\n${drift.slice(0, 12).map((d) => `  ${d}`).join("\n")}`);
    process.exit(1);
  }
  console.log(`[release] 发布包与本次构建一致（${upstream.version}@${upstream.commit}）`);
  process.exit(0);
}

fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });
const manifest = { upstream, assets: {} };
for (const [name, target] of Object.entries(targets)) {
  const staging = path.join(DIST, `.staging-${name}`);
  fs.mkdirSync(staging, { recursive: true });
  let raw = 0;
  for (const [rel, abs] of target.files) {
    const out = path.join(staging, rel);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.copyFileSync(abs, out);
    raw += fs.statSync(abs).size;
  }
  for (const [rel, body] of target.generated) {
    const out = path.join(staging, rel);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, body);
    raw += Buffer.byteLength(body);
  }
  const tarball = path.join(DIST, target.asset);
  execFileSync("tar", ["--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "-czf", tarball, "-C", staging, "."]);
  fs.rmSync(staging, { recursive: true, force: true });
  const bytes = fs.statSync(tarball).size;
  manifest.assets[name] = { ...targetManifest(target), bytes, sha256: createHash("sha256").update(fs.readFileSync(tarball)).digest("hex") };
  console.log(`[release] ${name.padEnd(8)} ${target.files.size + target.generated.size} 个文件 / ${(raw / 1024).toFixed(0)} KB → ${(bytes / 1024).toFixed(0)} KB 压缩`);
}
fs.writeFileSync(path.join(DIST, "MANIFEST.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`[release] 上游 ${upstream.name} ${upstream.version}@${upstream.commit}（${upstream.license}）`);

if (!wantPublish) {
  console.log("[release] 仅构建候选包；发布需 bash context-mode/setup.sh --publish");
  process.exit(0);
}

const baseTag = `ctxm-${upstream.version}`;
let tag = baseTag;
for (let i = 2; i <= 99; i++) {
  try { execFileSync("gh", ["release", "view", tag, "--repo", REPO_SLUG], { stdio: "pipe" }); tag = `${baseTag}-${i}`; }
  catch { break; }
}
const notes = [
  `context-mode ${upstream.version}（${upstream.commit}）fork：9 个 \`ctxm_*\` 工具，主宿主自动外置由 agent-skills 无损 snapshot 统一负责。需要 Node >=24.15。`,
  "",
  "Pi：通过 `pi-setup.sh` 安装；OpenCode v2：通过 `opencode-setup.sh --plugins-only` 安装；DSH：通过 `dsh-setup.sh` 安装。",
  "",
  `重建：\`bash context-mode/setup.sh --publish\`。许可：${upstream.license}，见包内 LICENSE。`,
].join("\n");
try {
  execFileSync("gh", ["release", "create", tag, "--repo", REPO_SLUG, ...Object.values(targets).map((target) => path.join(DIST, target.asset)), "--title", `${upstream.name} fork ${upstream.version} (${upstream.commit})`, "--notes", notes], { stdio: "inherit" });
} catch (error) {
  console.error(`[release] gh release create 失败：${error.message}`);
  process.exit(1);
}
console.log(`[release] 已发布 ${tag}`);
for (const target of Object.values(targets)) console.log(`  ${REPO_URL}/releases/latest/download/${target.asset}`);
