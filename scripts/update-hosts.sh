#!/usr/bin/env bash
# setup.sh 已固定本次源码版本；借用现有前置选择，不启动 DSH。
set -euo pipefail
root="${SOURCE_ROOT:?请通过 setup.sh 启动}"
source "$root/dsh-setup.sh"
YES=0; CHOOSE=0; hosts_arg=''; explicit=0; flags=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --hosts) [ "$#" -ge 2 ] || { echo '缺少 --hosts 名单' >&2; exit 2; }; explicit=1; hosts_arg="$2"; shift ;;
    -y|--yes) YES=1; flags+=(-y) ;;
    --choose) CHOOSE=1; flags+=(--choose) ;;
    *) echo "未知参数: $1；见 setup.sh --help" >&2; exit 2 ;;
  esac
  shift
done
if [ "$CHOOSE" = 1 ] && [ "$YES" = 1 ]; then echo '请分别使用 --choose（重选）或 -y（沿用）。' >&2; exit 2; fi
if [ "$CHOOSE" = 1 ] && ! have_tty; then echo '--choose 需要交互终端' >&2; exit 2; fi
# 统一入口显示自己的摘要，旧偏好文件仍按同一白名单和锁读写。
YES=1 preferences_init
saved="$(preference_get SHARED_HOSTS || true)"
if [ "$explicit" = 0 ]; then
  hosts_arg="$saved"
  if [ -z "$saved" ] || [ "$CHOOSE" = 1 ]; then
    if ! have_tty || [ "$YES" = 1 ]; then
      echo '首次无人值守更新请指定 --hosts opencode,pi 等，或 --hosts none 只同步公共项。' >&2; exit 2
    fi
    read -r -p "本机要配置哪些宿主？all 全部，或 opencode,pi,dsh,codex,claude,antigravity；none 仅公共项 [${saved:-opencode}]: " hosts_arg </dev/tty || exit 1
    hosts_arg="${hosts_arg:-${saved:-opencode}}"
  fi
fi
preference_put SHARED_HOSTS "$hosts_arg" || { echo '宿主名单无效，请用逗号分隔，或单填 all / none。' >&2; exit 2; }
hosts=()
if [ "$hosts_arg" = all ]; then
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
      echo '提示: DSH 仅支持 Linux / macOS，Windows 下 all 跳过 dsh。'
      hosts=(opencode pi codex claude antigravity) ;;
    *) hosts=(opencode pi dsh codex claude antigravity) ;;
  esac
else
  for host in opencode pi dsh codex claude antigravity; do
    case ",$hosts_arg," in *,"$host",*) hosts+=("$host") ;; esac
  done
fi
if [ "$hosts_arg" != none ] && [ "$YES" != 1 ] && ! have_tty; then
  echo '无交互终端：请显式加 -y 以使用宿主安装偏好（可能升级客户端、更新共享 worker）。' >&2; exit 2
fi
groups=(base)
for group in research accel kb ppt; do
  key="SHARED_$(printf '%s' "$group" | tr 'a-z' 'A-Z')"
  if ask "同步可选 Skill 组 $group？" N "$key"; then groups+=("$group"); fi
done
case "${SKILLS_EXTERNAL:-}" in
  install|skip) ;;
  *) if ask '更新外部设计 Skill？' Y SHARED_EXTERNAL; then SKILLS_EXTERNAL=install; else SKILLS_EXTERNAL=skip; fi ;;
esac
mod="$root/modules/run.sh"
known="$(bash "$mod" --host common --list | awk '{print $1}' | paste -sd, -)"
mod_env=(); mod_flags=()
[ "$YES" != 1 ] || mod_flags+=(--yes)
if [ "${PREF_REUSE:-0}" = 1 ]; then
  old_known="$(preference_get SHARED_MODULES_KNOWN || true)"; old_sel="$(preference_get SHARED_MODULES || true)"
  if [ -z "$old_known" ]; then
    # 共用模块属于本机，即使本轮只更新 Skill，也保留原宿主选择过的项。
    for k in OC PI DSH CODEX; do
      old_known+=",$(preference_get "${k}_MODULES_KNOWN" || true)"
      old_sel+=",$(preference_get "${k}_MODULES" || true)"
    done
  fi
  mod_env=("AGENT_SKILLS_MODULE_SELECTION=$old_sel" "AGENT_SKILLS_MODULE_KNOWN=$old_known")
fi
selected="$(env ${mod_env[@]+"${mod_env[@]}"} bash "$mod" --host common ${mod_flags[@]+"${mod_flags[@]}"} --select)"
shared_modules="${selected//$'\n'/,}"
preference_put SHARED_MODULES "$shared_modules"
preference_put SHARED_MODULES_KNOWN "$known"
echo "本机宿主: $hosts_arg；共享 Skill: ${groups[*]}；外部设计: $SKILLS_EXTERNAL；公共模块: ${shared_modules:-无}"
if [ "$YES" != 1 ] && have_tty; then ask_builtin '按以上选择更新？' Y || exit 0; fi
minor=6; case " ${groups[*]} " in *' ppt '*) minor=10 ;; esac
resolve_python3 "$minor" || { echo "共享发现入口需要 Python 3.$minor+（python3 / python / py -3），请安装后重跑。" >&2; exit 1; }
preferences_commit
saved="$(if [ ! -L "$PREF_FILE" ] && [ -f "$PREF_FILE" ]; then
  YES=1 preferences_init
  printf '%s\n' "$PREF_SESSION" | LC_ALL=C sort
fi)"
if [ "$saved" != "$(printf '%s\n' "$PREF_SESSION" | LC_ALL=C sort)" ]; then
  echo 'ERROR: 本轮安装偏好未保存；未执行更新。请处理上述告警后重跑。' >&2
  exit 1
fi
roles=0; case " ${hosts[*]+"${hosts[*]}"} " in *' claude '*) roles=1 ;; esac
AGENT_SKILLS_COMMON=1 AGENT_SKILLS_CLAUDE_ROLES="$roles" AGENTS_TAIL=0 SKILLS_EXTERNAL="$SKILLS_EXTERNAL" \
  bash "$root/skills-sync.sh" "${groups[@]}"
# claude-mem 是共享 worker：各宿主的官方安装器都会停掉它，逐个重启会互相打断。
# 这里记下运行前状态，各宿主只装自己的 IDE 集成，收尾（含中途失败）只恢复一次。
mem_settings="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json"
mem_was_alive=0; mem_worker_alive "$mem_settings" && mem_was_alive=1
restore_mem_worker() {
  [ "${mem_was_alive:-0}" = 1 ] || return 0
  mem_worker_alive "$mem_settings" && return 0
  mem_worker_restore "$mem_settings" 1 || true
}
trap restore_mem_worker EXIT
for host in ${hosts[@]+"${hosts[@]}"}; do
  echo "== $host 专用配置 =="
  case "$host" in
    claude)
      if [ "${AGENTS_TAIL:-1}" = 1 ]; then python3 "$root/scripts/migrate-agents-tail.py" --sync-host claude; fi ;;
    antigravity)
      if [ "${AGENTS_TAIL:-1}" = 1 ]; then python3 "$root/scripts/migrate-agents-tail.py" --sync-host antigravity; fi
      python3 "$root/scripts/migrate-agents-tail.py" --antigravity-mcp ;;
    *) case "$host" in opencode) prefix=OC ;; pi) prefix=PI ;; dsh) prefix=DSH ;; codex) prefix=CODEX ;; esac
       AGENT_SKILLS_HOST_ONLY=1 AGENT_SKILLS_HOST_PREFIX="$prefix" AGENT_SKILLS_SHARED_MODULES="$shared_modules" \
         AGENT_SKILLS_MEM_RESTART=0 \
         bash "$root/$host-setup.sh" ${flags[@]+"${flags[@]}"} ;;
  esac
done
bash "$mod" --host common --selected "$selected"
echo '本次更新完成。'
