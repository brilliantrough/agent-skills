#!/usr/bin/env bun
// bun opencode/release.mjs [--publish]；先 npm ci --prefix opencode && npm ci --prefix context-rewrite。
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
import pkg from "./package.json" with { type: "json" };
const version = pkg.version;
const tag = `opencode-plugins-${version}`;
const repo = "brilliantrough/agent-skills";
const dist = join(root, "opencode/dist");
if (!readFileSync(join(root, "opencode-setup.sh"), "utf8").includes(`OC_RELEASE="${tag}"`)) throw new Error("setup 中的 OC_RELEASE 须与 opencode/package.json 版本一致");
mkdirSync(dist, { recursive: true });
const assets = [];
for (const major of [1, 2]) {
  const stage = join(dist, `stage-v${major}`);
  rmSync(stage, { recursive: true, force: true });
  mkdirSync(stage, { recursive: true });
  const copy = (src, dest = src) => {
    mkdirSync(dirname(join(stage, dest)), { recursive: true });
    cpSync(join(root, src), join(stage, dest), { recursive: true });
  };
  async function bundle(entry, destination) {
    const result = await Bun.build({ entrypoints: [join(root, entry)], target: "bun", minify: true });
    if (!result.success) throw new AggregateError(result.logs, `构建失败：${entry}`);
    mkdirSync(dirname(join(stage, destination)), { recursive: true });
    await Bun.write(join(stage, destination), result.outputs[0]);
  }
  const install = major === 1 ? ["plugins/zz-agent-skills.js", "tui-plugins/later", "context-rewrite"] : ["v2"];
  if (major === 1) {
    await bundle("opencode/v1.js", "plugins/zz-agent-skills.js");
    copy("opencode/tui-plugins/later", "tui-plugins/later");
  } else {
    await bundle("opencode/v2/index.js", "v2/index.js");
    await bundle("opencode/v2/later-cli.js", "v2/later-cli.js");
    for (const file of ["package.json", "tui.js", "README.md"]) copy(`opencode/v2/${file}`, `v2/${file}`);
    const pony = "opencode/node_modules/@dietrichgebert/ponytail";
    for (const file of ["hooks", "skills", ".opencode", "LICENSE", "package.json"]) copy(`${pony}/${file}`, `v2/ponytail/${file}`);
  }
  const docs = major === 1 ? "context-rewrite" : "v2";
  for (const file of ["README.md", "ACP-KERNEL-LICENSE"]) copy(`context-rewrite/${file}`, `${docs}/${file === 'README.md' && major === 2 ? 'CONTEXT.md' : file}`);
  copy("opencode/node_modules/zod/LICENSE", `${docs}/ZOD-LICENSE`);
  copy("opencode/OPENCODE-LICENSE", `${docs}/OPENCODE-LICENSE`);
  copy("opencode/deploy.py", "deploy.py");
  const files = {};
  function walk(dir) {
    for (const e of readdirSync(join(stage, dir), { withFileTypes: true })) {
      const relative = dir ? `${dir}/${e.name}` : e.name;
      if (e.isDirectory()) walk(relative);
      else files[relative] = createHash("sha256").update(readFileSync(join(stage, relative))).digest("hex");
    }
  }
  walk("");
  writeFileSync(join(stage, "MANIFEST.json"), JSON.stringify({ version, major, install, files }, null, 2) + "\n");
  const asset = join(dist, `opencode-plugins-v${major}.tar.gz`);
  execFileSync("tar", ["--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "-czf", asset, "-C", stage, "."]);
  assets.push(asset);
  console.log(`built: ${asset}`);
}
if (process.argv.includes("--publish")) {
  execFileSync("gh", ["release", "create", tag, "--verify-tag", "--repo", repo, "--latest=false", "--title", `OpenCode 插件 ${version}（v1 / v2）`,
    "--notes", "opencode-setup.sh 按已安装客户端主版本选择预构建包；不升级宿主，不迁移数据库。context-mode 继续独立发布。使用 acp-kernel 0.0.101；许可证与出处见包内 README 和 ACP-KERNEL-LICENSE。", ...assets], { stdio: "inherit" });
}
