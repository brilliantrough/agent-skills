// bun tests/opencode-config-migration.mjs；先构建 opencode/release.mjs。
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, readdirSync, rmSync, symlinkSync, lstatSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { spawnSync } from "node:child_process";

const dir = mkdtempSync(join(existsSync("/tmp/opencode") ? "/tmp/opencode" : tmpdir(), "config-migration-"));
const script = resolve("opencode/dist/stage-v2/migrate-config.mjs");
const path = join(dir, "opencode.jsonc");
const input = {
  autoupdate: "notify", snapshot: false, compaction: { auto: false, prune: false },
  provider: { custom: { npm: "@ai-sdk/openai", options: { apiKey: "{env:PRIVATE_KEY}", baseURL: "https://private.example/v1", setCacheKey: true },
    models: { m: { options: { store: false }, variants: { high: { reasoningEffort: "high" } } } } } },
  agent: { explore: { model: "custom/m", tools: { write: false, read: true } } },
  permission: { "*": "ask", bash: { "git *": "allow", "git push *": "deny" } },
  mcp: { old: { type: "remote", url: "{env:MCP_URL}", enabled: false, timeout: 1234, oauth: { clientId: "id", clientSecret: "{file:key}" } },
    servers: { existing: { type: "local", command: ["node", "server.js"], disabled: true } } },
  plugin: [["custom-plugin", { secret: "sentinel" }]], skills: { paths: ["./skills"], urls: ["https://example.com/skills"] },
  unrelated: { keep: true },
};
const raw = "// keep in backup\n" + JSON.stringify(input);
const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
try {
  writeFileSync(path, raw);
  assert.equal(run(path).status, 0);
  assert.equal(readFileSync(path, "utf8"), raw);
  assert.equal(readdirSync(dir).length, 1);
  const applied = run("--apply", path);
  assert.equal(applied.status, 0, applied.stderr);
  const config = JSON.parse(readFileSync(path, "utf8"));
  assert.equal(config.providers.custom.settings.apiKey, "{env:PRIVATE_KEY}");
  assert.equal(config.providers.custom.settings.baseURL, input.provider.custom.options.baseURL);
  assert.equal(config.providers.custom.compatibility.supportsPromptCacheKey, true);
  assert.deepEqual(config.providers.custom.models.m.variants, [{ id: "high", settings: { reasoningEffort: "high" } }]);
  assert.deepEqual(config.permissions.map(r => [r.action, r.resource, r.effect]), [["*", "*", "ask"], ["shell", "git *", "allow"], ["shell", "git push *", "deny"]]);
  assert.equal(config.agents.explore.permissions[0].effect, "deny");
  assert.deepEqual(config.mcp.servers.old.timeout, { startup: 1234, catalog: 1234, execution: 1234 });
  assert.equal(config.mcp.servers.old.disabled, true);
  assert.equal(config.mcp.servers.old.oauth.client_secret, "{file:key}");
  assert.deepEqual(config.mcp.servers.existing, input.mcp.servers.existing);
  assert.deepEqual(config.plugins, [{ package: "custom-plugin", options: { secret: "sentinel" } }]);
  assert.deepEqual(config.unrelated, input.unrelated);
  assert.equal(config.update, "notify");
  assert.deepEqual(config.compaction, { auto: false });
  assert.equal(readFileSync(join(dir, readdirSync(dir).find(f => f.includes(".bak-v2-"))), "utf8"), raw);
  const first = readFileSync(path, "utf8"), count = readdirSync(dir).length;
  assert.equal(run("--apply", path).status, 0);
  assert.equal(readFileSync(path, "utf8"), first);
  assert.equal(readdirSync(dir).length, count);
  const invalid = join(dir, "bad.json");
  writeFileSync(invalid, '{"providers": {"broken": {"models": 3}}}');
  writeFileSync(path, raw);
  assert.notEqual(run("--apply", path, invalid).status, 0);
  assert.equal(readFileSync(path, "utf8"), raw);
  writeFileSync(invalid, '{"snapshot":false,"snapshots":true}');
  const conflict = readFileSync(invalid, "utf8");
  assert.notEqual(run("--apply", path, invalid).status, 0);
  assert.equal(readFileSync(invalid, "utf8"), conflict);
  assert.equal(readFileSync(path, "utf8"), raw);
  if (process.platform !== "win32") {
    const link = join(dir, "linked.json");
    symlinkSync(path, link);
    assert.equal(run("--apply", link).status, 0);
    assert.equal(lstatSync(link).isSymbolicLink(), true);
    assert.equal(JSON.parse(readFileSync(link, "utf8")).update, "notify");
  }
  console.log("PASS: 配置迁移预览、私密值/引用保留、权限顺序、MCP 混用、备份、幂等、错误不写入、链接写穿");
} finally { rmSync(dir, { recursive: true, force: true }); }
