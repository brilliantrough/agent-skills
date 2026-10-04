#!/usr/bin/env bash
# skills-sync.sh — agent-skills 的 skill 分组同步器(pi/opencode/codex 三个 setup 共用,也可单跑)
#
# 分组 = 仓库 skills/ 下的目录(base/ accel/ kb/):新增 skill 只需放入对应组目录,没有名单要维护。
# 策略:base 每次随仓库刷新(本地有未回流改动先备份);accel 缺才装(本机特化不覆盖);kb 每次刷新。
# 安装:整目录复制到 ~/.agents/skills/<名>;装了 Claude Code 的机器同步 ~/.claude/skills/<名>(有差异才写)。
# 备份:~/.local/share/agent-skills/.backups/<组>/<名>.bak-<时间戳>(回流仓库后自行删除)。
#
# 用法:skills-sync.sh [all|base]   all = 全部组;base = 仅基础组(个人工作站)
# 源:SKILLS_SRC 指定仓库 skills/ 目录;默认 ~/Linewrite/skills/agent-skills/skills;
#   没有则从 GitHub 拉 main tarball 到 ~/.cache/agent-skills-src(无需 git)。
set -euo pipefail

SCOPE="${1:-all}"
case "$SCOPE" in all) SYNC_GROUPS="base accel kb" ;; base) SYNC_GROUPS="base" ;; *) echo "用法: $0 [all|base]" >&2; exit 2 ;; esac

SRC="${SKILLS_SRC:-$HOME/Linewrite/skills/agent-skills/skills}"
if [ ! -d "$SRC" ]; then
  cache="$HOME/.cache/agent-skills-src"
  mkdir -p "$cache"
  echo "本地无仓库克隆,拉取 main tarball -> $cache"
  curl -fsSL --connect-timeout 10 -m 120 -o "$cache/src.tgz" \
    https://codeload.github.com/brilliantrough/agent-skills/tar.gz/refs/heads/main
  rm -rf "$cache/agent-skills-main"; tar -xzf "$cache/src.tgz" -C "$cache"; rm -f "$cache/src.tgz"
  SRC="$cache/agent-skills-main/skills"
fi
[ -d "$SRC" ] || { echo "ERROR: 找不到 skills 源目录 $SRC" >&2; exit 1; }

LIVE="$HOME/.agents/skills"
BACKUPS="$HOME/.local/share/agent-skills/.backups"
TS="$(date +%Y%m%d%H%M%S)"
N_INST=0; N_UPD=0; N_KEEP=0; N_SAME=0

# 漂移比对忽略行尾差异(Windows 工作副本 CRLF vs tarball/npx 安装的 LF;BSD diff 不支持时退回逐字节)
DIFF_RQ=(diff -rq)
if diff --strip-trailing-cr /dev/null /dev/null >/dev/null 2>&1; then DIFF_RQ=(diff -rq --strip-trailing-cr); fi

copy_sync() {  # 整目录替换(先建临时再换名;dest 是符号链接只删链接不递归)
  local src="$1" dest="$2" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.new-$$"; rm -rf "$tmp"
  cp -a "$src" "$tmp"
  if [ -L "$dest" ]; then rm -f "$dest"; else rm -rf "$dest"; fi
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
    base)  policy=refresh; bak=1 ;;
    accel) policy=missing; bak=0 ;;
    kb)    policy=refresh; bak=0 ;;
  esac
  [ -d "$SRC/$g" ] || continue
  echo "== $g 组($policy$([ "$bak" = 1 ] && echo ',漂移先备份')) =="
  for d in "$SRC/$g"/*/; do
    [ -f "$d/SKILL.md" ] && sync_one "$g" "$policy" "$bak" "$(basename "$d")"
  done
done

echo "== skills 同步完成:装 $N_INST,更新 $N_UPD,保留 $N_KEEP,未变 $N_SAME =="
