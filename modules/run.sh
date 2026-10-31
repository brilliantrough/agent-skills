#!/usr/bin/env bash
# modules/run.sh — 可选模块的通用分发。
#
# 根 setup 只调本脚本，不再为了一个新能力去改四个 *-setup.sh。新增能力 = 加一个
# modules/<名>/ 目录，根脚本零改动。
#
# 用法: bash modules/run.sh --host pi|opencode|codex|dsh [--repo <owner/name>] [--ref <branch>]
#                             [--yes] [--list] [--only <名>]
#
# 模块契约（详见 modules/README.md）:
#   必须有 setup.sh，文件头用注释声明元数据:
#     # module: <名>
#     # desc:   <一句话说明，用于提问>
#     # default: N            ← 默认 N；写 Y 需要理由
#     # hosts:  any|pi,opencode,...
#   setup.sh 接收 --host <宿主>，自身不提问、幂等、只改自己负责的东西。
#   可选 AGENTS.block.md —— 仅当确实需要每轮注入时才写，默认不写。
set -euo pipefail

HOST=""
REPO="${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}"
REF="${AGENT_SKILLS_REF:-main}"
YES=0
LIST=0
ONLY=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --list) LIST=1; shift ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$HOST" ] || HOST="$(basename "$0" | sed 's/-setup\.sh$//')"

# ---- 模块目录：本地仓库优先；被下载到临时目录时拉一次 tarball ----
here="$(cd "$(dirname "$0")" && pwd)"
MDIR="$here"
cleanup=""
if ! compgen -G "$MDIR/*/setup.sh" >/dev/null; then
  tmp="$(mktemp -d)"; cleanup="$tmp"
  trap 'rm -rf "$cleanup"' EXIT
  curl -fsSL --connect-timeout 8 -m 120 "https://github.com/$REPO/archive/refs/heads/$REF.tar.gz" -o "$tmp/m.tgz" \
    || { echo "ERROR: 取不到模块目录（下载失败）" >&2; exit 1; }
  tar -xzf "$tmp/m.tgz" -C "$tmp" || { echo "ERROR: 解包失败" >&2; exit 1; }
  MDIR="$(echo "$tmp"/*/modules)"
  [ -d "$MDIR" ] || { echo "ERROR: 包内没有 modules/" >&2; exit 1; }
fi

meta() { sed -n "s/^# $2:[[:space:]]*//p" "$1" | head -1; }

ask_mod() {
  local q="$1" d="${2:-N}" a=""
  if [ "$YES" = 1 ]; then [ "$d" = Y ]; return $?; fi
  [ -t 0 ] || return 1
  printf '%s [%s] ' "$q" "$([ "$d" = Y ] && echo 'Y/n' || echo 'y/N')" >&2
  read -r a </dev/tty || a=""
  case "${a:-$d}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

if [ "$LIST" = 1 ]; then
  for d in "$MDIR"/*/; do
    [ -f "$d/setup.sh" ] || continue
    printf '%-24s %-4s %-10s %s\n' "$(meta "$d/setup.sh" module)" \
      "$(meta "$d/setup.sh" default)" "$(meta "$d/setup.sh" hosts)" "$(meta "$d/setup.sh" desc)"
  done
  exit 0
fi

ran=0; failed=0
for d in "$MDIR"/*/; do
  [ -f "$d/setup.sh" ] || continue
  name="$(meta "$d/setup.sh" module)"; name="${name:-$(basename "$d")}"
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
  hosts="$(meta "$d/setup.sh" hosts)"; hosts="${hosts:-any}"
  if [ "$hosts" != any ] && ! echo ",$hosts," | grep -q ",$HOST,"; then continue; fi
  desc="$(meta "$d/setup.sh" desc)"; desc="${desc:-模块 $name}"
  def="$(meta "$d/setup.sh" default)"; def="${def:-N}"
  ask_mod "安装 $name($desc)?" "$def" || continue
  echo "== 模块 $name =="
  bash "$d/setup.sh" --host "$HOST" || { echo "WARN: 模块 $name 未完成" >&2; failed=$((failed+1)); }
  ran=$((ran+1))
done

[ "$ran" = 0 ] && echo "模块: 本次没有选中任何模块"
[ "$failed" = 0 ] || exit 1
