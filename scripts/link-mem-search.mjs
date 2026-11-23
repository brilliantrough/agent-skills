// Expose the skill from the installed upstream package; do not vendor a second copy.
import { existsSync, mkdirSync, realpathSync, statSync, symlinkSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const [configDir, skillsDir] = process.argv.slice(2);
const source = resolve(configDir, 'plugins/marketplaces/thedotmack/plugin/skills/mem-search');
const dest = resolve(skillsDir, 'mem-search');
try {
  if (!statSync(resolve(source, 'SKILL.md'), { throwIfNoEntry: false })?.isFile()) {
    throw new Error(`官方 skill 缺失：${source}/SKILL.md，请核对 claude-mem 安装版本和 CLAUDE_CONFIG_DIR`);
  }
  mkdirSync(dirname(dest), { recursive: true });
  try {
    symlinkSync(source, dest, process.platform === 'win32' ? 'junction' : 'dir');
    console.log(`linked: ${dest}`);
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    if (!existsSync(dest) || realpathSync(dest) !== realpathSync(source)) {
      throw new Error(`保留同名或断开的 ${dest}；未接管，请核对来源`);
    }
    console.log(`unchanged: ${dest}`);
  }
} catch (e) {
  console.error(`ERROR: mem-search: ${e.message}`);
  process.exitCode = 1;
}
