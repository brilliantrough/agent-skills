#!/usr/bin/env bash
# modules/run.sh — 可选模块的通用分发。
#
# 根 setup 只调本脚本，不再为了一个新能力去改四个 *-setup.sh。新增能力 = 加一个
# modules/<名>/ 目录，根脚本零改动。
#
# 用法: bash modules/run.sh --host pi|opencode|codex|dsh [--repo <owner/name>] [--ref <branch>]
#                             [--yes] [--list] [--only <名>] [--select | --selected <名单>]
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
HOST_EXPLICIT=0
REPO="${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}"
REF="${AGENT_SKILLS_REF:-main}"
YES=0
LIST=0
ONLY=""
SELECT=0
SELECTED=""
SELECTED_SET=0
MODULE_PREF_SET=0
declare -p AGENT_SKILLS_MODULE_SELECTION >/dev/null 2>&1 && MODULE_PREF_SET=1
: "${AGENT_SKILLS_MODULE_SELECTION:=}"
: "${AGENT_SKILLS_MODULE_KNOWN:=}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; HOST_EXPLICIT=1; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --list) LIST=1; shift ;;
    --select) SELECT=1; shift ;;
    --selected) SELECTED="${2:-}"; SELECTED_SET=1; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$HOST" ] || HOST="$(basename "$0" | sed 's/-setup\.sh$//')"

# ---- 模块目录：只从本脚本所在源码树读取(--repo/--ref 保留兼容,不再下载) ----
here="$(cd "$(dirname "$0")" && pwd)"
MDIR="$here"

meta() { sed -n "s/^# $2:[[:space:]]*//p" "$1" | head -1; }

ask_mod() {
  local q="$1" d="${2:-N}" a=""
  if [ "$YES" = 1 ]; then [ "$d" = Y ]; return $?; fi
  if { : </dev/tty; } 2>/dev/null; then
    printf '%s [%s] ' "$q" "$([ "$d" = Y ] && echo 'Y/n' || echo 'y/N')" >&2
    read -r a </dev/tty || a=""
    case "${a:-$d}" in [Yy]*) return 0 ;; *) return 1 ;; esac
  else
    [ "$d" = Y ]  # 无控制终端与 -y 一样取默认值，不在执行阶段补问。
  fi
}

if [ "$LIST" = 1 ]; then
  for d in "$MDIR"/*/; do
    [ -f "$d/setup.sh" ] || continue
    name="$(meta "$d/setup.sh" module)"; name="${name:-$(basename "$d")}"
    hosts="$(meta "$d/setup.sh" hosts)"; hosts="${hosts:-any}"
    if [ "$HOST_EXPLICIT" = 1 ] && [ "$hosts" != any ] && ! echo ",$hosts," | grep -q ",$HOST,"; then continue; fi
    printf '%-24s %-4s %-10s %s\n' "$name" \
      "$(meta "$d/setup.sh" default)" "$(meta "$d/setup.sh" hosts)" "$(meta "$d/setup.sh" desc)"
  done
  exit 0
fi

ran=0; failed=0
selection="$SELECTED"
if [ "$SELECTED_SET" = 0 ]; then
  # 先问完全部模块，再执行；根 setup 的 --select 阶段在这里只输出名单，不安装。
  selection=""
  for d in "$MDIR"/*/; do
    [ -f "$d/setup.sh" ] || continue
    name="$(meta "$d/setup.sh" module)"; name="${name:-$(basename "$d")}"
    [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
    hosts="$(meta "$d/setup.sh" hosts)"; hosts="${hosts:-any}"
    if [ "$hosts" != any ] && ! echo ",$hosts," | grep -q ",$HOST,"; then continue; fi
    desc="$(meta "$d/setup.sh" desc)"; desc="${desc:-模块 $name}"
    def="$(meta "$d/setup.sh" default)"; def="${def:-N}"
    if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ] && [ "$hosts" = any ]; then
      # 父入口已问过本机共用模块；把选择保留在宿主偏好里，单独重跑时仍生效。
      case ",${AGENT_SKILLS_SHARED_MODULES:-}," in *,"$name",*) selection="${selection:+$selection$'\n'}$name" ;; esac
      continue
    fi
    if [ "$MODULE_PREF_SET" = 1 ]; then
      # 已选名单保持原样；上次未见过的模块才按当前默认值决定，交互模式只问这些新项。
      if echo ",${AGENT_SKILLS_MODULE_SELECTION:-}," | grep -q ",$name,"; then
        selection="${selection:+$selection$'\n'}$name"
      elif ! echo ",${AGENT_SKILLS_MODULE_KNOWN:-}," | grep -q ",$name,"; then
        if ask_mod "安装 $name($desc)?" "$def"; then selection="${selection:+$selection$'\n'}$name"; fi
      fi
    elif ask_mod "安装 $name($desc)?" "$def"; then
      selection="${selection:+$selection$'\n'}$name"
    fi
  done
fi
if [ "$SELECT" = 1 ]; then
  [ -z "$selection" ] || printf '%s\n' "$selection"
  exit 0
fi
for d in "$MDIR"/*/; do
  [ -f "$d/setup.sh" ] || continue
  name="$(meta "$d/setup.sh" module)"; name="${name:-$(basename "$d")}"
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
  hosts="$(meta "$d/setup.sh" hosts)"; hosts="${hosts:-any}"
  if [ "$hosts" != any ] && ! echo ",$hosts," | grep -q ",$HOST,"; then continue; fi
  [[ $'\n'$selection$'\n' == *$'\n'"$name"$'\n'* ]] || continue
  if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ] && [ "$hosts" = any ]; then continue; fi
  desc="$(meta "$d/setup.sh" desc)"; desc="${desc:-模块 $name}"
  echo "== 模块 $name =="
  bash "$d/setup.sh" --host "$HOST" || { echo "WARN: 模块 $name 未完成" >&2; failed=$((failed+1)); }
  ran=$((ran+1))
done

[ "$ran" = 0 ] && echo "模块: 本次没有选中任何模块"
[ "$failed" = 0 ] || exit 1
