import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const SKILL = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REQUIRED_VERSION = '0.4.14';

export function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 120000, ...options });
  if (result.error || result.status !== 0) throw new Error(result.error?.message || result.stderr || result.stdout || `Command exited ${result.status}`);
  return result.stdout;
}

export function renameRuntime(source, target) {
  // Windows can briefly retain a directory handle after npm/tsx exits.
  for (let attempt = 0; ; attempt++) {
    try {
      fs.renameSync(source, target);
      return;
    } catch (error) {
      if (process.platform !== 'win32' || !['EPERM', 'EBUSY'].includes(error.code) || attempt === 5) throw error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100 * (attempt + 1));
    }
  }
}

export function prepareHtml({ dashi, home = os.homedir(), workDir, install = false } = {}) {
  if (Number(process.versions.node.split('.')[0]) < 20) throw new Error('HTML requires Node.js 20+');
  const source = path.resolve(dashi || process.env.DASHI_PPT_ROOT || path.join(home, '.agents/skills/dashi-ppt'));
  const project = path.join(source, 'project');
  if (!fs.existsSync(path.join(project, 'package.json'))) throw new Error('Dashi is missing; rerun setup and select the ppt group to install it.');
  const pkg = JSON.parse(fs.readFileSync(path.join(project, 'package.json'), 'utf8'));
  if (pkg.version !== REQUIRED_VERSION) throw new Error(`NJU HTML is verified only with Dashi ${REQUIRED_VERSION}; found ${pkg.version}. Do not patch an unverified version.`);
  const hash = createHash('sha256');
  function hashProject(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (['node_modules', 'output', '.git', '.npmrc'].includes(entry.name) || /^\.env(?:\.|$)|\.(?:pem|key)$/.test(entry.name)) continue;
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) hashProject(file);
      else if (entry.isFile()) hash.update(path.relative(project, file)).update(fs.readFileSync(file));
    }
  }
  hashProject(project);
  for (const file of ['assets/html/runtime.jsx', 'assets/html/templates.json', 'scripts/prepare_html.mjs']) hash.update(fs.readFileSync(path.join(SKILL, file)));
  const fingerprint = hash.digest('hex');
  const root = path.resolve(workDir || path.join(home, '.local/share/agent-skills/nju-ppt/html', fingerprint.slice(0, 16)));
  const target = path.join(root, 'project');
  const stamp = path.join(root, 'nju-runtime.json');
  if (fs.existsSync(stamp)) {
    const saved = JSON.parse(fs.readFileSync(stamp, 'utf8'));
    if (saved.fingerprint !== fingerprint) throw new Error('Runtime directory belongs to a different baseline; use a new --work-dir.');
    if (!fs.existsSync(path.join(target, 'node_modules/tsx/dist/cli.mjs'))) throw new Error('HTML runtime is incomplete; move the damaged cache aside and rerun setup with the ppt group.');
    return saved;
  }
  if (fs.existsSync(root) && fs.readdirSync(root).length) throw new Error('Runtime directory is not empty; choose a new --work-dir.');
  if (root === source || root.startsWith(source + path.sep)) throw new Error('Do not put the isolated runtime inside the installed Dashi skill.');
  if (!install && !fs.existsSync(path.join(project, 'node_modules/tsx/dist/cli.mjs'))) throw new Error('HTML dependencies are missing; rerun setup and select the ppt group.');
  fs.mkdirSync(path.dirname(root), { recursive: true });
  const staging = fs.mkdtempSync(root + '.new-');
  const stagedProject = path.join(staging, 'project');
  try {
    fs.cpSync(project, stagedProject, { recursive: true, filter: file => {
      const relative = path.relative(project, file).replaceAll('\\', '/');
      return path.basename(file) !== '.npmrc' && !/^\.env(?:\.|$)|\.(?:pem|key)$/.test(path.basename(file)) && !(install && relative === 'node_modules') && !['output', 'node_modules/.cache'].some(prefix => relative === prefix || relative.startsWith(prefix + '/'));
    } });
    if (install) {
      const command = process.platform === 'win32' ? 'cmd.exe' : 'npm';
      const parameters = process.platform === 'win32' ? ['/d', '/s', '/c', 'npm ci --include=dev --no-audit --no-fund'] : ['ci', '--include=dev', '--no-audit', '--no-fund'];
      process.stderr.write(run(command, parameters, { cwd: stagedProject, timeout: 180000 }));
    }
    const theme = path.join(stagedProject, 'src/components/themes/nju');
    fs.mkdirSync(theme);
    for (const file of ['runtime.jsx', 'templates.json']) fs.copyFileSync(path.join(SKILL, 'assets/html', file), path.join(theme, file));
    const tsx = path.join(stagedProject, 'node_modules/tsx/dist/cli.mjs');
    const metadata = run(process.execPath, [tsx, '-e', "import {pages} from './src/components/themes/nju/runtime.jsx';process.stdout.write(JSON.stringify(pages))"], { cwd: stagedProject });
    fs.writeFileSync(path.join(theme, 'metadata.json'), metadata);
    const manifestFile = path.join(stagedProject, 'layout-manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
    for (const page of JSON.parse(metadata)) manifest.layouts[page.key] = { dataLayout: page.layout };
    fs.writeFileSync(manifestFile, JSON.stringify(manifest));
    fs.appendFileSync(path.join(stagedProject, 'src/components/themes/generated-metadata.js'), `\nimport njuPages from './nju/metadata.json' with { type: 'json' };\nGENERATED_THEME_PAGES.push(...njuPages);\nGENERATED_THEME_PACKS.push({key:'nju',label:'南京大学银杏金',displayName:'南京大学银杏金',scenario:'学术汇报',audience:'研究者',pageCount:njuPages.length});\n`);
    patchFile(path.join(stagedProject, 'src/components/themes/theme-registry-codegen.mjs'), /export const ALL_THEME_KEYS = \[([\s\S]*?)\];/, (_, keys) => `export const ALL_THEME_KEYS = [${keys} 'nju',\n];`);
    patchFile(path.join(stagedProject, 'src/components/themes/theme-registry-codegen.mjs'), '  const keys = normalizeThemeKeys(themeKeys);', '  importPrefix = importPrefix.replaceAll(String.fromCharCode(92), "/");\n  const keys = normalizeThemeKeys(themeKeys);');
    patchFile(path.join(stagedProject, 'scripts/workflow/theme-registry.mjs'), "return /^theme\\d+_page00[1-5]$/.test(layout);", "return layout === 'nju_cover' || /^theme\\d+_page00[1-5]$/.test(layout);");
    const result = { version: REQUIRED_VERSION, fingerprint, dashi_root: source, project: target, node: process.execPath };
    fs.writeFileSync(path.join(staging, 'nju-runtime.json'), JSON.stringify(result, null, 2) + '\n');
    if (fs.existsSync(root)) fs.rmdirSync(root);
    renameRuntime(staging, root);
    return result;
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
}

function patchFile(file, pattern, replacement) {
  const text = fs.readFileSync(file, 'utf8');
  const next = text.replace(pattern, replacement);
  if (next === text) throw new Error(`Dashi integration contract changed: ${file}`);
  fs.writeFileSync(file, next);
}

export function args(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--install') { result.install = true; continue; }
    if (!argv[i].startsWith('--') || !argv[i + 1] || argv[i + 1].startsWith('--')) throw new Error('Arguments must be --name value pairs');
    result[argv[i].slice(2)] = argv[i + 1];
    i++;
  }
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const options = args(process.argv.slice(2));
    console.log(JSON.stringify(prepareHtml({ dashi: options.dashi, home: options.home, workDir: options['work-dir'], install: options.install }), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
