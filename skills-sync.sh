#!/usr/bin/env bash
# skills-sync.sh — agent-skills 的 skill 分组同步器(pi/opencode/codex 三个 setup 共用,也可单跑)
#
# 分组策略(名单只在 Groups一节维护,selfcheck 校验名单 ↔ skills/ 目录一致):
#   base  个人品味/流程类:每次随仓库刷新;本地有未回流改动先备份(<目录>.bak-<时间戳>)再覆盖
#   accel 算力平台模板类:缺才装,装后永不覆盖(本机特化即冻结)
#   kb    公共知识类:每次随仓库刷新,不备份(纯公共知识,无本机改动顾虑)
#
# 布局(符号链接可用时):实体在 ~/.local/share/agent-skills/<组>/<名>,
#   ~/.agents/skills/<名> 与 ~/.claude/skills/<名>(装了 Claude Code 才建)是指向实体的符号链接。
#   符号链接不可用的平台(部分 Windows)退化为实体直接落在 ~/.agents/skills/<名>。
#
# 用法:skills-sync.sh [all|base]   默认 all = base+accel+kb;base = 仅基础组(个人工作站)
# 源:环境变量 SKILLS_SRC 指定仓库 skills/ 目录;默认 ~/Linewrite/skills/agent-skills/skills;
#   都没有则从 GitHub 拉 main 分支 tarball 到 ~/.cache/agent-skills-src(无需 git)。
set -euo pipefail

# ---- Groups(名单唯一维护处;改动后跑 selfcheck)----
BASE_SKILLS="code-review diagnosing-bugs domain-modeling editable-vector-slides exp-batch exp-campaign exp-discuss exp-probe grilling load-mem migrate-mem personal-ui-taste plan-brief quick-do readable-docs save-mem steady-do tdd writing-skill"
ACCEL_SKILLS="accel-init accel-skill-template model-datasets accel-platform-install accel-pytorch-python accel-pytorch-code-porting platform-environment-skill-audit"
KNOWLEDGE_SKILLS="kb-accel-sdk"

SCOPE="${1:-all}"
case "$SCOPE" in all) SYNC_GROUPS="base accel kb" ;; base) SYNC_GROUPS="base" ;; *) echo "用法: $0 [all|base]" >&2; exit 2 ;; esac

# ---- 源定位 ----
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

MASTERS="$HOME/.local/share/agent-skills"
LIVE="$HOME/.agents/skills"
TS="$(date +%Y%m%d%H%M%S)"
N_INST=0; N_UPD=0; N_KEEP=0; N_SAME=0

# 漂移比对忽略行尾差异(Windows 工作副本 CRLF vs tarball/npx 安装的 LF;BSD diff 不支持时退回逐字节)
DIFF_RQ=(diff -rq)
if diff --strip-trailing-cr /dev/null /dev/null >/dev/null 2>&1; then DIFF_RQ=(diff -rq --strip-trailing-cr); fi

# 符号链接可用性(Git Bash 默认把 ln -s 退化为复制;先试 nativestrict 真链接,不行才判定不可用)
CAN_LN=0
_t="$(mktemp -d)"
if MSYS=winsymlinks:nativestrict ln -s "$_t" "$_t.lnk" 2>/dev/null && [ -L "$_t.lnk" ]; then CAN_LN=1; fi
rm -rf "$_t" "$_t.lnk"

mklink() { MSYS=winsymlinks:nativestrict ln -s "$1" "$2"; }

# copy_sync <src> <dest>:整目录替换(先建临时再换名,避免半截状态)
copy_sync() {
  local src="$1" dest="$2" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.new-$$"; rm -rf "$tmp"
  cp -a "$src" "$tmp"
  rm -rf "$dest"; mv "$tmp" "$dest"
}

# ensure_link <target> <link>:link 指向 target(已是正确符号链接则不动)
ensure_link() {
  local target="$1" link="$2"
  if [ -L "$link" ]; then
    [ "$(readlink "$link")" = "$target" ] && return 0
    rm -f "$link"
  elif [ -e "$link" ]; then
    rm -rf "$link"   # 内容已同步进实体,这里只替换入口
  fi
  mklink "$target" "$link"
}

sync_one() {  # $1=组 $2=策略(refresh|missing) $3=备份(1|0) $4=名
  local grp="$1" policy="$2" dobak="$3" s="$4"
  local src="$SRC/$s" master="$MASTERS/$grp/$s" live="$LIVE/$s" entity
  [ -d "$src" ] || { echo "WARN: 源里没有 $s,跳过" >&2; return 0; }

  if [ "$CAN_LN" = 1 ]; then
    mkdir -p "$MASTERS/$grp" "$LIVE"
    # 旧版直装实体迁移进 masters(内容优先保留,之后统一按策略跟仓库对齐)
    if [ -e "$live" ] && [ ! -L "$live" ]; then
      rm -rf "$master"; mv "$live" "$master"
    fi
    ensure_link "$master" "$live"
    entity="$master"
  else
    entity="$live"
  fi

  if [ ! -d "$entity" ] || [ -z "$(ls -A "$entity" 2>/dev/null)" ]; then
    copy_sync "$src" "$entity"; echo "installed: $grp/$s"; N_INST=$((N_INST+1))
  elif [ "$policy" = missing ]; then
    echo "kept: $grp/$s(缺才装组,不覆盖本机特化)"; N_KEEP=$((N_KEEP+1))
  elif "${DIFF_RQ[@]}" "$src" "$entity" >/dev/null 2>&1; then
    echo "unchanged: $grp/$s"; N_SAME=$((N_SAME+1))
  else
    if [ "$dobak" = 1 ]; then
      local bakdir="$MASTERS/.backups/$grp"
      mkdir -p "$bakdir"; cp -a "$entity" "$bakdir/$s.bak-$TS"
      echo "updated: $grp/$s(本地有未回流改动,已备份到 $bakdir/$s.bak-$TS;记得回流仓库)"
    else
      echo "updated: $grp/$s"
    fi
    copy_sync "$src" "$entity"; N_UPD=$((N_UPD+1))
  fi

  # Claude Code 入口(仅在该机装了 Claude Code 时维护)
  if [ -d "$HOME/.claude" ]; then
    mkdir -p "$HOME/.claude/skills"
    if [ "$CAN_LN" = 1 ]; then
      ensure_link "$entity" "$HOME/.claude/skills/$s"
    elif [ ! -e "$HOME/.claude/skills/$s" ] || ! "${DIFF_RQ[@]}" "$entity" "$HOME/.claude/skills/$s" >/dev/null 2>&1; then
      copy_sync "$entity" "$HOME/.claude/skills/$s"
    fi
  fi
}

for g in $SYNC_GROUPS; do
  case "$g" in
    base)  names="$BASE_SKILLS";  policy=refresh; bak=1 ;;
    accel) names="$ACCEL_SKILLS"; policy=missing; bak=0 ;;
    kb)    names="$KNOWLEDGE_SKILLS"; policy=refresh; bak=0 ;;
  esac
  echo "== $g 组($policy$([ "$bak" = 1 ] && echo ',漂移先备份')) =="
  for s in $names; do sync_one "$g" "$policy" "$bak" "$s"; done
done

echo "== skills 同步完成:装 $N_INST,更新 $N_UPD,保留 $N_KEEP,未变 $N_SAME =="
[ "$CAN_LN" = 1 ] || echo "(本平台符号链接不可用,实体直接落在 $LIVE)"
