#!/usr/bin/env bash
# 三套 setup 经 skills-sync.sh 调用；也可单跑。
# 三个设计依赖安装前询问；--ppt另补PPT引擎；--uninstall反安装设计依赖；--yes免询问。
# 第三方副本由上游管理；个人改动放回本仓 skill。同名本地/其他源保留并告警。
set -euo pipefail
with_ppt=0
command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1 || {
  echo "WARN: 缺少 Node/npx，外部 skill 未安装/更新" >&2; exit 1;
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
agents=(pi)
[ ! -d "$HOME/.claude" ] || agents+=(claude-code)
status=0

# 设计依赖：只这三个。redesign-existing-projects 已并入 design-taste-frontend，不再安装。
DESIGN_SKILLS="ui-ux-pro-max huashu-design design-taste-frontend"

ASSUME_YES=0; UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --ppt) with_ppt=1 ;;
    *) echo "用法: $0 [--ppt] [--yes] [--uninstall]" >&2; exit 2 ;;
  esac
done

uninstall_design_skills() {
  node - "$HOME" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const home = process.argv[2];
const names = ['ui-ux-pro-max', 'huashu-design', 'design-taste-frontend', 'redesign-existing-projects'];
const lockPath = path.join(home, '.agents', '.skill-lock.json');
const lock = fs.existsSync(lockPath) ? JSON.parse(fs.readFileSync(lockPath, 'utf8')) : {};
const skills = lock.skills || {};
let removed = 0;
for (const name of names) {
  let hit = false;
  for (const dir of [path.join(home, '.agents', 'skills', name), path.join(home, '.claude', 'skills', name)]) {
    if (fs.existsSync(dir)) { fs.rmSync(dir, { recursive: true, force: true }); hit = true; }
  }
  if (skills[name]) { delete skills[name]; hit = true; }
  if (hit) { console.log('removed: ' + name); removed++; }
}
if (removed && lock.skills) { lock.skills = skills; fs.writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n'); }
if (!removed) console.log('nothing to remove');
JS
}

# 上游已把 redesign-existing-projects 并进 design-taste-frontend。已装旧机器需清理，
# 否则它永远停在 ~/.agents/skills 里、继续误导路由。未登记的本地副本只提示不删。
migrate_obsolete_skills() {
  node - "$HOME" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const home = process.argv[2];
const name = 'redesign-existing-projects';
const lockPath = path.join(home, '.agents', '.skill-lock.json');
const lock = fs.existsSync(lockPath) ? JSON.parse(fs.readFileSync(lockPath, 'utf8')) : {};
const skills = lock.skills || {};
const dirs = [path.join(home, '.agents', 'skills', name), path.join(home, '.claude', 'skills', name)];
const present = dirs.some(d => fs.existsSync(d));
const entry = skills[name];
if (entry && (entry.source || '').includes('taste-skill')) {
  for (const d of dirs) if (fs.existsSync(d)) fs.rmSync(d, { recursive: true, force: true });
  delete skills[name];
  lock.skills = skills;
  fs.writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n');
  console.log('migrated: ' + name + ' 已并入 design-taste-frontend，旧副本已移除');
} else if (present) {
  console.log('NOTE: ' + name + ' 是未登记本地副本，保留；上游已移除该 skill，可手工删除');
}
JS
}

if [ "$UNINSTALL" = 1 ]; then
  uninstall_design_skills
  echo "外部设计依赖已清理；personal-ui-taste 降级为内置方法。重装：bash $ROOT/skills-external.sh --yes"
  exit 0
fi

migrate_obsolete_skills

# 非交互（管道、CI）默认安装，保持原行为；SKILLS_EXTERNAL=skip 只跳安装，不跳迁移。
with_design=1
if [ "${SKILLS_EXTERNAL:-install}" = skip ]; then
  echo "SKILLS_EXTERNAL=skip：跳过外部设计依赖安装"
  with_design=0
fi
if [ "$with_design" = 1 ] && [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
  printf '外部设计依赖（3 个）：%s\n' "$DESIGN_SKILLS"
  printf 'personal-ui-taste 按需引用；不装则降级为内置方法。安装/更新？[Y/n] '
  read -r ans || ans=y
  case "${ans:-y}" in
    [Nn]*) echo "已跳过设计依赖；稍后安装：bash $ROOT/skills-external.sh"; with_design=0 ;;
  esac
fi
[ "$with_design" = 1 ] || [ "$with_ppt" = 1 ] || exit 0

claude_safe() {
  local canonical="$HOME/.agents/skills/$1" mirror="$HOME/.claude/skills/$1"
  if [ -e "$mirror" ] && ! diff -rq "$canonical" "$mirror" >/dev/null 2>&1; then
    echo "WARN: Claude 同名副本 $1 与共享目录不同，保留并跳过；请先比较合并" >&2
    status=1; return 1
  fi
}

ensure_skill() {
  local repo="$1" name="$2" missing
  claude_safe "$name" || return 0
  if ! missing=$(node - "$repo" "$name" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const home = require('node:os').homedir();
const base = path.join(home, '.agents');
const lockPath = path.join(base, '.skill-lock.json');
const skills = fs.existsSync(lockPath) ? JSON.parse(fs.readFileSync(lockPath, 'utf8')).skills : {};
const [repo, name] = process.argv.slice(2);
const installed = fs.existsSync(path.join(base, 'skills', name, 'SKILL.md'));
const entry = skills[name];
if ((entry && entry.source !== repo) || (installed && !entry)) {
  console.error(`WARN: ${name} 来自 ${entry?.source || '未登记本地副本'}，保留；需要时手工确认 npx skills add ${repo} --skill ${name} -g -y`);
  process.exitCode = 1;
} else console.log(!installed || (fs.existsSync(path.join(home, '.claude')) &&
  !fs.existsSync(path.join(home, '.claude', 'skills', name, 'SKILL.md'))) ? 'missing' : 'present');
JS
  ); then status=1; return 0; fi
  if [ "$missing" = missing ]; then
    npx -y skills@latest add "$repo" --skill "$name" -g -y --agent "${agents[@]}" || status=1
  else
    echo "present: $name"
  fi
}

if [ "$with_design" = 1 ]; then
  ensure_skill nextlevelbuilder/ui-ux-pro-max-skill ui-ux-pro-max
  ensure_skill alchaincyf/huashu-design huashu-design
  ensure_skill Leonxlnx/taste-skill design-taste-frontend
fi
[ "$with_ppt" = 0 ] || ensure_skill hugohe3/ppt-master ppt-master

third=$(node - "$ROOT" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const lockPath = path.join(require('node:os').homedir(), '.agents', '.skill-lock.json');
const skills = fs.existsSync(lockPath) ? JSON.parse(fs.readFileSync(lockPath, 'utf8')).skills : {};
const mine = 'brilliantrough/agent-skills';
const own = new Set();
for (const group of ['base', 'research', 'accel', 'kb', 'ppt']) {
  const dir = path.join(process.argv[2], 'skills', group);
  if (!fs.existsSync(dir)) continue;
  for (const name of fs.readdirSync(dir)) if (fs.existsSync(path.join(dir, name, 'SKILL.md'))) own.add(name);
}
const expected = {
  'ui-ux-pro-max': 'nextlevelbuilder/ui-ux-pro-max-skill',
  'huashu-design': 'alchaincyf/huashu-design',
  'design-taste-frontend': 'Leonxlnx/taste-skill',
  'ppt-master': 'hugohe3/ppt-master'
};
// 上游已把它并入 design-taste-frontend；旧机器上的残留目录不进入更新列表。
const obsolete = new Set(['redesign-existing-projects']);
console.log(Object.entries(skills).filter(([name, e]) =>
  !own.has(name) && !obsolete.has(name) && !(e.source || '').includes(mine) && !(e.sourceUrl || '').includes(mine) &&
  (!expected[name] || e.source === expected[name])
).map(([name]) => name).join(' '));
JS
)
names=()
for name in $third; do
  if claude_safe "$name"; then names+=("$name"); fi
done
if [ "${#names[@]}" -gt 0 ]; then
  echo "更新检查沿用上游 CLI；网络检查错误以其原始输出为准，退出 0 不保证全部最新。"
  npx -y skills@latest update -g "${names[@]}" || status=1
fi
[ "$status" = 0 ] || echo "WARN: 外部 skill 未完全就绪，请检查上方输出后重跑" >&2
exit "$status"
