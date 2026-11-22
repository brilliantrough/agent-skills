import { access, chmod, constants, cp, mkdir, mkdtemp, readdir, readFile, writeFile, lstat, readlink, rename, stat, symlink, glob, rm } from "node:fs/promises";
import { createHash } from "node:crypto";
import { fileURLToPath, pathToFileURL } from "node:url";
import { existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
import { homedir } from "node:os";
import { spawnSync } from "node:child_process";
import { isDeepStrictEqual } from "node:util";
import { parseArgs } from "node:util";

const sensitive = /(api[_-]?key|secret|token|password|passwd|credential|bearer|auth|cookie|ingest|webhook|base[_-]?url|url|endpoint|host|(^|[._-])key$)/i;
// 报错只描述形状，不回显可能含密钥的字符串／数组／对象；数字、布尔、null 等标量无泄露风险，可带原值。
// 宿主对新旧两代 group 插件名都识别（dsh-app-boot 的列表检查包含两者）。
// 只有命名 Group 才是容器；`group: true` 单独出现不算（宿主按 name 决定载体）。
// 因此具名 provider 即使误写 group: true，也仍按 provider 处理并验收。
const GROUP_NAMES = new Set(["cordis:group", "@deepseek-ai/cordis-plugin-group"]);
const isGroup = (row) => typeof row?.name === "string" && GROUP_NAMES.has(row.name);
const describeValue = (v) => {
  if (v === undefined) return "缺失";
  if (v === null) return "为 null";
  if (typeof v === "number" || typeof v === "boolean") return `为 ${JSON.stringify(v)}，不是对象`;
  if (typeof v === "string") return "为字符串，不是对象";
  if (Array.isArray(v)) return `为数组（长度 ${v.length}），不是对象`;
  return `为 ${typeof v}，不是对象`;
};
const placeholder = (v) => typeof v === "string" && /^<[^>]+>$/.test(v.trim());
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
// !!js 表达式节点是用户显式写的值，和敏感值一样不能被模板替换。
const jsExpr = (v) => object(v) && typeof v["__jsExpr"] === "string";
const profiles = ["headless", "web", "tui"];
const requiredRoutes = new Set(["claude-newapi", "codex-newapi", "anthropic-newapi", "google", "llm-deepseek"]);
const refName = /^[A-Za-z_][A-Za-z0-9_]*$/;
// 数字、空串与占位符都不是可用凭据。
const usable = (value) => typeof value === "string" && value.trim() !== "" && !placeholder(value);
const parserOriginal = 'if (started) return malformed("duplicate message_start");';
const parserCompatible = 'if (started) {\n\t\t\t\tif (blocks.size === 0 && reason === void 0) continue;\n\t\t\t\treturn malformed("duplicate message_start");\n\t\t\t}';
export function merge(local, template, key = "") {
  // A numeric model output budget is not a credential despite the token key match.
  if (key === "maxTokens" && typeof local === "number" && typeof template === "number") return template;
  // 敏感叶子沿用本机值，但"null／空／纯空白／占位符"不是可用的本机值：让模板（或 env 已注入的模板值）补齐。
  // 非敏感键与 placeholder(template) 的旧规则保持不变。
  const staleSensitive = local !== undefined && sensitive.test(key) && key !== "disabled" &&
    (local === null || (typeof local === "string" && (local.trim() === "" || placeholder(local))));
  if (local !== undefined && !staleSensitive && (key === "disabled" || jsExpr(local) || sensitive.test(key) || placeholder(template))) return local;
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

export function migrateGeminiProvider(providers) {
  if (!object(providers)) return;
  const legacy = providers["gemini-newapi"];
  if (legacy !== undefined) {
    if (providers.google !== undefined) {
      throw new Error("同时存在 gemini-newapi 与 google；为避免跨网关拼接凭据，请先手工合并");
    }
    providers.google = legacy;
    delete providers["gemini-newapi"];
  }
  // rc.2 的 google 目录路由必须继承目录 api，显式 api 会让整个 llm-pi-ai 校验失败。
  if (object(providers.google)) delete providers.google.api;
}

const uniqueSuffix = () => `${Date.now()}-${process.pid}-${Math.random().toString(36).slice(2, 8)}`;
const warn = (message) => process.stderr.write(`WARN ${message}\n`);

// 只读目录里的文件删除会 EACCES；先放开权限再删，仍失败就留下明确的 WARN，不让垃圾掩盖真正的恢复结果。
// 只改目录权限：删文件要的是父目录写权限，文件本身的模式（尤其可执行位）保持原样。
async function chmodDirs(path, mode = 0o755) {
  const stats = await lstat(path).catch(() => undefined);
  if (!stats) return;
  if (!stats.isDirectory()) return;
  await chmod(path, mode).catch(() => {});
  for (const name of await readdir(path).catch(() => [])) await chmodDirs(join(path, name), mode);
}
async function forceRemove(path, label = path) {
  let last;
  for (const mode of [undefined, 0o755]) {
    try {
      if (mode !== undefined) await chmodDirs(path, mode);
      await rm(path, { recursive: true, force: true });
      return true;
    } catch (error) { last = error; }
  }
  warn(`无法清理 ${label}（${last?.code ?? "未知原因"}），请手动删除`);
  return false;
}

export async function writeChanged(path, value, { mode = 0o600, backup = true } = {}) {
  let previous;
  try { previous = await readFile(path, "utf8"); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  if (previous === value) return false;
  // 内容要变时不覆盖符号链接：链接目标可能不属于本安装。未变化的链接保持原样。
  if ((await lstat(path).catch(() => undefined))?.isSymbolicLink()) throw new Error(`不覆盖符号链接：${path}`);
  await mkdir(dirname(path), { recursive: true });
  // 备份与临时文件都用唯一名：同名冲突会在写入阶段变成晚失败。
  const unique = uniqueSuffix();
  if (previous !== undefined && backup) {
    await writeFile(`${path}.bak-${unique}`, previous, { mode, flag: "wx" });
  }
  const temporary = `${path}.tmp-${unique}`;
  await writeFile(temporary, value, { mode, flag: "wx" });
  await rename(temporary, path);
  return true;
}
// 两阶段写盘：先在目标同目录落好最终内容与备份（真实创建即可写性证明），提交阶段只做 rename。
// 任何一步失败都能用备份还原，不留下半套配置。
// ownerOnly 只用于凭据：宿主用 stat 跟随链接后要求无 group/other 位（dsh-credentials-local assertOwnerOnly）。
async function prepareWrite(path, value, { mode, backup = true, ownerOnly = false } = {}) {
  let previous;
  try { previous = await readFile(path, "utf8"); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const existing = await stat(path).catch((error) => { if (error.code === "ENOENT") return undefined; throw error; });
  const tooOpen = ownerOnly && existing && process.platform !== "win32" && (existing.mode & 0o077) !== 0;
  // 内容不变就什么都不写，此时过宽的权限会原样留给宿主：必须在这里拒绝，
  // 不能让部署"成功"却留下宿主启动即失败的凭据文件。
  if (previous === value) {
    if (tooOpen) throw new Error(`${path} 权限过宽（mode ${(existing.mode & 0o777).toString(8)}）；请先 chmod 600 ${path}`);
    return undefined;
  }
  // 内容要改写时顺带把权限收紧到 0600，重写本身就修好了它。
  if ((await lstat(path).catch(() => undefined))?.isSymbolicLink()) throw new Error(`不覆盖符号链接：${path}`);
  // 普通配置沿用原文件权限；回滚才能把 0644 原样换回来。新建的默认 0600。
  const targetMode = mode ?? (existing ? existing.mode & 0o777 : 0o600);
  await mkdir(dirname(path), { recursive: true });
  const unique = uniqueSuffix();
  const temporary = `${path}.tmp-${unique}`;
  let backupPath;
  // 所有权分三档：
  //   created[]   —— writeFile 成功返回，一定是本次的；
  //   attempted   —— 正在写的路径。非 EEXIST 失败会留下半截文件（本次产生），要清；
  //   EEXIST      —— 文件是别人先建的同名文件，绝不能删。
  const created = [];
  let attempted;
  const cleanupCreated = async () => {
    for (const file of created.reverse()) await rm(file, { force: true });
    created.length = 0;
  };
  const attempt = async (file, content) => {
    attempted = file;
    await writeFile(file, content, { mode: targetMode, flag: "wx" });
    created.push(file);
    await chmod(file, targetMode);
    attempted = undefined;
  };
  try {
    // writeFile 的 mode 会被 umask 削掉 077，必须显式 chmod 才能拿到 0644／0755。
    await attempt(temporary, value);
    if (previous !== undefined && backup) {
      backupPath = `${path}.bak-${unique}`;
      await attempt(backupPath, previous);
    }
    return { path, temporary, backupPath, hadPrevious: previous !== undefined, mode: targetMode };
  } catch (error) {
    await cleanupCreated();
    // 半截文件：只清 attempted 这个本次写了一半的路径，EEXIST 的文件不在此列。
    if (attempted !== undefined && error?.code !== "EEXIST") await rm(attempted, { force: true });
    throw error;
  }
}const commitWrite = (prepared) => rename(prepared.temporary, prepared.path);
async function undoWrite(prepared) {
  if (prepared.hadPrevious) await rename(prepared.backupPath, prepared.path);
  else await rm(prepared.path, { force: true });
}
async function discardWrite(prepared) {
  await rm(prepared.temporary, { force: true });
  if (prepared.backupPath) await rm(prepared.backupPath, { force: true });
}

const json = async (path, fallback) => {
  let raw;
  try { raw = await readFile(path, "utf8"); }
  catch (error) { if (error.code === "ENOENT" && fallback !== undefined) return fallback; throw error; }
  // parser 消息可能带源片段；只报文件与失败类别。
  try { return JSON.parse(raw); }
  catch { throw new Error(`JSON 配置无法解析（源内容已隐藏）：${path}`); }
};
const quote = (s) => "'" + s.replaceAll("'", "'\\''") + "'";
function run(command, args, env) {
  const result = spawnSync(command, args, { stdio: "inherit", env });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} 退出码 ${result.status}`);
}
// 与宿主同一个判据：Node URL 可解析且为 http(s)，端口越界也让 Node 自己拒绝。
function assertBaseUrl(value, label) {
  let url;
  // 不回显原值：URL 的 query 常带 token。
  try { url = new URL(value); } catch { throw new Error(`${label} 的 baseURL 不是合法 URL（位置：${label}，类型：${typeof value}）`); }
  if (url.protocol !== "http:" && url.protocol !== "https:") throw new Error(`${label} 的 baseURL 必须是 http(s)`);
}
// 宿主 schema／表达式／解析器的错误消息和路径都可能带 config 字面量（含密钥），只保留调用位置。
const safeReason = (_error, label) => `${label}（详细值与路径已隐藏）`;
async function notSymlink(path) {
  try { if ((await lstat(path)).isSymbolicLink()) throw new Error(`不覆盖符号链接：${path}`); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
}
// 受管目录必须是暂存区／runtime 内的实体目录：任何一级是链接都算越界。
async function assertInside(root, path, label) {
  const relative = path.slice(root.length);
  if (!path.startsWith(root + sep)) throw new Error(`${label} 越出受管目录：${path}`);
  let current = root;
  for (const part of relative.split(sep).filter(Boolean)) {
    current = join(current, part);
    const stats = await lstat(current).catch((error) => { if (error.code === "ENOENT") return undefined; throw error; });
    if (!stats) return;
    if (stats.isSymbolicLink()) throw new Error(`${label} 经过符号链接：${current}`);
  }
}
// 宿主逐行应用补丁；同 id 多行可能并存，迁移与校验都要覆盖每一行。
function migrateEveryProvider(patch, path) {
  for (const row of patch) {
    if (row?.id !== "llm-pi-ai") continue;
    try { migrateGeminiProvider(row.config?.providers); }
    catch (error) {
      // 迁移只抛固定的"双键冲突"结论，不含配置值；其它异常统一隐藏。
      if (typeof error?.message === "string" && error.message.startsWith("同时存在 gemini-newapi")) throw error;
      throw new Error(safeReason(error, `${path}：Gemini 路由迁移失败`));
    }
  }
}

export async function deploy({ root, source, template: templatePath, contextMode, magicContext, claudeMem }) {
  root = resolve(root); source = resolve(source);
  const runtime = join(root, "runtime");
  const home = process.env.DSH_HOME ?? join(root, "home");
  for (const profile of profiles) {
    const directory = join(home, "profiles", profile), modules = join(directory, "node_modules");
    const modulesStat = await lstat(modules).catch((error) => { if (error.code !== "ENOENT") throw error; });
    if (modulesStat && (!modulesStat.isSymbolicLink() || resolve(directory, await readlink(modules)) !== join(runtime, "node_modules"))) {
      throw new Error(`profile 已有独立依赖目录，保留原样：${modules}`);
    }
  }
  await notSymlink(runtime);
  await mkdir(root, { recursive: true });
  // 运行资产先落在 root 内的暂存目录；三个 profile 全部校验通过后才提交到 runtime。
  const stage = await mkdtemp(join(root, ".deploy-"));
  const node = process.execPath, npm = join(dirname(node), "npm");
  const env = { ...process.env, PATH: dirname(node) + ":" + process.env.PATH };
  try {
    const stageRuntime = join(stage, "runtime"), stageBundle = join(stageRuntime, "bundle");
    const stageMagic = join(stageRuntime, "vendor/magic-context");
    const copyOptions = { recursive: true, filter: async (src) => !src.split(/[\\/]/).some((part) => ["node_modules", ".git"].includes(part)) };
    // 暂存整树替换会退役已删除的 output-store；历史 context-output 文件不在 runtime 内，保持不动。
    for (const dir of ["dsh", "context-rewrite", "image-gen"]) await cp(join(source, dir), join(stageBundle, dir), copyOptions);
    await writeChanged(join(stageBundle, "dsh/pi/package.json"), JSON.stringify({
      name: "agent-skills-dsh-pi-extensions", private: true, pi: { extensions: ["./later.ts", "./image-gen.ts"] },
    }, null, 2) + "\n");
    await writeChanged(join(stageBundle, "dsh/pi/later.ts"), await readFile(join(source, "pi/extensions/later.ts"), "utf8"));
    await writeChanged(join(stageBundle, "dsh/pi/image-gen.ts"), await readFile(join(source, "pi/extensions/image-gen.ts"), "utf8"));
    const manifest = await json(join(source, "dsh/runtime.package.json"));
    manifest.dependencies.yaml = "2.8.1";
    manifest.dependencies["acp-kernel"] = "0.0.101";
    manifest.dependencies["agent-skills-dsh"] = "file:./bundle/dsh";
    if (claudeMem) manifest.dependencies["@claude-mem/dsh"] = "file:" + resolve(claudeMem);
    const manifestText = JSON.stringify(manifest, null, 2) + "\n";
    await writeChanged(join(stageRuntime, "package.json"), manifestText);
    if (contextMode) await cp(contextMode, join(stageRuntime, "vendor/context-mode"), copyOptions);
    await cp(magicContext, stageMagic, copyOptions);
    if (!existsSync(join(stageMagic, "package.json"))) throw new Error("缺少 Magic Context 源码包，未修改启动入口");
    const depsChanged = !existsSync(join(runtime, "package.json"))
      || await readFile(join(runtime, "package.json"), "utf8") !== manifestText
      || !existsSync(join(runtime, "node_modules/@deepseek-ai/dsh/lib/bin.js"));
    if (depsChanged) {
      run(npm, ["install", "--prefix", stageRuntime, "--no-audit", "--no-fund", "--fetch-retries=1"], env);
    } else {
      // 依赖不变时只读复用现有 node_modules；暂存树不是正式 runtime，不会写穿。
      await symlink(join(runtime, "node_modules"), join(stageRuntime, "node_modules"), "junction");
    }
    // 外部 file: 依赖：npm 按**暂存位置**写相对链接，所以合成与校验阶段必须保持这种可解析形态，
    // 否则 stage 里 resolve 不到包、bundle 被跳过，交换后又突然出现，startedBundles／disabled 全变。
    // 重定位到"最终 runtime 位置"的写法只在提交前做（见下方 relink 段）。
    const externalLinks = [];
    for (const [name, spec] of Object.entries(manifest.dependencies ?? {})) {
      if (typeof spec !== "string" || !spec.startsWith("file:")) continue;
      const target = resolve(runtime, spec.slice("file:".length));
      // 自身 bundle（file:./bundle/dsh）就该相对 runtime，交换后本来就不会失效。
      if (!target.startsWith(runtime + sep)) externalLinks.push([name, target]);
    }
    // 暂存阶段的判定标准是"现在能解析"：depsChanged 时 npm 已按 stage 位置写好相对链接。
    // 依赖不变时 node_modules 就是共享的最终目录，留到提交前按最终位置验证。
    if (depsChanged) {
      for (const [name] of externalLinks) {
        try { createRequire(join(stageRuntime, "package.json")).resolve(name); }
        catch {
          throw new Error(`外部依赖 ${name} 在暂存 runtime 里不可解析（${join(stageRuntime, "node_modules", name)}）；未提交 runtime`);
        }
      }
    }
    const runtimeRequire = createRequire(join(stageRuntime, "package.json"));
    const hash = createHash("sha256");
    const files = await Array.fromAsync(glob(["src/**/*.ts", "src/client/*.js", "tsconfig*.json", "scripts/copy-client.mjs"], { cwd: stageMagic }));
    for (const file of files.sort()) hash.update(file).update(await readFile(join(stageMagic, file)));
    hash.update((await json(join(stageRuntime, "node_modules/typescript/package.json"))).version);
    const digest = hash.digest("hex"), stamp = join(stageMagic, ".agent-skills-build");
    if (!existsSync(join(stageMagic, "lib/index.js")) || !existsSync(stamp) || await readFile(stamp, "utf8") !== digest) {
      run(node, [join(stageRuntime, "node_modules/typescript/bin/tsc"), "-p", join(stageMagic, "tsconfig.build.json")], env);
      run(node, [join(stageMagic, "scripts/copy-client.mjs")], env);
      await writeChanged(stamp, digest, { backup: false });
    }
    // 解析器补丁只操作自有副本：包内容 dereference 复制进暂存区，绝不写穿共享 node_modules 或包内相对链接。
    // 只有真需要补丁时才复制与改写。
    const deepseekTarget = "node_modules/@deepseek-ai/dsh-llm-deepseek";
    const deepseekSource = join(stageRuntime, deepseekTarget);
    const deepseekMain = (await json(join(deepseekSource, "package.json"))).main ?? "lib/index.js";
    const parser = await readFile(join(deepseekSource, deepseekMain), "utf8");
    let parserPlan;
    if (!parser.includes(parserCompatible)) {
      if (parser.split(parserOriginal).length !== 2) throw new Error("llm-deepseek 解析器已变化，未应用兼容补丁");
      const staged = join(stage, "deepseek");
      // dereference: true 把包内相对符号链接展开成实体文件，补丁只会落在暂存区。
      await cp(deepseekSource, staged, { recursive: true, dereference: true });
      const file = join(staged, deepseekMain);
      await assertInside(staged, file, "解析器暂存文件");
      await writeFile(file, parser.replace(parserOriginal, parserCompatible));
      await assertInside(staged, file, "解析器暂存文件");
      parserPlan = { staged, target: deepseekTarget };
    }
    const includeFile = runtimeRequire.resolve("@deepseek-ai/cordis-plugin-include");
    // 宿主用 include 的 entry-list 方言解析补丁：!!js 标量保留为表达式节点，写盘时原样打印。
    const patchYaml = createRequire(includeFile)("js-yaml");
    const { entryListSchema } = await import(pathToFileURL(includeFile).href);
    function parsePatchYaml(raw, path, { requireArray = false } = {}) {
      let data;
      // js-yaml 的异常消息会带源片段（可能含密钥），只报位置。
      try { data = patchYaml.load(raw, { schema: entryListSchema }); }
      catch { throw new Error(`配置含无效 YAML 或自定义标签，未覆盖：${path}`); }
      if (data == null) {
        if (requireArray) throw new Error(`配置必须是条目数组（空文件或仅注释不可用）：${path}`);
        return [];
      }
      if (!Array.isArray(data)) throw new Error(`补丁必须是列表：${path}`);
      return data;
    }
    const dumpPatch = (list) => patchYaml.dump(list, { schema: entryListSchema, noRefs: true, lineWidth: 0 });
    const { default: YAML } = await import(pathToFileURL(runtimeRequire.resolve("yaml")).href);
    function parseYaml(raw, path) {
      const doc = YAML.parseDocument(raw);
      if (doc.errors.length || doc.warnings.length) throw new Error(`配置含无效 YAML 或自定义标签，未覆盖：${path}`);
      return doc.toJS();
    }
    const pi = await json(join(homedir(), ".pi/agent/models.json"), { providers: {} });
    const piAuth = await json(join(homedir(), ".pi/agent/auth.json"), {});
    const savedPatchPath = join(home, "profiles/headless/cordis.patch.yml");
    const savedPatch = existsSync(savedPatchPath) ? parsePatchYaml(await readFile(savedPatchPath, "utf8"), savedPatchPath) : [];
    if (!Array.isArray(savedPatch)) throw new Error(`补丁必须是列表：${savedPatchPath}`);
    const savedLlm = savedPatch.filter((row) => row?.id === "llm-pi-ai").at(-1);
    const savedProviders = savedLlm?.config?.providers ?? {};
    const refs = {};
    const template = await json(templatePath);
    template.push({ id: "magic-context-dsh", config: { registerCompactionEngine: false, memory: {}, dataDir: join(home, "magic-context") } });
    let watchUpdate;
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
        watchUpdate = { path: watchPath, value: JSON.stringify(watch, null, 2) + "\n" };
      }
    }
    if (contextMode) template.push({ id: "mcp-context-mode", disabled: false, config: {
      serverName: "context_mode", transport: "stdio", command: process.execPath,
      args: [join(runtime, "vendor/context-mode/server.mjs"), "--agent", "opencode"],
      failOnStartupError: true,
    } }, { id: "skill-filesystem", config: { customSkillDirs: [join(runtime, "vendor/context-mode/skills")] } });
    const providers = template.find((r) => r.id === "llm-pi-ai").config.providers;
    for (const [route, config] of Object.entries(providers)) {
      const sourceRoute = route === "google" ? "gemini-newapi" : route;
      const local = pi.providers?.[sourceRoute];
      const saved = savedProviders[route] ?? savedProviders[sourceRoute];
      if (saved?.apiKeyEnv) config.apiKeyEnv = saved.apiKeyEnv;
      const address = [saved?.baseURL, process.env[sourceRoute.toUpperCase().replaceAll("-", "_") + "_BASE_URL"], local?.baseUrl]
        .find((value) => typeof value === "string" && value.trim() !== "" && !placeholder(value));
      if (address) config.baseURL = address;
      // 逐级回退到第一个有效值：空串／占位符不等于"已配置"，不能让它挡住 Pi 里的真实 key。
      const key = [process.env[config.apiKeyEnv], local?.apiKey, piAuth[sourceRoute]?.type === "api_key" ? piAuth[sourceRoute].key : undefined]
        .find(usable);
      // 表达式形式的 apiKeyEnv 在补丁里求值，模板阶段没有变量名可登记。
      if (typeof config.apiKeyEnv === "string" && usable(key)) refs[config.apiKeyEnv] = key;
    }
    const deepseekEntry = template.find((r) => r.id === "llm-deepseek").config;
    deepseekEntry.baseURL = providers["anthropic-newapi"].baseURL;
    const credentialPath = join(home, ".credentials.yaml");
    let credentials = {};
    if (existsSync(credentialPath)) credentials = parseYaml(await readFile(credentialPath, "utf8"), credentialPath) ?? {};
    credentials.version ??= 1;

    // 宿主真实合成：bundle → profile → home，复用 app-boot 与 include 的官方纯函数。
    const additions = [...template, { id: "pi2dsh", config: { packages: [join(runtime, "bundle/dsh/pi"), "@dietrichgebert/ponytail"], visionCompanions: false } }];
    const boot = await import(pathToFileURL(runtimeRequire.resolve("@deepseek-ai/dsh-app-boot")).href);
    const installAnchor = runtimeRequire.resolve("@deepseek-ai/dsh/package.json");
    const { resolveConfig } = await import(pathToFileURL(join(stageRuntime, "node_modules/@deepseek-ai/cordis/lib/index.js")).href);
    const { interpolate } = await import(pathToFileURL(join(stageRuntime, "node_modules/@deepseek-ai/cordis-plugin-loader/lib/index.js")).href);
    const llm = await import(pathToFileURL(join(stageRuntime, "node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js")).href);
    const deepseekProvider = await import(pathToFileURL(join(stageRuntime, "node_modules/@deepseek-ai/dsh-llm-deepseek-api-key/lib/index.js")).href);
    const { createLaunchEnvironmentSnapshot } = await import(pathToFileURL(join(stageRuntime, "node_modules/@deepseek-ai/dsh-launch-environment/lib/index.js")).href);
    const launchEnvironment = createLaunchEnvironmentSnapshot([{ source: "process", values: process.env }]);
    // 宿主 profileContext 的形状（dsh/profile-boot-C14i-8IN.js:290-301 里 provide 的对象）。
    // 字段值全部来自真实来源，不猜：
    //   startedBundles = composed.profile.layers.map(l => l.packageName)，即兼容性过滤后真正加载的 bundle
    //   overlays       = --patch 文件加载结果；setup 不传 --patch，故为 []
    //   telemetryDisabledEnv = process.env.DSH_TELEMETRY_DISABLED（原始值，未设置即 undefined）
    //   cwd 是运行时值：安装期只能给部署进程的 cwd，宿主机启动时的样子无法在此保证。
    const profileContextOf = (profile, startedBundles) => {
      const directory = join(home, "profiles", profile);
      return {
        name: profile,
        dir: directory,
        patchPath: join(directory, "cordis.patch.yml"),
        installAnchor,
        startedBundles,
        cwd: process.cwd(),
        home,
        overlays: [],
        telemetryDisabledEnv: process.env.DSH_TELEMETRY_DISABLED,
      };
    };
    // 宿主 boot 的求值作用域；<path> 指向该层条目所在目录，home 层在 home 根。
    const scopeOf = (directory, profileContext) => ({
      ctx: { get: (name) => (name === "profileContext" ? profileContext : undefined), baseUrl: pathToFileURL(directory + "/").href },
      baseUrl: pathToFileURL(directory + "/").href,
      dshHomePath: (...segments) => join(home, ...segments),
    });
    const profilePlans = [];
    for (const profile of profiles) {
      const directory = join(home, "profiles", profile);
      const packagePath = join(directory, "package.json");
      const prior = await json(packagePath, { private: true });
      const patchPath = join(directory, "cordis.patch.yml");
      const original = existsSync(patchPath) ? await readFile(patchPath, "utf8") : "[]\n";
      const disk = parsePatchYaml(original, patchPath);
      const current = structuredClone(disk);
      // deprecated: dsh-gemini-catalog-rc2；确认旧 gemini-newapi 已迁移后可删除重命名段。
      migrateEveryProvider(current, patchPath);
      const result = merge(current, additions);
      migrateEveryProvider(result, patchPath);
      // 宿主按 id 逐行覆盖且 config 整块替换，同 id 多行只有最后一行生效；校验就按这个有效值来。
      const effective = new Map();
      for (const row of result) if (typeof row.id === "string" && "config" in row) effective.set(row.id, row.config);
      if (!prior.dsh?.profile?.bundles?.includes("@deepseek-ai/dsh-web-app") &&
          !result.some((row) => row.insert?.some((entry) => entry.name === "@deepseek-ai/dsh-agent-preset-registry"))) {
        result.push({ insert: [
          { id: "agent-preset-registry", name: "@deepseek-ai/dsh-agent-preset-registry", config: { default: "agent-skills-host" } },
          { id: "agent-skills-host", name: "@deepseek-ai/dsh-agent-preset", config: { id: "agent-skills-host", plugins: [] } },
        ] });
      }
      // 这一层只收集，不做判定：后面的 home 层可能整块覆盖，提前拒绝会误杀合法配置。
      for (const [route, config] of Object.entries(effective.get("llm-pi-ai")?.providers ?? {})) {
        if (!object(config)) continue;
        const env = config.apiKeyEnv;
        if (typeof env !== "string" || !refName.test(env)) continue;
        const value = process.env[env];
        if (usable(value) && !(env in refs)) refs[env] = value;
      }
      const webBundle = profile === "web" ? "@deepseek-ai/dsh-web-app" : `@deepseek-ai/dsh-${profile}`;
      const packages = ["@deepseek-ai/dsh-base", ...(profile === "tui" ? ["@xmoon76/dsh-pi-tui"] : [webBundle]), "pi2dsh", "agent-skills-dsh", "dsh-plugin-magic-context"];
      if (claudeMem) packages.push("@claude-mem/dsh");
      prior.dsh ??= {}; prior.dsh.profile ??= {};
      // 保留用户清单原貌（含重复与退役项）：宿主同样按原顺序处理，
      // 告警序号要对得上用户看到的位置；只追加尚未出现的默认包。
      const existingBundles = Array.isArray(prior.dsh.profile.bundles) ? [...prior.dsh.profile.bundles] : [];
      prior.dsh.profile.bundles = [...existingBundles, ...packages.filter((name) => !existingBundles.includes(name))];
      // 数据没变就沿用原文本，保留人工注释与格式；变了才整篇重写（表达式节点原样打印）。
      profilePlans.push({ profile, directory, packagePath, patchPath, prior, result,
        packageText: JSON.stringify(prior, null, 2) + "\n",
        patchText: isDeepStrictEqual(disk, result) ? original : dumpPatch(result) });
    }
    credentials.refs = { ...refs, ...credentials.refs };

    // 待写文档必须过宿主自己的凭据解析器：无关的已有 refs 也要合法，整份文档形状要与运行时一致。
    const { parseCredentialsDocument } = await import(pathToFileURL(join(stageRuntime, "node_modules/@deepseek-ai/dsh-credentials-local/lib/index.js")).href);
    let credentialsText = YAML.stringify(credentials);
    let parsedCredentials;
    try { parsedCredentials = parseCredentialsDocument(credentialsText, credentialPath); }
    catch (error) { throw new Error(safeReason(error, "凭据文档会被宿主拒绝")); }

    // rc.2 真实流程（profile-boot: readProfilePatches → boot → mountRootInclude → prepareProfilePatches）：
    // 1) loadProfileDirectory 先 dropRetiredBundles，再收集每个 bundle 的 patch；读不出的 bundle 只跳过。
    // 2) patches = bundle 层 + profile 层 + home 层（+ overlays）。
    // 3) 先把这些 patch 合到空树上，再把结果作为一条 insert 应用到根 cordis.yml。
    const homePatchPath = join(home, "cordis.patch.yml");
    // 宿主 loadOverlayPatches 的 YAMLException 会带源行（可能含密钥），只报路径。
    const loadOverlay = (path) => {
      try { return boot.loadOverlayPatches("dsh", path); }
      catch { throw new Error(`补丁无法解析（含无效 YAML 或自定义标签；源内容已隐藏）：${path}`); }
    };
    const homePatch = existsSync(homePatchPath) ? loadOverlay(homePatchPath) : [];
    const { applyEntryPatches } = await import(pathToFileURL(includeFile).href);
    const retiredBundles = new Set(["@deepseek-ai/dsh-experimental-schedule-bundle"]);
    // 宿主遇到无效补丁会 WARN 并跳过；这里同样输出，避免静默吞掉未生效的补丁。
    // 补丁参数可能是 config 值（含密钥），一律不回显，也不序列化 args。
    const patchWarning = (message) => {
      warn(`补丁未生效：${String(message).replaceAll(/%C/g, "[参数已隐藏]")}`);
    };
    for (const plan of profilePlans) {
      // 宿主 prepareProfile 无条件写回常量根 `[]`（rc.2: `writeFileSync(cordis.yml, PROFILE_ROOT_CONFIG)`），
      // 每次都重建，旧根内容不会被读取。这里同样固定 []，不读也不解析旧 profile 根。
      const rootRows = [];
      // 告警序号对齐用户原始清单：编号在去重、退役过滤与合并之前完成。
      // 最终写入计划就是用户可见顺序：[原有项..., 追加项...]。序号直接按这个数组编号，
      // 再做 seen／退役过滤，不再二次偏移。
      const bundleBundles = (plan.prior.dsh?.profile?.bundles ?? []).map((name, originalIndex) => ({ name, originalIndex }));
      const bundleLayers = [];
      const startedBundles = [];
      // 与宿主 loadProfileDirectory 同一判据：engines.dsh／peerDependencies 不满足且无精确豁免就不加载。
      const exemptions = boot.readProfileVersionExemptions(plan.directory);
      for (const { name: packageName, originalIndex } of bundleBundles) {
        if (retiredBundles.has(packageName)) continue;
        // 宿主按清单出现次数逐个加载（含重复项），startedBundles 同样保留重复计数；
        // 这里不去重，序号直接用最终计划里的原始索引。
        try {
          const packageDir = boot.resolveBundleDir("dsh", packageName, installAnchor, plan.directory);
          const manifest = boot.readProfileManifest("dsh", packageDir);
          const bundle = manifest.dsh?.bundle;
          if (bundle === undefined) throw new Error(`bundle ${JSON.stringify(packageName)} declares no dsh.bundle in its package.json`);
          const issue = boot.evaluatePluginCompatibility(manifest, exemptions);
          if (issue !== undefined && !issue.exempted) throw new Error(boot.pluginCompatibilityWarning(issue));
          bundleLayers.push(boot.bundlePatchPaths(packageDir, bundle).flatMap((path) => loadOverlay(path)));
          startedBundles.push(packageName);
        } catch {
          // 宿主同样只报告并跳过读不出的 bundle，不会因此整次启动失败。
          // bundle 名可能来自用户配置（甚至带 token 的 URL），manifest/parser 的错误也可能带源片段，
          // 因此只报清单序号与失败类别。
          warn(`${plan.profile}：跳过 profile bundle 清单第 ${originalIndex + 1} 项（读取或兼容性检查失败，详细值已隐藏）`);
        }
      }
      // profileContext 的 startedBundles 是"真正加载成功"的 bundle 列表，与宿主 layers 一致。
      const patches = [...bundleLayers, plan.result, homePatch].flat();
      const composed = applyEntryPatches([], patches, patchWarning);
      const finalRows = applyEntryPatches(rootRows, [{ insert: composed }], patchWarning);
      // 宿主语义（rc.2 源码 + 真实 boot 对照）：
      // 1) EntryGroup.update：`Object.fromEntries(config.map(o => [o.id, o]))` —— 同 id 取最后整行。
      // 2) Group：`super(ctx, ctx.fiber.entry.parent.tree)` —— 普通 cordis:group 共享父级 store。
      // 3) Include 继承 EntryTree 并 `super(ctx)`，因此嵌套 include 是**独立 store + 独立 baseUrl**，
      //    id 不与父 store 冲突；其行 = 文件内容经 `config.patches` 应用后的结果。
      // 4) 创建顺序是"根层 → 各 group 子项 → 更深层"的 BFS；后创建的同 id 整行覆盖前面的。
      //    每层先按 id 选该层最后一行，只展开这些 winner 的 group 子项——被覆盖的旧 group 子项根本不会创建。
      const finalRefs = new Map(Object.entries(credentials.refs ?? {}));
      const resolveRef = (name) => {
        if (finalRefs.has(name)) return finalRefs.get(name);
        const value = process.env[name];
        if (usable(value)) { finalRefs.set(name, value); return value; }
        return undefined;
      };
      const validateStore = async ({ rows, directory, label, required, seen, inherited = false }) => {
        const localScope = scopeOf(directory, profileContextOf(plan.profile, startedBundles));
        const evaluate = (value) => {
          try { return interpolate(localScope, value); }
          catch (error) { throw new Error(safeReason(error, `${label}：最终配置表达式求值失败`)); }
        };
        // 宿主 Entry.disabled 分两层（源码 + 实测）：
        //   ownDisabled：`if (this.options.group) return false` —— 容器自身永远不算禁用，照常挂载。
        //   inheritedDisabled：不看 group 短路 —— 命名 Group 的 disabled:true 会传给它创建的子项
        //   （实测：命名 Group + group:true + disabled:true 时子项 pi.disabled=true 且不加载）。
        // !!js 的 disabled 在条目上下文求值，原始表达式保留在配置里。
        const evalDisabled = (row, who) => {
          if (row?.disabled === undefined) return false;
          if (!jsExpr(row.disabled)) return Boolean(row.disabled);
          try { return Boolean(interpolate(localScope, row.disabled)); }
          catch (error) { throw new Error(safeReason(error, `${label}：${who} 的 disabled 表达式求值失败`)); }
        };
        // 宿主对 group 用真值判断（cordis-plugin-include `if (entry.group && ...)`、
        // loader `if (this.options.group) return false`），因此 group: 1 与 group: true 等价。
        const isGroupFlag = (row) => Boolean(row?.group);
        const ownDisabled = (row, who) => (isGroupFlag(row) ? false : evalDisabled(row, who));
        const inheritedDisabled = (row, who) => evalDisabled(row, who);
        // 官方 ensureId 用 `if (!options.id)` 只为 falsy 分配新 id，但 patch 合成与 EntryGroup.update
        // 的 `Object.fromEntries([o.id, o])` 会把 ""、0、false 当作显式 key 去重（实测：两行同 falsy id
        // 只挂载最后一条并获得新 id）。只有 undefined／null 才是真正互不覆盖的匿名条目。
        const isAnonymous = (row) => row?.id === undefined || row?.id === null;
        // 用户可见的位置一律用纯序号路径，避免把用户写的 id／name（可能是密钥或 URL）带进错误消息。
        const labeled = (prefix, index) => `${prefix}#${index + 1}`;
        // 宿主去重：每个 EntryGroup 先 `Object.fromEntries(config.map(o => [o.id, o]))`，
        // 所有 id 都被字符串化成同一个键（实测 num3-str3：3 与 "3" 共用键 "3"），后者整行替换前者。
        // 因此本地键统一 `scope\0String(id)`；匿名（undefined/null）各自独立。
        let counter = 0;
        const symbolFor = (item) => (item.sym ??= Symbol(`anonymous:${counter++}`));
        const localKey = (item) => (isAnonymous(item.row) ? symbolFor(item) : `${item.scope}\0${String(item.row.id)}`);
        // Object.fromEntries 的枚举顺序：array-index 键升序 → 其它字符串键插入序 → Symbol 插入序。
        const INDEX_KEY = /^(?:0|[1-9][0-9]{0,9})$/;
        const isIndexKey = (key) => INDEX_KEY.test(key) && Number(key) < 2 ** 32 - 1;
        const orderItems = (items) => {
          const named = items.filter((item) => !isAnonymous(item.row));
          const anonymous = items.filter((item) => isAnonymous(item.row));
          const indexed = named.filter((item) => isIndexKey(String(item.row.id)));
          const plain = named.filter((item) => !isIndexKey(String(item.row.id)));
          indexed.sort((a, b) => Number(a.row.id) - Number(b.row.id));
          return [...indexed, ...plain, ...anonymous];
        };
        // 条目是否会被真正创建：`group: true` 只豁免自身 disabled；
        // 无该标记且父级命名 Group 禁用时不创建（真实 boot 矩阵 E）。
        const willCreate = (item) => {
          const { row, who } = item;
          if (Boolean(item.inherited) && !isGroupFlag(row)) return false;
          return !ownDisabled(row, who);
        };
        const isIncludeName = (name) => name === "cordis:include" || name === "@deepseek-ai/cordis-plugin-include";
        const canonicalProvider = (name) => {
          if (name === "llm-pi-ai" || name === "@deepseek-ai/dsh-llm-pi-ai") return "llm-pi-ai";
          if (name === "llm-deepseek" || name === "@deepseek-ai/dsh-llm-deepseek-api-key") return "llm-deepseek";
          return undefined;
        };
        // 每个 localKey 先做 scope 内去重，得到整行胜出的 winner（宿主 `Object.fromEntries` 语义）。
        // 实测 S1/S2/S3：即使最后一条是 disabled，同一 localKey 里更早的启用行也不会被创建，
        // 因此无需把被遮住的旧行当候选。
        const providerWinners = [];
        const includeWinners = [];
        // 每个 store 键上出现的启用候选（用于跨 EntryGroup 的保守冲突判定）。
        let level = rows.map((row, index) => ({ row, chain: [], scope: "root", inherited: Boolean(inherited), who: labeled("根条目", index) }));
        while (level.length) {
          const groups = new Map();
          for (const item of level) {
            const key = localKey(item);
            if (!groups.has(key)) groups.set(key, []);
            groups.get(key).push(item);
          }
          // scope 首次出现顺序；scope 内按宿主枚举顺序决定谁最后落位。
          const scopeOrder = new Map();
          for (const item of level) if (!scopeOrder.has(item.scope)) scopeOrder.set(item.scope, scopeOrder.size);
          const orderedGroups = [...groups.entries()].sort((a, b) => {
            const sa = scopeOrder.get(a[1][0].scope), sb = scopeOrder.get(b[1][0].scope);
            return sa === sb ? 0 : sa - sb;
          });
          const next = [];
          for (const [, members] of orderedGroups) {
            const ordered = orderItems(members);
            const winner = ordered[ordered.length - 1];
            const { row, chain, who, scope } = winner;
            const created = willCreate(winner);
            if (isIncludeName(row?.name) && !isGroup(row)) {
              // 不同 Group 的同 ID Include 落在同一 store 键，启用者取决于 import 顺序；
              // 这里收所有"会被创建且启用"的候选，交给下面的冲突检查与递归验收。
              if (created) includeWinners.push({ row, who, inherited: winner.inherited, id: row.id, scope, raw: row.config });
              continue;
            }
            if (isGroup(row)) {
              // 禁用的命名 Group 不创建子项；`group: true` 容器自身仍挂载并展开，
              // 但禁用状态继续向下传（真实 boot 矩阵 E / L3）。
              if (!created) continue;
              const childDisabled = Boolean(winner.inherited || evalDisabled(row, who));
              const childScope = `${scope}/${who}`;
              row.config.forEach((child, index) => {
                if (!child || typeof child !== "object") return;
                next.push({ row: child, chain: [...chain, row], scope: childScope, inherited: childDisabled, who: labeled(`${who}/子项`, index) });
              });
              continue;
            }
            const plugin = canonicalProvider(row?.name ?? row?.id);
            if (plugin) providerWinners.push({ plugin, raw: row.config, id: row.id, scope, enabled: created });
          }
          level = next;
        }
        // 跨 EntryGroup 的同 truthy ID：不同 Group 的插件异步 import 顺序不可静态断定，
        // 因此存在多个"配置不同的启用候选"时保守拒绝（配置相同才验一份）。
        const byId = new Map();
        for (const entry of providerWinners) {
          if (!entry.enabled || !entry.id) continue;
          const key = String(entry.id);
          if (!byId.has(key)) byId.set(key, []);
          byId.get(key).push(entry);
        }
        for (const entries of byId.values()) {
          if (new Set(entries.map((entry) => entry.scope)).size < 2) continue;
          if (entries.every((entry) => isDeepStrictEqual(entry.raw, entries[0].raw))) continue;
          throw new Error(`${label}：不同 Group 都有同 ID provider 且配置不同，挂载顺序无法确认；请只保留一处，尚未写入任何内容`);
        }
        // Include 同理：不同 Group 的同 ID Include 配置不同 → 谁挂载取决于 import 顺序，保守拒绝。
        const includeById = new Map();
        for (const entry of includeWinners) {
          if (!entry.id) continue;
          const key = String(entry.id);
          if (!includeById.has(key)) includeById.set(key, []);
          includeById.get(key).push(entry);
        }
        for (const entries of includeById.values()) {
          if (new Set(entries.map((entry) => entry.scope)).size < 2) continue;
          if (entries.every((entry) => isDeepStrictEqual(entry.raw, entries[0].raw))) continue;
          throw new Error(`${label}：不同 Group 都有同 ID Include 且配置不同，挂载顺序无法确认；请只保留一处，尚未写入任何内容`);
        }
        // 每个 scope 内已取整行 winner；随后所有"仍可能被创建且启用"的 provider 一律进入验收。
        // 不再按 BFS 深度挑选"最终生效者"：跨命名 Group 的挂载由异步 import 决定，
        // 深度不能作为推定依据（保守拒绝部分宿主可运行配置，已记录取舍）。
        // 存在性看所有会被创建的行（禁用也算"最终配置里存在"）。
        const knownProviders = new Set(providerWinners.map(({ plugin }) => plugin));
        const enabled = [];
        const addEnabled = (entry) => {
          if (!entry.enabled || !entry.plugin) return;
          if (enabled.some((item) => item.plugin === entry.plugin && isDeepStrictEqual(item.raw, entry.raw))) return;
          enabled.push({ plugin: entry.plugin, raw: entry.raw });
        };
        providerWinners.forEach(addEnabled);
        // 每个启用的 Include 都独立递归：不同 ID／补丁／继承状态是不同的 store，
        // 同一文件被多次引用必须逐次验收（仅用递归栈 seen 做循环检测）。
        for (const { row, who, inherited } of includeWinners) {
          const rawPath = row.config?.path;
          // 宿主把 config.path 当原始字符串用（!!js 节点会被 extname 拒绝），这里不做求值。
          if (typeof rawPath !== "string" || rawPath.trim() === "") {
            throw new Error(`${label}：include ${who} 的 path 必须是非空字符串，无法确认其配置`);
          }
          // 循环键 = 宿主实际解析出的绝对路径：`new URL(config.path, ctx.baseUrl)` 再取路径。
          // 不使用 realpath（会改写相对基准）；相对基准仍是链接路径所在目录。
          // URL 构造与 fileURLToPath 的报错会带回原值，统一隐藏。
          let filename;
          try { filename = fileURLToPath(new URL(rawPath, pathToFileURL(directory + "/").href)); }
          catch { throw new Error(`${label}：include ${who} 的 path 不是受支持的位置（值已隐藏）`); }
          const ext = extname(filename);
          if (ext !== ".yml" && ext !== ".yaml" && ext !== ".json") {
            throw new Error(`${label}：include ${who} 的扩展名不受宿主支持（只支持 .yml/.yaml/.json），无法确认其配置`);
          }
          if (seen.has(filename)) throw new Error(`${label}：include ${who} 造成循环引用，无法确认配置`);
          const nextSeen = new Set([...seen, filename]);
          let raw;
          try {
            raw = await readFile(filename, "utf8");
          } catch (error) {
            // 宿主 Service.init：只有 ENOENT 且有 config.initial 时才写初值；其它 IO 错误照常失败。
            // ENOTDIR 说明父路径是文件，归到父目录错误（宿主写 filename.tmp 时同样会失败）。
            if (error?.code === "ENOTDIR") throw new Error(`${label}：include ${who} 的父目录不是目录（位置已隐藏）`);
            if (error?.code !== "ENOENT") throw new Error(`${label}：include ${who} 的配置文件不可读（位置已隐藏）`);
            if (row.config?.initial === undefined) throw new Error(`${label}：include ${who} 的配置文件不可读（位置已隐藏）`);
            const initial = row.config.initial;
            // 宿主用 entryListSchema dump/parse；非数组（含 !!js 节点）都不能当作条目列表。
            if (!Array.isArray(initial) || initial.some((entry) => !entry || typeof entry !== "object" || Array.isArray(entry))) {
              throw new Error(`${label}：include ${who} 的 initial 必须是条目数组，无法确认配置`);
            }
            // 宿主写初值走 `writeFile(filename + ".tmp")`，所以父目录必须已存在、是目录且可写；
            // 部署不预建目录或文件，口径与宿主一致。
            const parent = dirname(filename);
            let parentStat;
            try { parentStat = await stat(parent); }
            catch { throw new Error(`${label}：include ${who} 的父目录不存在或不可访问（位置已隐藏）`); }
            if (!parentStat.isDirectory()) throw new Error(`${label}：include ${who} 的父目录不是目录（位置已隐藏）`);
            try { await access(parent, constants.W_OK); }
            catch { throw new Error(`${label}：include ${who} 的父目录不可写（位置已隐藏）`); }
            // 宿主固定写 `filename + ".tmp"` 再 rename。tmp 已存在时：
            //   只接受可写单链接普通文件；目录会 EISDIR，链接会让 writeFile 截断其它目标。
            // 部署不创建/修改 tmp 或目标文件。
            const tmpPath = `${filename}.tmp`;
            let tmpStat;
            try { tmpStat = await lstat(tmpPath); } catch (error) {
              if (error?.code !== "ENOENT") throw new Error(`${label}：include ${who} 的临时文件不可访问（位置已隐藏）`);
            }
            if (tmpStat !== undefined) {
              if (tmpStat.isDirectory()) throw new Error(`${label}：include ${who} 的临时路径已是目录（位置已隐藏）`);
              if (!tmpStat.isFile()) throw new Error(`${label}：include ${who} 的临时路径不是普通文件（位置已隐藏）`);
              if (tmpStat.nlink > 1) throw new Error(`${label}：include ${who} 的临时文件有多个硬链接（位置已隐藏）`);
              try { await access(tmpPath, constants.W_OK); }
              catch { throw new Error(`${label}：include ${who} 的临时文件不可写（位置已隐藏）`); }
            }
            const nestedRows = applyEntryPatches(structuredClone(initial), row.config?.patches ?? [], patchWarning);
            await validateStore({
              rows: nestedRows,
              directory: parent,
              label: `${label}：include ${who}`,
              required: false,
              inherited: Boolean(inherited) || evalDisabled(row, who),
              seen: nextSeen,
            });
            continue;
          }
          let nested;
          if (ext === ".json") {
            // 宿主 .json 走严格 JSON.parse：注释／尾逗号都会被拒绝。
            // JSON.parse 的消息会带源片段，只报位置。
            try { nested = JSON.parse(raw); }
            // JSON.parse 的消息会带源片段与文件名，只报序号位置。
            catch { throw new Error(`${label}：include ${who} 的 JSON 无法解析（详细值与路径已隐藏）`); }
            if (!Array.isArray(nested)) throw new Error(`${label}：include ${who} 必须是条目数组（位置已隐藏）`);
          } else {
            // 复用条目方言解析，但错误标签换成不带路径的 include 位置。
            try { nested = parsePatchYaml(raw, "", { requireArray: true }); }
            catch { throw new Error(`${label}：include ${who} 的 YAML 使用无效标签或不是条目数组（详细值与路径已隐藏）`); }
          }
          const nestedRows = applyEntryPatches(nested, row.config?.patches ?? [], patchWarning);
          await validateStore({
            rows: nestedRows,
            directory: dirname(filename),
            label: `${label}：include ${who}`,
            required: false,
            inherited: Boolean(inherited) || evalDisabled(row, who),
            seen: nextSeen,
          });
        }
        // 本 store 里实际存在的 provider；required 时才要求两个必需 provider 存在。
        if (required) {
          if (!knownProviders.has("llm-pi-ai")) throw new Error(`${label}：最终配置缺少必需 provider llm-pi-ai`);
          if (!knownProviders.has("llm-deepseek")) throw new Error(`${label}：最终配置缺少必需 provider llm-deepseek`);
        }
        for (const entry of enabled.filter((item) => item.plugin === "llm-pi-ai")) {
          const where = `${label}：llm-pi-ai`;
          const withProviders = (entry.raw === undefined ? undefined : evaluate(entry.raw))?.providers;
          if (!object(withProviders)) throw new Error(`${where}：最终配置的 providers ${describeValue(withProviders)}`);
          const missing = [];
          for (const route of requiredRoutes) {
            if (route === "llm-deepseek") continue;
            const config = withProviders[route];
            if (!object(config)) { missing.push(route); continue; }
            if (typeof config.apiKeyEnv !== "string" || !refName.test(config.apiKeyEnv)) {
              // 必需 route 是固定名，可以安全回显。
              throw new Error(`${where}：最终配置 ${route} 的 apiKeyEnv 非法：${describeValue(config.apiKeyEnv)}`);
            }
            // 引用名可能是误填的真实密钥，只报位置。
            if (!usable(resolveRef(config.apiKeyEnv))) throw new Error(`${where}：最终配置 ${route} 的凭据引用缺失或为空（引用名已隐藏）`);
          }
          if (missing.length) throw new Error(`${where}：最终配置缺少必需 provider ${missing.join(", ")}`);
          // 自定义路由键可能被误填成带 token 的 URL，因此只有固定必需名可回显；
          // 其余一律报「自定义 provider#N」。apiKeyEnv／baseURL 的错误标签同样走这个安全名。
          let customIndex = 0;
          for (const [route, config] of Object.entries(withProviders)) {
            const safeName = requiredRoutes.has(route) ? route : `自定义 provider#${++customIndex}`;
            if (!object(config)) continue;
            if (config.apiKeyEnv !== undefined && (typeof config.apiKeyEnv !== "string" || !refName.test(config.apiKeyEnv))) {
              throw new Error(`${where}：最终配置 ${safeName} 的 apiKeyEnv 非法：${describeValue(config.apiKeyEnv)}`);
            }
            if (config.baseURL === undefined || config.baseURL === null) {
              if (requiredRoutes.has(route)) throw new Error(`${where}：最终配置 ${safeName} 缺少网关地址`);
              continue;
            }
            assertBaseUrl(config.baseURL, `${where}：最终配置 ${safeName}`);
          }
          try { resolveConfig({ Config: llm.Config, name: llm.name }, { providers: withProviders }); }
          catch (error) { throw new Error(safeReason(error, `${where}：pi-ai providers 配置校验未通过`)); }
        }
        for (const entry of enabled.filter((item) => item.plugin === "llm-deepseek")) {
          const where = `${label}：llm-deepseek`;
          if (entry.raw === undefined) throw new Error(`${where}：最终配置缺少 llm-deepseek 配置`);
          const dsConfig = evaluate(entry.raw);
          // 宿主适配器在这里拒绝带 query／fragment／凭据的网关；提前给出结论，避免落到无法去值的第三方消息。
          if (typeof dsConfig?.baseURL === "string") {
            let parsed;
            try { parsed = new URL(dsConfig.baseURL); } catch { parsed = undefined; }
            if (parsed && (parsed.username || parsed.password || parsed.search || parsed.hash)) {
              throw new Error(`${where}：网关地址不得带凭据、query 或 fragment（位置：llm-deepseek.baseURL）`);
            }
          }
          // resolve → plainOptions → resolveAdapterOptions 都可能把 config 值写进错误消息，整体包装。
          let options;
          try {
            const resolved = resolveConfig({ Config: deepseekProvider.Config, name: deepseekProvider.name }, dsConfig);
            options = deepseekProvider.resolveAdapterOptions(deepseekProvider.plainOptions(resolved), launchEnvironment);
          } catch (error) { throw new Error(safeReason(error, `${where}：DeepSeek 配置校验未通过`)); }
          if (typeof options?.apiKeyEnv !== "string" || !refName.test(options.apiKeyEnv)) {
            throw new Error(`${where}：最终配置的凭据引用非法（${describeValue(options?.apiKeyEnv)}）`);
          }
          // apiKeyEnv 槽位可能被误填成真实密钥（合法变量名也可能是一串密钥），一律不回显。
          if (!usable(resolveRef(options.apiKeyEnv))) throw new Error(`${where}：最终配置的凭据引用缺失或为空（引用名已隐藏）`);
        }
      };
      await validateStore({
        rows: finalRows,
        directory: plan.directory,
        label: plan.profile,
        required: true,
        // 根不参与 Include 循环判定（始终按 [] 合成，不读取旧根），递归栈从空开始。
        seen: new Set(),
      });
      // 最终配置认到的额外凭据也要落地，否则写出后启动仍缺 key。
      for (const [name, value] of finalRefs) if (!(name in refs)) refs[name] = value;
    }
    // 待写文档：文件里已有的值保持优先，只补新引用；再整体过一遍宿主解析器。
    credentials.refs = { ...refs, ...(credentials.refs ?? {}) };
    if (Object.keys(credentials.refs).some((name) => !parsedCredentials.refs.has(name))) {
      credentialsText = YAML.stringify(credentials);
      try { parsedCredentials = parseCredentialsDocument(credentialsText, credentialPath); }
      catch (error) { throw new Error(safeReason(error, "凭据文档会被宿主拒绝")); }
    }

    const launcher = join(root, "dsh");
    const entry = join(runtime, "node_modules/@deepseek-ai/dsh/lib/bin.js");
    const launcherText = `#!/bin/sh\n# agent-skills managed dsh launcher\nif [ -z "\${DSH_HOME:-}" ]; then export DSH_HOME=${quote(home)}; fi\nexport PATH=${quote(dirname(node))}:"$PATH"\nif [ "$#" -eq 0 ]; then set -- tui; fi\nexec ${quote(node)} ${quote(entry)} "$@"\n`;
    const writes = [[launcher, launcherText], [credentialPath, credentialsText]];
    if (watchUpdate) writes.push([watchUpdate.path, watchUpdate.value]);
    for (const plan of profilePlans) {
      writes.push([plan.packagePath, plan.packageText], [plan.patchPath, plan.patchText]);
      // cordis.yml 只在缺失时创建；这里仍预检链接，避免提交后才失败。
      if (!existsSync(join(plan.directory, "cordis.yml"))) writes.push([join(plan.directory, "cordis.yml"), "[]\n"]);
    }
    if (parserPlan) {
      const target = join(runtime, parserPlan.target);
      await assertInside(runtime, target, "解析器目标");
      if ((await lstat(target).catch(() => undefined))?.isSymbolicLink()) throw new Error(`不覆盖符号链接：${target}`);
    }
    // 提交阶段要整目录替换的受管资产：路径必须在 runtime 实体目录内，且不是链接。
    for (const path of [join(runtime, "bundle"), join(runtime, "vendor/magic-context"), ...(contextMode ? [join(runtime, "vendor/context-mode")] : [])]) {
      await assertInside(runtime, path, "受管资产");
      if ((await lstat(path).catch(() => undefined))?.isSymbolicLink()) throw new Error(`不覆盖符号链接：${path}`);
    }
    // node_modules 本身也必须在 runtime 内：外链说明依赖目录属于别处，提交会改写它。
    if (existsSync(join(runtime, "node_modules"))) await assertInside(runtime, join(runtime, "node_modules"), "runtime 依赖目录");

    // 旧 output-store 允许把快照放到任意绝对路径，包括受管 runtime 内的隐藏目录。必须在任何配置
    // 临时文件或备份产生前完成保护；冲突时直接停止，stage 由 finally 清理，live 配置尚未触碰。
    let preservedSnapshots = 0;
    if (existsSync(runtime)) {
      const preserveTree = async (directory, prefix = "") => {
        for (const entry of await readdir(directory, { withFileTypes: true })) {
          if (entry.isSymbolicLink()) continue;
          const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
          const source = join(runtime, rel);
          if (entry.isDirectory()) { await preserveTree(source, rel); continue; }
          if (!entry.isFile() || !/^[a-f0-9]{64}\.txt$/.test(entry.name)) continue;
          const destination = join(stageRuntime, rel), sourceStat = await lstat(source);
          if (!sourceStat.isFile()) continue;
          if (existsSync(destination)) {
            const destinationStat = await stat(destination);
            if (sourceStat.dev === destinationStat.dev && sourceStat.ino === destinationStat.ino) continue;
            if (!(await readFile(source)).equals(await readFile(destination))) throw new Error("受管 runtime 内的历史快照与新资产冲突，未替换 runtime");
            continue;
          }
          await assertInside(stageRuntime, destination, "历史快照目标");
          await mkdir(dirname(destination), { recursive: true });
          await cp(source, destination);
          await chmod(destination, sourceStat.mode & 0o777);
          preservedSnapshots += 1;
        }
      };
      await preserveTree(runtime);
    }
    if (preservedSnapshots) process.stdout.write(`历史快照已保留在受管 runtime 原路径：${preservedSnapshots} 个文件\n`);

    // 配置写入先全部预置（真实文件 + 备份），把可写性、同名冲突都挡在提交之前。
    let preparedWrites;
    try {
      preparedWrites = [];
      for (const [path, value] of writes) {
        const options = path === launcher ? { mode: 0o755 } : path === credentialPath ? { mode: 0o600, ownerOnly: true } : {};
        const prepared = await prepareWrite(path, value, options);
        if (prepared) preparedWrites.push(prepared);
      }
    } catch (error) {
      for (const prepared of preparedWrites) await discardWrite(prepared);
      // 这里只会是本函数自己抛出的位置／类别错误；仍不拼接第三方消息。
      const reason = typeof error?.message === "string" ? error.message : "未知失败";
      throw new Error(`${reason}（写盘前预检，runtime／watch／凭据均未改动）`);
    }

    // 受管资产提交：先在同一父目录建好完整替换目录，再整目录换位；失败可原样换回，不留半套。
    // 包内 node_modules（Magic Context 自带 peer 依赖）不在舞台副本里，必须从现有 runtime 继承。
    const managed = [
      [join(runtime, "bundle"), join(stageRuntime, "bundle")],
      [join(runtime, "vendor/magic-context"), stageMagic],
      ...(contextMode ? [[join(runtime, "vendor/context-mode"), join(stageRuntime, "vendor/context-mode")]] : []),
    ];
    const parked = [];
    let swapped;
    // 恢复顺序固定：新内容先 rename 到隔离名（改名不需要写目录内容，0555 也不挡），
    // 再把旧目录换回原位，最后才 best-effort 删隔离目录。清理失败只 WARN，不掩盖恢复结果。
    const restoreAll = async (error, writesToDiscard = preparedWrites) => {
      const trash = [], failures = [];
      const quarantine = async (path) => {
        const target = `${path}.failed-${uniqueSuffix()}`;
        try { await rename(path, target); trash.push(target); return true; }
        catch (renameError) {
          if (renameError.code === "ENOENT") return true;
          failures.push(`${path} 无法隔离：${renameError.message}`);
          return false;
        }
      };
      if (swapped) {
        const previous = swapped;
        if (await quarantine(runtime)) {
          if (previous.hadRuntime) {
            try { await rename(previous.backup, runtime); }
            catch (restoreError) { failures.push(`旧 runtime 保留在 ${previous.backup}：${restoreError.message}`); }
          }
        } else if (previous.hadRuntime) failures.push(`旧 runtime 保留在 ${previous.backup}`);
        swapped = undefined;
      }
      for (const [dir, aside] of parked.reverse()) {
        if (await quarantine(dir) && aside) {
          try { await rename(aside, dir); }
          catch (restoreError) { failures.push(`旧资产 ${dir} 保留在 ${aside}：${restoreError.message}`); }
        } else if (aside) failures.push(`旧资产 ${dir} 保留在 ${aside}`);
      }
      parked.length = 0;
      for (const path of trash) await forceRemove(path, path);
      for (const prepared of writesToDiscard) await discardWrite(prepared).catch(() => {});
      if (failures.length) throw new Error(`${error.message}；回滚未完全恢复：${failures.join("；")}`);
      throw error;
    };
    try {
      if (depsChanged) {
        // 新装的包就在暂存树里，整目录替换成打补丁的自有副本再交换 runtime。
        if (parserPlan) {
          const target = join(stageRuntime, parserPlan.target);
          await forceRemove(target, target);
          await cp(parserPlan.staged, target, { recursive: true, dereference: true });
        }
        // 提交前才把外部链接重定位成"最终 runtime 位置"的写法，并逐项验证解析结果。
        for (const [name, target] of externalLinks) {
          const finalPath = join(runtime, "node_modules", name);
          const staged = join(stageRuntime, "node_modules", name);
          await forceRemove(staged, staged);
          await mkdir(dirname(staged), { recursive: true });
          await symlink(relative(dirname(finalPath), target), staged, "dir");
          const linked = await readlink(staged);
          const resolved = resolve(dirname(finalPath), linked);
          if (resolved !== target) throw new Error(`外部依赖 ${name} 交换后会指向 ${resolved}，应为 ${target}；未提交 runtime`);
        }
        const backup = `${runtime}.bak-${uniqueSuffix()}`;
        const hadRuntime = existsSync(runtime);
        if (hadRuntime) await rename(runtime, backup);
        swapped = { backup, hadRuntime };
        await rename(stageRuntime, runtime);
        process.stdout.write(hadRuntime ? `依赖已更新；旧 runtime 保留为 ${backup}\n` : "依赖已安装；暂存 runtime 已提交\n");
      } else {
        // 依赖不变：node_modules 是共享只读目录，链接本来就在最终位置，只做验证。
        for (const [name, target] of externalLinks) {
          const finalPath = join(runtime, "node_modules", name);
          const linked = await readlink(finalPath).catch(() => undefined);
          if (linked === undefined) throw new Error(`外部依赖 ${name} 未安装为链接，未提交 runtime`);
          const resolved = resolve(dirname(finalPath), linked);
          if (resolved !== target) throw new Error(`外部依赖 ${name} 指向 ${resolved}，应为 ${target}；未提交 runtime`);
        }
        const prepared = new Map();
        try {
          for (const [dir, source] of managed) {
            const incoming = `${dir}.new-${uniqueSuffix()}`;
            await mkdir(dirname(dir), { recursive: true });
            await cp(source, incoming, { recursive: true, dereference: true });
            // cp 会把源目录的 0555 之类权限一起带过来，令后续写入／清理 EACCES；只放开目录。
            await chmodDirs(incoming);
            // 包内依赖不在舞台副本里，从现有 runtime 原样继承。
            const bundled = join(dir, "node_modules");
            if (existsSync(bundled)) await cp(bundled, join(incoming, "node_modules"), { recursive: true, dereference: false });
            prepared.set(dir, incoming);
          }
          // 全部建好后一次性换位；这一步只是改名，失败概率低且下面能整体换回。
          for (const [dir, incoming] of [...prepared]) {
            const aside = `${dir}.old-${uniqueSuffix()}`;
            const hadPrevious = existsSync(dir);
            if (hadPrevious) await rename(dir, aside);
            parked.push([dir, hadPrevious ? aside : undefined]);
            await rename(incoming, dir);
            prepared.delete(dir);
          }
        } catch (error) {
          for (const incoming of prepared.values()) await forceRemove(incoming, incoming);
          throw error;
        }
        // 共享依赖只读复用；解析器这一包也走受管换位，后续配置失败可整体恢复。
        if (parserPlan) {
          const target = join(runtime, parserPlan.target);
          const incoming = `${target}.new-${uniqueSuffix()}`;
          await cp(parserPlan.staged, incoming, { recursive: true, dereference: true });
          await chmodDirs(incoming);
          const aside = `${target}.old-${uniqueSuffix()}`;
          const hadPrevious = existsSync(target);
          if (hadPrevious) await rename(target, aside);
          parked.push([target, hadPrevious ? aside : undefined]);
          try { await rename(incoming, target); }
          catch (error) { await forceRemove(incoming, incoming); throw error; }
        }
      }
    } catch (error) {
      await restoreAll(error);
    }
    // 旧受管目录要等配置也提交成功后再删除。
    // 配置写入纳入同一事务：逐项 rename，失败则回滚已写项并恢复 runtime／受管目录。
    const committed = [];
    const linkedModules = [];
    try {
      for (const prepared of preparedWrites) {
        await commitWrite(prepared);
        committed.push(prepared);
      }
      for (const plan of profilePlans) {
        const modules = join(plan.directory, "node_modules");
        const stat = await lstat(modules).catch((error) => { if (error.code !== "ENOENT") throw error; });
        if (!stat) {
          await symlink(join(runtime, "node_modules"), modules, "junction");
          linkedModules.push(modules);
        }
      }
    } catch (error) {
      const pendingWrites = preparedWrites.filter((item) => !committed.includes(item));
      for (const prepared of committed.reverse()) {
        try { await undoWrite(prepared); }
        catch (undoError) {
          warn(`配置 ${prepared.path} 恢复失败（${undoError?.code ?? "未知原因"}）；备份保留在 ${prepared.backupPath ?? prepared.path}`);
        }
      }
      for (const modules of linkedModules) await rm(modules, { force: true }).catch(() => {});
      await restoreAll(error, pendingWrites);
    }
    // 成功后才清理旧受管目录：只读目录先放开权限，失败只 WARN。
    for (const [, aside] of parked) if (aside) await forceRemove(aside, aside);
    if (watchUpdate) process.stdout.write("claude-mem：已登记 DSH transcript watch，worker 下次启动生效。\n");
    process.stdout.write(`DSH 已配置：${launcher}；数据目录 ${home}\n`);
  } finally {
    // 暂存树可能带进只读目录；清理用同一套放开目录权限的删除。
    await forceRemove(stage, stage);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { root: { type: "string" }, source: { type: "string" }, template: { type: "string" }, contextMode: { type: "string" }, magicContext: { type: "string" }, claudeMem: { type: "string" }, yes: { type: "boolean" } } });
  for (const key of ["root", "source", "template"]) if (!values[key]) throw new Error(`缺少 --${key}`);
  await deploy(values);
}
