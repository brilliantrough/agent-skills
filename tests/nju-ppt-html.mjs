// Run: NODE_DISABLE_COMPILE_CACHE=1 node tests/nju-ppt-html.mjs. No external engine, downloads or browser needed.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { args, prepareHtml, renameRuntime } from '../skills/ppt/nju-ppt/scripts/prepare_html.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const childEnv = { ...process.env, NODE_DISABLE_COMPILE_CACHE: '1' };
const skill = path.join(root, 'skills/ppt/nju-ppt');
const templates = JSON.parse(fs.readFileSync(path.join(skill, 'assets/html/templates.json'), 'utf8'));
assert.equal(templates.length, 11);
for (const template of templates) {
  assert.ok(template.fields.some(field => field.key === 'PAGE_TITLE'));
  assert.ok(!template.backgroundSvg.includes('{{'));
  assert.ok(template.backgroundSvg.includes('assets/nju/images/nju-logo.png'));
}
const parent = path.join(os.tmpdir(), 'opencode');
fs.mkdirSync(parent, { recursive: true });
const temp = fs.mkdtempSync(path.join(parent, 'nju-html-check-'));
try {
  const from = path.join(temp, 'staged'), to = path.join(temp, 'published');
  fs.mkdirSync(from);
  fs.writeFileSync(path.join(from, 'keep.txt'), 'runtime');
  const rename = fs.renameSync;
  let calls = 0;
  try {
    fs.renameSync = (...args) => {
      calls++;
      if (calls < 3) throw Object.assign(new Error('busy'), { code: 'EPERM' });
      return rename(...args);
    };
    if (process.platform === 'win32') {
      renameRuntime(from, to);
      assert.equal(calls, 3);
      assert.equal(fs.readFileSync(path.join(to, 'keep.txt'), 'utf8'), 'runtime');
    } else {
      assert.throws(() => renameRuntime(from, to), /busy/);
      assert.equal(calls, 1, 'Other platforms must not retry Windows errors');
    }
    for (const code of ['EPERM', 'EBUSY', 'EACCES']) {
      calls = 0;
      const error = Object.assign(new Error(code), { code });
      fs.renameSync = () => { calls++; throw error; };
      assert.throws(() => renameRuntime(from, to), caught => caught === error);
      assert.equal(calls, process.platform === 'win32' && code !== 'EACCES' ? 6 : 1);
    }
  } finally {
    fs.renameSync = rename;
  }
  assert.deepEqual(args(['--home', temp, '--install']), { home: temp, install: true });
  const dashi = path.join(temp, '.agents/skills/dashi-ppt');
  const source = path.join(dashi, 'project');
  assert.throws(() => prepareHtml({ dashi, home: temp }), /Dashi is missing/);
  fs.mkdirSync(source, { recursive: true });
  fs.writeFileSync(path.join(source, 'package.json'), JSON.stringify({ version: '0.4.14' }));
  const isolated = path.join(temp, 'html-cache');
  assert.throws(() => prepareHtml({ dashi, home: temp, workDir: isolated }), /dependencies are missing/);
  assert.equal(fs.existsSync(isolated), false, 'A check must not create an unusable cache');
  const envKeys = ["HOME", "USERPROFILE", "XDG_CACHE_HOME", "npm_config_cache", "npm_config_userconfig", "npm_config_update_notifier", "npm_config_offline", "npm_config_audit", "npm_config_fund"];
  const savedEnv = Object.fromEntries(envKeys.map(key => [key, process.env[key]]));
  Object.assign(process.env, {
    HOME: temp, USERPROFILE: temp, XDG_CACHE_HOME: path.join(temp, 'cache'),
    npm_config_cache: path.join(temp, 'npm-cache'), npm_config_userconfig: path.join(temp, 'empty.npmrc'),
    npm_config_update_notifier: 'false', npm_config_offline: 'true', npm_config_audit: 'false', npm_config_fund: 'false',
  });
  try {
    assert.throws(() => prepareHtml({ dashi, home: temp, workDir: isolated, install: true }), /ci|npm|ENOENT/);
    assert.equal(fs.existsSync(isolated), false, 'A failed install must be retryable');
    assert.ok(!fs.readdirSync(temp).some(name => name.startsWith('html-cache.new-')));
    assert.equal(fs.existsSync(path.join(source, 'node_modules')), false, 'Shared Dashi must stay unchanged');
  } finally {
    for (const key of envKeys) {
      if (savedEnv[key] === undefined) delete process.env[key];
      else process.env[key] = savedEnv[key];
    }
  }
  fs.writeFileSync(path.join(source, 'package.json'), JSON.stringify({ version: '0.4.15' }));
  assert.throws(() => prepareHtml({ dashi, home: temp, install: true }), /verified only with Dashi/);
  const fixture = JSON.parse(fs.readFileSync(path.join(skill, 'references/examples/html-pilot.json'), 'utf8'));
  const input = path.join(temp, 'input.json'), out = path.join(temp, 'out');
  function rejects(change, message) {
    const spec = structuredClone(fixture);
    change(spec);
    fs.writeFileSync(input, JSON.stringify(spec));
    const result = spawnSync(process.execPath, [path.join(skill, 'scripts/render_html.mjs'), '--input', input, '--out', out], { encoding: 'utf8', timeout: 10000, env: childEnv });
    assert.equal(result.status, 1, result.stdout);
    assert.match(result.stderr, message);
    assert.equal(fs.existsSync(out), false);
  }
  rejects(spec => { spec.slides[0].id = '../escape'; }, /Page id must/);
  rejects(spec => { spec.slides[1].id = 'cover'; }, /Duplicate page id/);
  rejects(spec => { spec.slides[0].fields.UNKNOWN = 'not a template field'; }, /Invalid text field/);
  rejects(spec => { spec.slides[2].chart.series[0].values[0] = null; }, /finite numeric values/);
  rejects(spec => { spec.slides[2].chart.categories.push('mismatch'); }, /aligned finite numeric values/);
  rejects(spec => { spec.slides[3].table.rows[0].push('extra'); }, /Invalid table row/);
  rejects(spec => { spec.slides.shift(); }, /exactly one cover/);
  fs.mkdirSync(out);
  fs.writeFileSync(path.join(out, 'user-edit.txt'), 'preserve me');
  fs.writeFileSync(input, JSON.stringify(fixture));
  const result = spawnSync(process.execPath, [path.join(skill, 'scripts/render_html.mjs'), '--input', input, '--out', out], { encoding: 'utf8', timeout: 10000, env: childEnv });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Output already exists/);
  assert.equal(fs.readFileSync(path.join(out, 'user-edit.txt'), 'utf8'), 'preserve me');
  console.log('PASS: 11 compiled layouts, unsafe IDs/duplicate IDs/unknown fields/data mismatches rejected, existing edits preserved');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
