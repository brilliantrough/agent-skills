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
for (const major of [2]) {
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
  const install = ["v2"];
  await bundle("opencode/v2/index.js", "v2/index.js");
  await bundle("opencode/v2/later-cli.js", "v2/later-cli.js");
  for (const file of ["package.json", "tui.js", "README.md"]) copy(`opencode/v2/${file}`, `v2/${file}`);
  const docs = "v2";
  for (const file of ["README.md", "ACP-KERNEL-LICENSE"]) copy(`context-rewrite/${file}`, `${docs}/${file === 'README.md' && major === 2 ? 'CONTEXT.md' : file}`);
  copy("opencode/node_modules/zod/LICENSE", `${docs}/ZOD-LICENSE`);
  copy("opencode/OPENCODE-LICENSE", `${docs}/OPENCODE-LICENSE`);
  copy("opencode/deploy.py", "deploy.py");
  const config = await Bun.build({ entrypoints: [join(root, "opencode/migrate-config.mjs")], target: "bun", minify: true, metafile: true });
  if (!config.success) throw new AggregateError(config.logs, "配置迁移器构建失败");
  await Bun.write(join(stage, "migrate-config.mjs"), config.outputs[0]);
  copy("opencode/OPENCODE-LICENSE", "config-licenses/OPENCODE-LICENSE");
  const dependencies = new Set(Object.keys(config.metafile.inputs).flatMap(path => {
    const match = path.replaceAll("\\", "/").match(/^(.*node_modules\/((?:@[^/]+\/)?[^/]+))\//);
    return match ? [match[1]] : [];
  }));
  for (const path of dependencies) {
    for (const file of readdirSync(resolve(path)).filter(name => /^(licen[sc]e|notice)(\.|$)/i.test(name))) {
      copy(join(path, file), `config-licenses/${path.split("node_modules/").at(-1).replaceAll("/", "-")}-${file}`);
    }
  }
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
  execFileSync("gh", ["release", "create", tag, "--verify-tag", "--repo", repo, "--latest=false", "--title", `OpenCode 插件 ${version}（V2）`,
    "--notes", "仅支持 OpenCode V2；配置先由官方 2.2.3 归一化器在本机转换并备份，再更新原生模板。迁移器随包提供，无需目标机安装 npm 依赖。不启动宿主、不迁移数据库；context-mode 独立发布。", ...assets], { stdio: "inherit" });
}
