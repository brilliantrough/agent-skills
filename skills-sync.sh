#!/usr/bin/env bash
# skills-sync.sh — 本仓分组同步 + 外部依赖(pi/opencode/codex 三个 setup 共用,也可单跑)
#
# 分组 = 仓库 skills/ 下的目录(base/research/accel/kb/ppt):新增 skill 只需放入对应组目录。
# 策略:base/research/ppt 每次刷新且漂移先备份;accel 缺才装(本机特化不覆盖);kb 每次刷新、不备份。
# 安装:整目录复制到 ~/.agents/skills/<名>;装了 Claude Code 的机器在 ~/.claude/skills/<名> 建指向它的符号链接
#       (Claude Code 不读 ~/.agents/skills,但跟随逐个 skill 的链接;Git Bash 无真链接时退回复制),并部署审查代理。
# 备份:~/.local/share/agent-skills/.backups/<组>/<名>.bak-<时间戳>(回流仓库后自行删除)。
#
# 用法:skills-sync.sh [--antigravity] [all|base|research|accel|kb|ppt ...]
# --antigravity 将共享目录登记到宿主原生发现清单；公共规则仍由 AGENTS_TAIL 控制。
#       无参数/all = 全部组;可传多个组(例如 base research);setup 默认至少传 base。
# 源:与四个 setup 共用一棵本地源码树(默认受管 clone,见 acquire_source);
#     AGENT_SKILLS_SOURCE 指向已有工作树时只读使用;分支/Fork 验收仍用 AGENT_SKILLS_REF / AGENT_SKILLS_REPO。
set -euo pipefail

antigravity=0
if [ "${1:-}" = --antigravity ]; then antigravity=1; shift; fi

SCOPE_ARGS=("$@")
[ "${#SCOPE_ARGS[@]}" -gt 0 ] || SCOPE_ARGS=(all)
SYNC_GROUPS=""
add_group() {
  case " $SYNC_GROUPS " in *" $1 "*) return ;; esac
  SYNC_GROUPS="${SYNC_GROUPS:+$SYNC_GROUPS }$1"
}
if [ "${#SCOPE_ARGS[@]}" = 1 ] && [ "${SCOPE_ARGS[0]}" = all ]; then
  SYNC_GROUPS="base research accel kb ppt"
else
  for scope in "${SCOPE_ARGS[@]}"; do
    case "$scope" in
      base|research|accel|kb|ppt) add_group "$scope" ;;
      all) echo "用法: $0 [all|base|research|accel|kb|ppt ...](all 不能与其他组混用)" >&2; exit 2 ;;
      *) echo "用法: $0 [all|base|research|accel|kb|ppt ...]" >&2; exit 2 ;;
    esac
  done
fi

# ---- 开始即收集本脚本的全部选择；根 setup 可用环境变量预答，后续不再提问 ----
if [ -z "${AGENTS_TAIL+x}" ]; then
  AGENTS_TAIL=1
  if [ "${ASSUME_YES:-0}" != 1 ] && { : </dev/tty; } 2>/dev/null; then
    printf '同步公共规则到本账号已安装宿主的用户级指令文件？[Y/n] '
    read -r sync_answer </dev/tty || sync_answer=""
    case "${sync_answer:-Y}" in [Nn]*) AGENTS_TAIL=0 ;; esac
  fi
fi
if [ -z "${SKILLS_EXTERNAL+x}" ]; then
  SKILLS_EXTERNAL=install
  if [ "${ASSUME_YES:-0}" != 1 ] && { : </dev/tty; } 2>/dev/null; then
    printf '安装/更新 3 个外部设计依赖? [Y/n] '
    read -r sync_answer </dev/tty || sync_answer=""
    case "${sync_answer:-Y}" in [Nn]*) SKILLS_EXTERNAL=skip ;; esac
  fi
fi
export AGENTS_TAIL SKILLS_EXTERNAL

ref="${AGENT_SKILLS_REF:-main}"
repo="${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}"
# ---- 源码基准:模板、skills 与模块都从一棵本地源码树取,不再逐个下载 GitHub raw ----
# 默认复用/更新受管 clone($XDG_DATA_HOME/agent-skills/source),与开发副本分开;
# AGENT_SKILLS_SOURCE 显式指向已有工作树时只读使用(不 pull、不修改),便于候选安装。
# 更新失败但已有克隆时 WARN 后继续并报出所用 commit,不把陈旧克隆静默当成最新。
SELF_RAW=""; RAW=""
file_url() { # 绝对路径 → file:// URL:空格/#/?/%/[/] 必须转义,其余(含 UTF-8)原样保留
  local p="$1" prefix="file://" out="" c i
  if [ "${IS_WIN:-0}" = 1 ] && command -v cygpath >/dev/null 2>&1; then
    p="$(cygpath -m "$p")"; prefix="file:///"
  fi
  for ((i = 0; i < ${#p}; i++)); do
    c="${p:i:1}"
    case "$c" in
      ' ') out="$out%20" ;;
      '#'|'?'|'%'|'['|']') out="$out$(printf '%%%02X' "'$c")" ;;
      *) out="$out$c" ;;
    esac
  done
  printf '%s%s' "$prefix" "$out"
}

acquire_source() {
  local root repo repo_url ref commit updated=0 created=0
  repo="${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}"
  ref="${AGENT_SKILLS_REF:-main}"
  root="${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/source"
  if [ -n "${AGENT_SKILLS_SOURCE:-}" ]; then
    root="$AGENT_SKILLS_SOURCE"
    [ -d "$root/skills" ] && [ -d "$root/templates" ] || {
      echo "ERROR: AGENT_SKILLS_SOURCE=$root 不是本仓工作树(缺 skills/ 或 templates/)" >&2; return 1; }
    root="$(cd "$root" && pwd)"
    echo "源: $root(显式 AGENT_SKILLS_SOURCE,只读)"
  else
    command -v git >/dev/null 2>&1 || {
      echo "ERROR: 需要 git 维护源码基准 $root;或设 AGENT_SKILLS_SOURCE 指向已有本仓工作树" >&2; return 1; }
    if [ ! -d "$root/.git" ]; then
      echo "首次克隆 $repo@$ref -> $root"
      [ -d "$root" ] || created=1
      mkdir -p "$root" && git -C "$root" init -q || return 1
    fi
    # AGENT_SKILLS_REPO 既可是 owner/name,也可是可克隆 URL(file:///path、https://…)
    case "$repo" in
      *://*|/*|.*) repo_url="$repo" ;;
      *) repo_url="https://github.com/$repo.git" ;;
    esac
    if ! git -C "$root" remote set-url origin "$repo_url" 2>/dev/null; then
      git -C "$root" remote add origin "$repo_url" || return 1
    fi
    if git -C "$root" fetch --depth 1 -q origin "$ref" 2>/dev/null \
      && git -C "$root" checkout -q --force --detach FETCH_HEAD 2>/dev/null; then
      updated=1
    fi
    commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)"
    if [ "$updated" != 1 ]; then
      [ -n "$commit" ] || {
        [ "$created" != 1 ] || rm -rf "$root"
        echo "ERROR: 取不到源码 $repo@$ref,且 $root 没有可用副本;检查代理/git,或设 AGENT_SKILLS_SOURCE" >&2; return 1; }
      echo "WARN: 更新 $repo@$ref 失败,继续用已有克隆 $commit(可能不是最新)" >&2
    fi
    echo "源: $root($repo@$ref,$commit)"
  fi
  [ -d "$root/skills" ] && [ -d "$root/templates" ] || {
    echo "ERROR: 源码基准 $root 缺 skills/ 或 templates/" >&2; return 1; }
  SOURCE_ROOT="$root"
  SELF_RAW="$(file_url "$root")"
  RAW="$SELF_RAW/templates"
  # 子脚本(modules/run.sh、skills-sync.sh)复用同一棵树,不二次克隆
  export SOURCE_ROOT SELF_RAW RAW AGENT_SKILLS_SOURCE="$root"
}

acquire_source || exit 1
source_root="$SOURCE_ROOT"
SRC="$source_root/skills"
[ -d "$SRC" ] || { echo "ERROR: 源目录不完整 $SRC" >&2; exit 1; }
with_ppt=0
case " $SYNC_GROUPS " in
  *" ppt "*)
    [ -f "$SRC/ppt/nju-ppt/scripts/prepare.py" ] && [ -f "$SRC/ppt/nju-ppt/scripts/prepare_html.mjs" ] || {
      echo "ERROR: $ref 源码树尚不包含完整 ppt 组；不要用旧版或仅有 SKILL.md 的副本冒充安装成功" >&2; exit 1;
    }
    with_ppt=1 ;;
esac

LIVE="$HOME/.agents/skills"
BACKUPS="$HOME/.local/share/agent-skills/.backups"
TS="$(date +%Y%m%d%H%M%S)"
N_INST=0; N_UPD=0; N_KEEP=0; N_SAME=0

# 漂移比对忽略行尾差异(历史 CRLF 安装 vs tarball 的 LF;BSD diff 不支持时退回逐字节)
DIFF_RQ=(diff -rq)
# Git Bash 的 ln -s 默认是拷贝,不当作链接用
CAN_LINK=1
case "$(uname -s 2>/dev/null || true)" in MINGW*|MSYS*|CYGWIN*) CAN_LINK=0 ;; esac
if diff --strip-trailing-cr /dev/null /dev/null >/dev/null 2>&1; then DIFF_RQ=(diff -rq --strip-trailing-cr); fi

copy_sync() {  # 整目录替换(先建临时再换名,避免半拷状态)
  local src="$1" dest="$2" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.new-$$"; rm -rf "$tmp"
  cp -a "$src" "$tmp"
  rm -rf "$dest"
  mv "$tmp" "$dest"
}

sync_one() {  # $1=组 $2=策略(refresh|missing) $3=备份(1|0) $4=名
  local grp="$1" policy="$2" dobak="$3" s="$4"
  local src="$SRC/$grp/$s" live="$LIVE/$s"
  if [ ! -d "$live" ]; then
    copy_sync "$src" "$live"; echo "installed: $grp/$s"; N_INST=$((N_INST+1))
  elif [ "$policy" = missing ]; then
    echo "kept: $grp/$s(缺才装组,不覆盖本机特化)"; N_KEEP=$((N_KEEP+1))
  elif "${DIFF_RQ[@]}" "$src" "$live" >/dev/null 2>&1; then
    echo "unchanged: $grp/$s"; N_SAME=$((N_SAME+1))
  else
    if [ "$dobak" = 1 ]; then
      mkdir -p "$BACKUPS/$grp"; cp -a "$live" "$BACKUPS/$grp/$s.bak-$TS"
      echo "updated: $grp/$s(本地有未回流改动,已备份到 $BACKUPS/$grp/$s.bak-$TS;记得回流仓库)"
    else
      echo "updated: $grp/$s"
    fi
    copy_sync "$src" "$live"; N_UPD=$((N_UPD+1))
  fi
  # Claude Code 入口(仅该机装了 Claude Code 时维护):链接到共享目录,只留一份实体
  if [ -d "$HOME/.claude" ]; then
    local mirror="$HOME/.claude/skills/$s"
    mkdir -p "$HOME/.claude/skills"
    if [ "$mirror" -ef "$live" ]; then :
    elif [ "$CAN_LINK" = 1 ]; then
      rm -rf "$mirror"; ln -s "../../.agents/skills/$s" "$mirror"; echo "linked: ~/.claude/skills/$s"
    elif [ ! -e "$mirror" ] || ! "${DIFF_RQ[@]}" "$live" "$mirror" >/dev/null 2>&1; then
      copy_sync "$live" "$mirror"
    fi
  fi
}

for g in $SYNC_GROUPS; do
  case "$g" in
    base|research|ppt) policy=refresh; bak=1 ;;
    accel) policy=missing; bak=0 ;;
    kb)    policy=refresh; bak=0 ;;
  esac
  [ -d "$SRC/$g" ] || continue
  echo "== $g 组($policy$([ "$bak" = 1 ] && echo ',漂移先备份')) =="
  for d in "$SRC/$g"/*/; do
    [ -f "$d/SKILL.md" ] && sync_one "$g" "$policy" "$bak" "$(basename "$d")"
  done
done

echo "== 本仓 skills 同步完成:装 $N_INST,更新 $N_UPD,保留 $N_KEEP,未变 $N_SAME =="

# Claude Code 的两类独立审查代理;有差异先备份再写,链接写入目标
for claude_role in consolidation-reviewer verification-reviewer; do
  case "$claude_role" in
    consolidation-reviewer) claude_skill=consolidator ;;
    verification-reviewer) claude_skill=verification ;;
  esac
  claude_agent_src="$source_root/templates/claude/agents/$claude_role.md"
  claude_agent="$HOME/.claude/agents/$claude_role.md"
  if [ -d "$HOME/.claude" ] && [ -d "$LIVE/$claude_skill" ] && [ -f "$claude_agent_src" ]; then
    if [ -f "$claude_agent" ] && cmp -s "$claude_agent_src" "$claude_agent"; then
      echo "unchanged: $claude_agent"
    else
      mkdir -p "$HOME/.claude/agents"
      [ ! -f "$claude_agent" ] || cp -p "$claude_agent" "$claude_agent.bak-$TS"
      cat "$claude_agent_src" > "$claude_agent"; echo "wrote: $claude_agent"
    fi
  fi
done
echo "== 外部 skills:设计依赖(询问后安装)、PPT引擎(按组) + 更新已登记第三方(不含本仓) =="
status=0
if [ "$with_ppt" = 1 ]; then
  bash "$source_root/skills-external.sh" --ppt || status=1
else
  bash "$source_root/skills-external.sh" || status=1
fi

prepare_ppt() {
  local candidate home_native script_native
  local py=()
  if [ -n "${NJU_PPT_PYTHON:-}" ]; then
    py=("$NJU_PPT_PYTHON")
  else
    for candidate in python3 python py; do
      command -v "$candidate" >/dev/null 2>&1 || continue
      py=("$candidate"); [ "$candidate" != py ] || py+=(-3)
      if "${py[@]}" -c 'import sys; sys.exit(sys.version_info < (3,10))' >/dev/null 2>&1; then break; fi
      py=()
    done
  fi
  if [ "${#py[@]}" = 0 ] || ! "${py[@]}" -c 'import sys; sys.exit(sys.version_info < (3,10))' >/dev/null 2>&1; then
    echo "ERROR: ppt 文件已同步，但缺 Python 3.10+；安装后可设 NJU_PPT_PYTHON 再重跑" >&2; return 1
  fi
  home_native="$HOME"; script_native="$LIVE/nju-ppt/scripts/prepare.py"
  if command -v cygpath >/dev/null 2>&1; then
    home_native="$(cygpath -w "$home_native")"; script_native="$(cygpath -w "$script_native")"
  fi
  echo "== ppt: 准备独立 Python 环境与核心依赖(不修改系统 Python) =="
  "${py[@]}" "$script_native" --home "$home_native" --install
}

if [ "$with_ppt" = 1 ]; then prepare_ppt || status=1; fi

if [ "$with_ppt" = 1 ]; then
  echo "== ppt: 准备独立 HTML 环境与 Node 依赖（不修改共享 Dashi） =="
  home_native="$HOME"; html_script="$LIVE/nju-ppt/scripts/prepare_html.mjs"
  if command -v cygpath >/dev/null 2>&1; then
    home_native="$(cygpath -w "$home_native")"; html_script="$(cygpath -w "$html_script")"
  fi
  node "$html_script" --home "$home_native" --install || status=1
fi

inject_agents_md() {
  [ "$AGENTS_TAIL" = 1 ] || return 0
  python3 "$source_root/scripts/migrate-agents-tail.py" --sync-global
}
if [ "$antigravity" = 1 ]; then
  python3 "$source_root/scripts/migrate-agents-tail.py" --antigravity-skills || exit 1
  export AGENTS_TAIL_HOST=antigravity
fi
inject_agents_md || status=1

exit "$status"
