import assert from "node:assert/strict";
import { readFile, mkdtemp, mkdir, writeFile, rm, chmod } from "node:fs/promises";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

const root = resolve(".");
const read = (path) => readFile(join(root, path), "utf8");
const skill = await read("skills/base/verification/SKILL.md");
const contract = await read("skills/base/verification/references/reviewer.md");
assert.match(skill, /按风险委派/);
assert.match(skill, /具体验证方法以项目资料为准/);
assert.match(skill, /不预制通用测试矩阵/);
assert.match(skill, /verification-reviewer/);
assert.match(contract, /确认关键测试能因旧缺陷失败/);
assert.match(contract, /不报告简洁性/);

for (const path of [
  "templates/pi/agents/verification-reviewer.md",
  "templates/claude/agents/verification-reviewer.md",
  "templates/codex/agents/verification-reviewer.toml",
]) {
  const text = await read(path);
  assert.match(text, /verification\/references\/reviewer\.md/, path);
  assert.match(text, /不得联网/, path);
  assert.match(text, /不得写入仓库/, path);
}

const piAgent = await read("templates/pi/agents/verification-reviewer.md");
const claudeAgentTemplate = await read("templates/claude/agents/verification-reviewer.md");
assert.match(piAgent, /^tools: read, grep, find, ls, bash$/m);
assert.match(claudeAgentTemplate, /^tools: Read, Grep, Glob, Bash$/m);
assert.doesNotMatch(await read("templates/codex/agents/verification-reviewer.toml"), /^sandbox_mode\s*=/m);
assert.doesNotMatch(await read("templates/codex/agents/consolidation-reviewer.toml"), /^sandbox_mode\s*=/m);

const oc = JSON.parse(await read("templates/opencode/opencode.json"));
const agent = oc.agents["verification-reviewer"];
assert.equal(agent.mode, "subagent");
assert.equal(agent.model, "codex-newapi/gpt-6.2-sol#max");
assert.match(agent.system, /verification\/references\/reviewer\.md/);
assert.deepEqual(agent.permissions.map((rule) => [rule.action, rule.effect]), [
  ["read", "allow"], ["grep", "allow"], ["glob", "allow"], ["shell", "allow"],
  ["edit", "deny"], ["subagent", "deny"],
]);

const dshPatch = JSON.parse(await read("templates/dsh/cordis.patch.json"));
const preset = dshPatch.find((row) => row.id === "agent-skills-verification-reviewer");
const tool = dshPatch.find((row) => row.id === "tool-verification-review");
assert.equal(preset.config.id, "verification-reviewer");
assert.equal(preset.config.plugins[1].name, "agent-skills-dsh/verification-policy");
assert.equal(tool.config.toolName, "verification_review");
assert.equal(tool.config.agentPreset, "verification-reviewer");
assert.deepEqual(tool.config.allowedAgentPresets, ["verification-reviewer"]);
assert.equal(tool.config.agentOptions.model, "gpt-6.2-sol");
assert.match(await read("dsh/bundle.yml"), /tool-verification-review/);
const pkg = JSON.parse(await read("dsh/package.json"));
assert.equal(pkg.exports["./verification-policy"], "./verification-policy.mjs");

const restrictions = [];
const policy = await import(pathToFileURL(join(root, "dsh/verification-policy.mjs")).href);
policy.apply({ tools: { restrict: (rule) => restrictions.push(rule) } });
assert.equal(restrictions.length, 1);
const expectedShell = process.platform === "win32" ? "pwsh" : "bash";
const otherShell = process.platform === "win32" ? "bash" : "pwsh";
assert.ok(restrictions[0].allow.includes(expectedShell));
assert.ok(!restrictions[0].allow.includes(otherShell));
assert.ok(!restrictions[0].allow.includes("write"));
assert.ok(!restrictions[0].allow.includes("edit"));

assert.ok((await read("pi-setup.sh")).includes('"$AGENT_DIR/agents/verification-reviewer.md"'));
assert.match(await read("codex-setup.sh"), /for _role in consolidation-reviewer verification-reviewer/);
assert.match(await read("skills-sync.sh"), /verification-reviewer\) claude_skill=verification ;;/);
assert.match(await read("skills-sync.sh"), /for claude_role in consolidation-reviewer verification-reviewer/);
assert.match(await read("opencode-setup.sh"), /for role in \('consolidation-reviewer', 'verification-reviewer'\)/);
// 与 scripts/check.sh 第 4 节同一规则：路径变量拼接不能写成 /home/<x>/ 形态
assert.doesNotMatch(await read("scripts/verify-subagents.sh"), /\/home\/[a-z]+\//);

const tmp = await mkdtemp(join(tmpdir(), "verification-agent-"));
const run = (script, env = {}) => {
  const result = spawnSync("bash", [script], {
    env: { ...process.env, ROOT: root, WORK: tmp, ...env },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
};
const extract = (source, start, end) => {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from, `找不到生产部署段: ${start}`);
  return source.slice(from, to);
};
try {
  const claudeHome = join(tmp, "claude-home");
  await mkdir(join(claudeHome, ".claude"), { recursive: true });
  await mkdir(join(tmp, "live/consolidator"), { recursive: true });
  await mkdir(join(tmp, "live/verification"), { recursive: true });
  const claudeBlock = extract(await read("skills-sync.sh"),
    "# Claude Code 的两类独立审查代理;", 'echo "== 外部 skills:');
  const claudeHarness = join(tmp, "claude-deploy.sh");
  await writeFile(claudeHarness,
    "set -euo pipefail\nsource_root=\"$ROOT\"\nLIVE=\"$WORK/live\"\nHOME=\"$WORK/claude-home\"\n" + claudeBlock);
  run(claudeHarness, { TS: "first" });
  const claudeAgent = join(claudeHome, ".claude/agents/verification-reviewer.md");
  assert.equal(readFileSync(claudeAgent, "utf8"), await read("templates/claude/agents/verification-reviewer.md"));
  await writeFile(claudeAgent, "local\n");
  run(claudeHarness, { TS: "second" });
  assert.equal(readFileSync(claudeAgent, "utf8"), await read("templates/claude/agents/verification-reviewer.md"));
  assert.equal(readFileSync(`${claudeAgent}.bak-second`, "utf8"), "local\n");
  await rm(claudeAgent);
  await rm(join(tmp, "live/verification"), { recursive: true });
  run(claudeHarness, { TS: "third" });
  assert.equal(existsSync(claudeAgent), false, "verification skill 缺失时不得经 consolidator 目录安装角色");

  const codexBlock = extract(await read("codex-setup.sh"),
    'if [ "$PLAN_REVIEWER" = 1 ]; then', '_ss=');
  const codexHarness = join(tmp, "codex-deploy.sh");
  await writeFile(codexHarness,
    "set -euo pipefail\nPLAN_REVIEWER=1\nversion=\"${CODEX_VERSION:-0.158.0}\"\nCFG=\"$WORK/codex\"\nRAW=\"$ROOT/templates\"\n" +
    "rpath() { printf '%s' \"$1\"; }\nwarn() { printf 'WARN: %s\\n' \"$*\"; }\n" +
    "curl() { local out= url=; for url in \"$@\"; do :; done; while [ $# -gt 0 ]; do case \"$1\" in -o) out=\"$2\"; shift 2;; *) shift;; esac; done; cp \"$url\" \"$out\"; }\n" + codexBlock);
  const codexAgent = join(tmp, "codex/agents/verification-reviewer.toml");
  run(codexHarness, { CODEX_VERSION: "0.1.0" });
  assert.equal(existsSync(codexAgent), false, "低于 0.158.0 不得安装原生角色");
  run(codexHarness);
  assert.equal(readFileSync(codexAgent, "utf8"), await read("templates/codex/agents/verification-reviewer.toml"));
  await writeFile(codexAgent, "local = true\n");
  run(codexHarness);
  assert.equal(readFileSync(codexAgent, "utf8"), await read("templates/codex/agents/verification-reviewer.toml"));
  const backups = readdirSync(join(tmp, "codex/agents")).filter((name) => name.startsWith("verification-reviewer.toml.bak-"));
  assert.equal(backups.length, 1);
  assert.equal(readFileSync(join(tmp, "codex/agents", backups[0]), "utf8"), "local = true\n");

  const verifyHome = join(tmp, "verify-home");
  const verifyData = join(tmp, "verify-data");
  const verifyPi = join(verifyHome, ".pi/agent");
  const verifyEnv = {
    ...process.env,
    HOME: verifyHome,
    XDG_DATA_HOME: verifyData,
    PI_CODING_AGENT_DIR: verifyPi,
    CODEX_HOME: join(verifyHome, ".codex"),
    NODE_DISABLE_COMPILE_CACHE: "1",
  };
  const verifier = join(root, "scripts/verify-subagents.sh");
  const verify = () => spawnSync("bash", [verifier, "pi", "codex", "claude", "dsh"], { env: verifyEnv, encoding: "utf8" });
  const empty = verify();
  assert.equal(empty.status, 1, empty.stdout + empty.stderr);
  assert.match(empty.stderr, /漏装或漂移/);
  const unsafeApply = spawnSync("bash", [verifier, "--apply", "pi"], { env: verifyEnv, encoding: "utf8" });
  assert.equal(unsafeApply.status, 2, unsafeApply.stdout + unsafeApply.stderr);
  assert.match(unsafeApply.stderr, /--apply --yes/);
  for (const role of ["verification-reviewer", "consolidation-reviewer"]) {
    for (const [dir, file] of [
      [join(verifyPi, "agents"), `${role}.md`],
      [join(verifyHome, ".codex/agents"), `${role}.toml`],
      [join(verifyHome, ".claude/agents"), `${role}.md`],
    ]) {
      await mkdir(dir, { recursive: true });
      await writeFile(join(dir, file), "test\n");
    }
  }
  await writeFile(join(verifyPi, "models.json"), JSON.stringify({ providers: { "codex-newapi": { models: [{ id: "gpt-6.2-sol" }] } } }));
  const verifySkill = join(verifyHome, ".agents/skills/verification/references");
  await mkdir(verifySkill, { recursive: true });
  await writeFile(join(verifySkill, "reviewer.md"), "test\n");
  const dshRoot = join(verifyData, "agent-skills/dsh");
  for (const profile of ["headless", "web", "tui"]) {
    const dir = join(dshRoot, "home/profiles", profile);
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, "cordis.patch.yml"), "agent-skills-verification-reviewer\ntool-verification-review\nagent-skills-reviewer\n");
  }
  await mkdir(join(dshRoot, "runtime/bundle/dsh"), { recursive: true });
  await writeFile(join(dshRoot, "runtime/bundle/dsh/verification-policy.mjs"), "export {}\n");
  const installed = verify();
  assert.equal(installed.status, 0, installed.stdout + installed.stderr);
  assert.match(installed.stdout, /PASS：所选宿主/);
  assert.equal(spawnSync("bash", [verifier, "--yes"], { env: verifyEnv }).status, 2);

  // 默认只读检查必须与 live/项目隔离：不读项目级角色，也不把宿主状态写进真实 HOME
  const ocBin = join(tmp, "ocbin");
  const ocHome = join(tmp, "oc-home-iso");
  const ocCfg = join(tmp, "oc-cfg-iso");
  const ocProj = join(tmp, "oc-project");
  const ocRecord = join(tmp, "oc-record");
  await mkdir(ocBin, { recursive: true });
  await mkdir(join(ocProj, ".opencode/agent"), { recursive: true });
  await mkdir(ocCfg, { recursive: true });
  await mkdir(ocRecord, { recursive: true });
  await writeFile(join(ocProj, ".opencode/agent/verification-reviewer.md"), "---\nmode: subagent\n---\n");
  await writeFile(join(ocProj, ".opencode/agent/consolidation-reviewer.md"), "---\nmode: subagent\n---\n");
  await writeFile(join(ocBin, "opencode"), `#!/usr/bin/env bash
# 模拟宿主：状态目录取 XDG_STATE_HOME，缺省落 $HOME/.local/state；还会写全局配置目录
if [ -n "\${XDG_STATE_HOME:-}" ]; then state="$XDG_STATE_HOME/opencode"; else state="$HOME/.local/state/opencode"; fi
mkdir -p "$state" "$OPENCODE_CONFIG_DIR"
touch "$OPENCODE_CONFIG_DIR/.host-write"
printf '%s' "$PWD" > "${ocRecord}/pwd"
python3 - "$OPENCODE_CONFIG_DIR" "$PWD" <<'PY'
import glob, json, os, sys
cfg, pwd = sys.argv[1], sys.argv[2]
roles = set()
path = os.path.join(cfg, "opencode.json")
if os.path.exists(path):
    data = json.load(open(path, encoding="utf-8"))
    if set(data) - {"agents"}:
        sys.exit("临时配置混入非 agents 键：" + ",".join(sorted(set(data) - {"agents"})))
    roles |= set(data.get("agents") or {})
roles |= {os.path.basename(f)[:-3] for f in glob.glob(os.path.join(pwd, ".opencode/agent/*.md"))}
model = {"providerID": "codex-newapi", "id": "gpt-6.2-sol", "variant": "max"}
print(json.dumps([{"id": r, "mode": "subagent", "model": model} for r in sorted(roles)]))
PY
`);
  await chmod(join(ocBin, "opencode"), 0o755);
  await writeFile(join(ocCfg, "opencode.json"), JSON.stringify({ agents: {} }));
  // 调用方若导出了 live 的 XDG_STATE_HOME，检查也不能把宿主状态写进去
  const liveState = join(tmp, "oc-live-state");
  await mkdir(liveState, { recursive: true });
  const isoEnv = { ...verifyEnv, XDG_STATE_HOME: liveState };
  const isoRun = () => spawnSync("bash", [verifier, "opencode"], {
    cwd: ocProj, encoding: "utf8",
    env: { ...isoEnv, HOME: ocHome, OPENCODE_CONFIG_DIR: ocCfg, PATH: `${ocBin}:${process.env.PATH}` },
  });
  const projectOnly = isoRun();
  assert.equal(projectOnly.status, 1, projectOnly.stdout + projectOnly.stderr);
  assert.match(projectOnly.stderr, /opencode：未注册 verification-reviewer/);
  assert.notEqual(readFileSync(join(ocRecord, "pwd"), "utf8"), ocProj, "检查不得在调用处的项目目录内运行");
  assert.equal(existsSync(join(liveState, "opencode")), false, "宿主状态写进了调用方的 XDG_STATE_HOME");
  assert.equal(existsSync(join(ocCfg, ".host-write")), false, "宿主写入落在了全局配置目录");
  await writeFile(join(ocCfg, "opencode.json"), JSON.stringify({ agents: {
    "verification-reviewer": { mode: "subagent" }, "consolidation-reviewer": { mode: "subagent" },
  } }));
  const globalOnly = isoRun();
  assert.equal(globalOnly.status, 0, globalOnly.stdout + globalOnly.stderr);
  // live 配置可能是带注释的 JSONC；注释和尾逗号不能让检查误报“无法解析”
  await rm(join(ocCfg, "opencode.json"));
  await writeFile(join(ocCfg, "opencode.jsonc"),
    '{\n  // 全局角色\n  "theme": "x//y",\n  "agents": {\n    "verification-reviewer": { "mode": "subagent" },\n    "consolidation-reviewer": { "mode": "subagent" },\n  },\n}\n');
  const jsonc = isoRun();
  assert.equal(jsonc.status, 0, jsonc.stdout + jsonc.stderr);

  if (process.env.OPENCODE_TEST_BIN) {
    const configDir = join(tmp, "oc-config");
    await mkdir(configDir);
    await mkdir(join(tmp, "oc-home"));
    await writeFile(join(configDir, "opencode.json"), JSON.stringify({ agents: { "verification-reviewer": agent } }));
    const loaded = spawnSync(process.env.OPENCODE_TEST_BIN, ["--standalone", "debug", "agents"], {
      env: {
        ...process.env,
        HOME: join(tmp, "oc-home"),
        XDG_DATA_HOME: join(tmp, "oc-data"),
        XDG_CACHE_HOME: join(tmp, "oc-cache"),
        XDG_STATE_HOME: join(tmp, "oc-state"),
        OPENCODE_CONFIG_DIR: configDir,
        NODE_DISABLE_COMPILE_CACHE: "1",
      },
      encoding: "utf8",
      timeout: 30000,
    });
    assert.equal(loaded.status, 0, loaded.stdout + loaded.stderr);
    const native = JSON.parse(loaded.stdout).find((entry) => entry.id === "verification-reviewer");
    assert.ok(native, "OpenCode 原生 agents 列表必须包含 verification-reviewer");
    assert.equal(native.mode, "subagent");
    const nativeRules = new Set(native.permissions.map((rule) => `${rule.action}:${rule.effect}`));
    for (const rule of ["shell:allow", "edit:deny", "subagent:deny"]) assert.ok(nativeRules.has(rule), rule);
  } else {
    console.log("SKIP HOST: OpenCode 原生角色加载（设 OPENCODE_TEST_BIN=opencode）");
  }
} finally {
  await rm(tmp, { recursive: true, force: true });
}

console.log("PASS: verification-reviewer 规范、五宿主模板、执行权限与隔离部署循环");
