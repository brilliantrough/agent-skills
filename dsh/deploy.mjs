import { cp, mkdir, readFile, writeFile, lstat, readlink, rename, symlink, glob } from "node:fs/promises";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { spawnSync } from "node:child_process";
import { isDeepStrictEqual } from "node:util";
import { parseArgs } from "node:util";

const sensitive = /(api[_-]?key|secret|token|password|passwd|credential|bearer|auth|cookie|ingest|webhook|base[_-]?url|url|endpoint|host|(^|[._-])key$)/i;
const placeholder = (v) => typeof v === "string" && /^<[^>]+>$/.test(v);
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
export function merge(local, template, key = "") {
  if (local !== undefined && (key === "disabled" || sensitive.test(key) || placeholder(template))) return local;
  if (object(local) && object(template)) {
    return Object.fromEntries([...new Set([...Object.keys(local), ...Object.keys(template)])]
      .map((k) => [k, k in template ? merge(local[k], template[k], k) : local[k]]));
  }
  if (Array.isArray(local) && Array.isArray(template) && ["packages", "customSkillDirs"].includes(key)) {
    return [...new Set([...local, ...template])];
  }
  if (Array.isArray(local) && Array.isArray(template) && template.every((v) => object(v) && typeof v.id === "string")) {
    return [...local.map((item) => {
      const replacement = template.find((v) => v.id === item.id);
      return replacement ? merge(item, replacement) : item;
    }), ...template.filter((v) => !local.some((item) => item.id === v.id))];
  }
  return template;
}

export async function writeChanged(path, value, { mode = 0o600, backup = true } = {}) {
  let previous;
  try {
    if ((await lstat(path)).isSymbolicLink()) throw new Error(`不覆盖符号链接：${path}`);
    previous = await readFile(path, "utf8");
  } catch (error) { if (error.code !== "ENOENT") throw error; }
  if (previous === value) return false;
  await mkdir(dirname(path), { recursive: true });
  if (previous !== undefined && backup) {
    const stamp = new Date().toISOString().replaceAll(/\D/g, "").slice(0, 14);
    await writeFile(`${path}.bak-${stamp}`, previous, { mode, flag: "wx" });
  }
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, value, { mode });
  await rename(temporary, path);
  return true;
}
const json = async (path, fallback) => {
  try { return JSON.parse(await readFile(path, "utf8")); }
  catch (error) { if (error.code === "ENOENT" && fallback !== undefined) return fallback; throw error; }
};
const quote = (s) => "'" + s.replaceAll("'", "'\\''") + "'";
function run(command, args, env) {
  const result = spawnSync(command, args, { stdio: "inherit", env });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} 退出码 ${result.status}`);
}

export async function deploy({ root, source, template: templatePath, contextMode, magicContext, claudeMem }) {
  root = resolve(root); source = resolve(source);
  const runtime = join(root, "runtime"), bundle = join(runtime, "bundle");
  const home = process.env.DSH_HOME ?? join(root, "home");
  for (const profile of ["headless", "web", "tui"]) {
    const directory = join(home, "profiles", profile), modules = join(directory, "node_modules");
    if (existsSync(modules) && (!(await lstat(modules)).isSymbolicLink() || resolve(directory, await readlink(modules)) !== join(runtime, "node_modules"))) {
      throw new Error(`profile 已有独立依赖目录，保留原样：${modules}`);
    }
  }
  await mkdir(bundle, { recursive: true });
  const copyOptions = { recursive: true, filter: async (src, dest) => {
    if (src.split(/[\\/]/).some((part) => ["node_modules", ".git"].includes(part))) return false;
    if ((await lstat(src)).isDirectory()) return true;
    return !existsSync(dest) || !(await readFile(src)).equals(await readFile(dest));
  } };
  for (const dir of ["dsh", "context-rewrite", "image-gen"]) {
    await cp(join(source, dir), join(bundle, dir), copyOptions);
  }
  if (contextMode) await cp(contextMode, join(runtime, "vendor/context-mode"), {
    ...copyOptions, filter: async (src, dest) => (await lstat(src)).isDirectory() || !existsSync(dest) || !(await readFile(src)).equals(await readFile(dest)),
  });
  const magic = join(runtime, "vendor/magic-context");
  if (magicContext) await cp(magicContext, magic, copyOptions);
  if (!existsSync(join(magic, "package.json"))) throw new Error("缺少 Magic Context 源码包，未修改启动入口");
  await writeChanged(join(bundle, "dsh/pi/package.json"), JSON.stringify({
    name: "agent-skills-dsh-pi-extensions", private: true, pi: { extensions: ["./later.ts", "./image-gen.ts"] },
  }, null, 2) + "\n");
  await writeChanged(join(bundle, "dsh/pi/later.ts"), await readFile(join(source, "pi/extensions/later.ts"), "utf8"));
  await writeChanged(join(bundle, "dsh/pi/image-gen.ts"), await readFile(join(source, "pi/extensions/image-gen.ts"), "utf8"));
  const manifest = await json(join(source, "dsh/runtime.package.json"));
  manifest.dependencies.yaml = "2.8.1";
  manifest.dependencies["acp-kernel"] = "0.0.101";
  manifest.dependencies["agent-skills-dsh"] = "file:./bundle/dsh";
  if (claudeMem) manifest.dependencies["@claude-mem/dsh"] = "file:" + resolve(claudeMem);
  const changed = await writeChanged(join(runtime, "package.json"), JSON.stringify(manifest, null, 2) + "\n");
  const env = { ...process.env, PATH: dirname(process.execPath) + ":" + process.env.PATH };
  if (changed || !existsSync(join(runtime, "node_modules/@deepseek-ai/dsh/lib/bin.js"))) {
    run(join(dirname(process.execPath), "npm"), ["install", "--prefix", runtime, "--no-audit", "--no-fund", "--fetch-retries=1"], env);
  }
  const runtimeRequire = createRequire(join(runtime, "package.json"));
  const hash = createHash("sha256");
  const files = await Array.fromAsync(glob(["src/**/*.ts", "src/client/*.js", "tsconfig*.json", "scripts/copy-client.mjs"], { cwd: magic }));
  for (const file of files.sort()) hash.update(file).update(await readFile(join(magic, file)));
  hash.update((await json(join(runtime, "node_modules/typescript/package.json"))).version);
  const digest = hash.digest("hex"), stamp = join(magic, ".agent-skills-build");
  if (!existsSync(join(magic, "lib/index.js")) || !existsSync(stamp) || await readFile(stamp, "utf8") !== digest) {
    run(process.execPath, [join(runtime, "node_modules/typescript/bin/tsc"), "-p", join(magic, "tsconfig.build.json")], env);
    run(process.execPath, [join(magic, "scripts/copy-client.mjs")], env);
    await writeChanged(stamp, digest, { backup: false });
  }
  const transport = runtimeRequire.resolve("@deepseek-ai/dsh-llm-deepseek");
  const parser = await readFile(transport, "utf8");
  const original = 'if (started) return malformed("duplicate message_start");';
  const compatible = 'if (started) {\n\t\t\t\tif (blocks.size === 0 && reason === void 0) continue;\n\t\t\t\treturn malformed("duplicate message_start");\n\t\t\t}';
  if (!parser.includes(compatible)) {
    if (parser.split(original).length !== 2) throw new Error("llm-deepseek 解析器已变化，未应用兼容补丁");
    await writeChanged(transport, parser.replace(original, compatible));
  }
  const YAML = runtimeRequire("yaml");
  function parseYaml(raw, path) {
    const doc = YAML.parseDocument(raw);
    if (doc.errors.length || doc.warnings.length) throw new Error(`配置含无效 YAML 或自定义标签，未覆盖：${path}`);
    return doc.toJS();
  }
  const pi = await json(join(homedir(), ".pi/agent/models.json"), { providers: {} });
  const piAuth = await json(join(homedir(), ".pi/agent/auth.json"), {});
  const savedPatchPath = join(home, "profiles/headless/cordis.patch.yml");
  const savedPatch = existsSync(savedPatchPath) ? parseYaml(await readFile(savedPatchPath, "utf8"), savedPatchPath) : [];
  if (!Array.isArray(savedPatch)) throw new Error(`补丁必须是列表：${savedPatchPath}`);
  const savedProviders = savedPatch.find((r) => r.id === "llm-pi-ai")?.config?.providers ?? {};
  const refs = {};
  const template = await json(templatePath);
  template.push({ id: "magic-context-dsh", config: { registerCompactionEngine: false, memory: {}, dataDir: join(home, "magic-context") } });
  if (claudeMem) {
    const dataDir = process.env.CLAUDE_MEM_DATA_DIR ?? join(homedir(), ".claude-mem");
    const settingsDocument = await json(join(dataDir, "settings.json"), {});
    const settings = settingsDocument.env ?? settingsDocument;
    const expand = (path) => path.startsWith("~/") ? join(homedir(), path.slice(2)) : path;
    const watchPath = expand(process.env.CLAUDE_MEM_TRANSCRIPTS_CONFIG_PATH ?? settings.CLAUDE_MEM_TRANSCRIPTS_CONFIG_PATH ?? join(dataDir, "transcript-watch.json"));
    const watch = await json(watchPath, { version: 1, schemas: {}, watches: [], stateFile: join(dataDir, "transcript-watch-state.json") });
    if (watch.version !== 1 || !Array.isArray(watch.watches)) throw new Error(`无效 transcript watch 配置，未覆盖：${watchPath}`);
    if (!watch.watches.some((entry) => entry.schema === "dsh")) {
      if (watch.watches.some((entry) => entry.name === "dsh")) throw new Error("已有其它 dsh watch，保留配置并停止");
      watch.schemas ??= {};
      watch.schemas.dsh ??= await json(join(claudeMem, "transcript-schema.json"));
      watch.watches.push({ name: "dsh", path: join(home, "sessions"), schema: "dsh", startAtEnd: true, managedBy: "claude-mem" });
      await writeChanged(watchPath, JSON.stringify(watch, null, 2) + "\n");
      process.stdout.write("claude-mem：已登记 DSH transcript watch，worker 下次启动生效。\n");
    }
  }
  if (contextMode) template.push({ id: "mcp-context-mode", disabled: false, config: {
    serverName: "context_mode", transport: "stdio", command: process.execPath,
    args: [join(runtime, "vendor/context-mode/server.bundle.mjs")], env: { CONTEXT_MODE_PLATFORM: "pi" },
    failOnStartupError: true,
  } }, { id: "skill-filesystem", config: { customSkillDirs: [join(runtime, "vendor/context-mode/skills")] } });
  const providers = template.find((r) => r.id === "llm-pi-ai").config.providers;
  for (const [route, config] of Object.entries(providers)) {
    const local = pi.providers?.[route];
    const saved = savedProviders[route];
    if (saved?.apiKeyEnv) config.apiKeyEnv = saved.apiKeyEnv;
    const address = saved?.baseURL ?? process.env[route.toUpperCase().replaceAll("-", "_") + "_BASE_URL"] ?? local?.baseUrl;
    if (address && !placeholder(address)) config.baseURL = address;
    const key = process.env[config.apiKeyEnv] ?? local?.apiKey ?? (piAuth[route]?.type === "api_key" ? piAuth[route].key : undefined);
    if (key && !placeholder(key)) refs[config.apiKeyEnv] = key;
  }
  const deepseek = template.find((r) => r.id === "llm-deepseek").config;
  deepseek.baseURL = providers["anthropic-newapi"].baseURL;
  for (const config of Object.values(providers)) {
    if (config.baseURL === undefined) continue;
    if (placeholder(config.baseURL)) throw new Error(`缺少 ${config.apiKeyEnv.replace(/_API_KEY$/, "_BASE_URL")}；先配置网关地址再重跑`);
    if (!URL.canParse(config.baseURL)) throw new Error(`无效网关地址：${config.apiKeyEnv} 对应的 baseURL`);
  }
  const credentialPath = join(home, ".credentials.yaml");
  let credentials = {};
  if (existsSync(credentialPath)) credentials = parseYaml(await readFile(credentialPath, "utf8"), credentialPath) ?? {};
  credentials.version ??= 1;
  credentials.refs = { ...refs, ...credentials.refs };
  await writeChanged(credentialPath, YAML.stringify(credentials));

  for (const profile of ["headless", "web", "tui"]) {
    const directory = join(home, "profiles", profile);
    await mkdir(directory, { recursive: true });
    const webBundle = profile === "web" ? "@deepseek-ai/dsh-web-app" : `@deepseek-ai/dsh-${profile}`;
    const packages = ["@deepseek-ai/dsh-base", ...(profile === "tui" ? ["@xmoon76/dsh-pi-tui"] : [webBundle]), "pi2dsh", "agent-skills-dsh", "dsh-plugin-magic-context"];
    if (claudeMem) packages.push("@claude-mem/dsh");
    const packagePath = join(directory, "package.json");
    const prior = await json(packagePath, { private: true });
    prior.dsh ??= {}; prior.dsh.profile ??= {};
    prior.dsh.profile.bundles = [...new Set([...(prior.dsh.profile.bundles ?? []), ...packages])];
    await writeChanged(packagePath, JSON.stringify(prior, null, 2) + "\n");
    if (!existsSync(join(directory, "cordis.yml"))) await writeChanged(join(directory, "cordis.yml"), "[]\n");
    const modules = join(directory, "node_modules"), target = join(runtime, "node_modules");
    if (!existsSync(modules)) await symlink(target, modules, "junction");
    else if (!(await lstat(modules)).isSymbolicLink() || resolve(directory, await readlink(modules)) !== target) {
      throw new Error(`profile 已有独立依赖目录，保留原样：${modules}`);
    }
    const patchPath = join(directory, "cordis.patch.yml");
    const original = existsSync(patchPath) ? await readFile(patchPath, "utf8") : "[]\n";
    const current = parseYaml(original, patchPath) ?? [];
    if (!Array.isArray(current)) throw new Error(`补丁必须是列表：${patchPath}`);
    const additions = [...template, { id: "pi2dsh", config: { packages: [join(bundle, "dsh/pi"), "@dietrichgebert/ponytail"], visionCompanions: false } }];
    const result = merge(current, additions);
    if (!isDeepStrictEqual(current, result)) await writeChanged(patchPath, YAML.stringify(result));
  }
  const launcher = join(root, "dsh");
  const node = process.execPath, entry = join(runtime, "node_modules/@deepseek-ai/dsh/lib/bin.js");
  await writeChanged(launcher, `#!/bin/sh\n# agent-skills managed dsh launcher\nif [ -z "\${DSH_HOME:-}" ]; then export DSH_HOME=${quote(home)}; fi\nexport PATH=${quote(dirname(node))}:"$PATH"\nif [ "$#" -eq 0 ]; then set -- tui; fi\nexec ${quote(node)} ${quote(entry)} "$@"\n`, { mode: 0o755 });
  process.stdout.write(`DSH 已配置：${launcher}；数据目录 ${home}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { root: { type: "string" }, source: { type: "string" }, template: { type: "string" }, contextMode: { type: "string" }, magicContext: { type: "string" }, claudeMem: { type: "string" }, yes: { type: "boolean" } } });
  for (const key of ["root", "source", "template"]) if (!values[key]) throw new Error(`缺少 --${key}`);
  await deploy(values);
}
