#!/usr/bin/env bash
# skills-sync.sh — 本仓分组同步 + 外部依赖(pi/opencode/codex 三个 setup 共用,也可单跑)
#
# 分组 = 仓库 skills/ 下的目录(base/research/accel/kb/ppt):新增 skill 只需放入对应组目录。
# 策略:base/research/ppt 每次刷新且漂移先备份;accel 缺才装(本机特化不覆盖);kb 每次刷新、不备份。
# 安装:整目录复制到 ~/.agents/skills/<名>;装了 Claude Code 的机器同步 ~/.claude/skills/<名>(有差异才写)。
# 备份:~/.local/share/agent-skills/.backups/<组>/<名>.bak-<时间戳>(回流仓库后自行删除)。
#
# 用法:skills-sync.sh [all|base|research|accel|kb|ppt ...]
#       无参数/all = 全部组;可传多个组(例如 base research);setup 默认至少传 base。
# 源:从 GitHub 拉取 tarball 到 ~/.cache/agent-skills-src；默认main，分支验收可设AGENT_SKILLS_REF，Fork 验收可设AGENT_SKILLS_REPO。
set -euo pipefail

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

ref="${AGENT_SKILLS_REF:-main}"
repo="${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}"
cache="$HOME/.cache/agent-skills-src"
mkdir -p "$cache"
echo "拉取 GitHub $ref tarball -> $cache"
curl -fsSL --connect-timeout 10 -m 120 -o "$cache/src.tgz" \
  "https://codeload.github.com/$repo/tar.gz/refs/heads/$ref"
source_root="$cache/agent-skills-source"
rm -rf "$source_root"; mkdir -p "$source_root"
tar -xzf "$cache/src.tgz" --strip-components=1 -C "$source_root"; rm -f "$cache/src.tgz"
SRC="$source_root/skills"
[ -d "$SRC" ] || { echo "ERROR: 源目录不完整 $SRC" >&2; exit 1; }
with_ppt=0
case " $SYNC_GROUPS " in
  *" ppt "*)
    [ -f "$SRC/ppt/nju-ppt/scripts/prepare.py" ] || {
      echo "ERROR: 下载的 $ref 尚不包含完整 ppt 组；不要用旧版或仅有 SKILL.md 的副本冒充安装成功" >&2; exit 1;
    }
    with_ppt=1 ;;
esac

LIVE="$HOME/.agents/skills"
BACKUPS="$HOME/.local/share/agent-skills/.backups"
TS="$(date +%Y%m%d%H%M%S)"
N_INST=0; N_UPD=0; N_KEEP=0; N_SAME=0

# 漂移比对忽略行尾差异(历史 CRLF 安装 vs tarball 的 LF;BSD diff 不支持时退回逐字节)
DIFF_RQ=(diff -rq)
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
  # Claude Code 入口(仅该机装了 Claude Code 时维护;有差异才写)
  if [ -d "$HOME/.claude" ]; then
    mkdir -p "$HOME/.claude/skills"
    if [ ! -e "$HOME/.claude/skills/$s" ] || ! "${DIFF_RQ[@]}" "$live" "$HOME/.claude/skills/$s" >/dev/null 2>&1; then
      copy_sync "$live" "$HOME/.claude/skills/$s"
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
exit "$status"
