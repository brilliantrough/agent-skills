#!/usr/bin/env bash
# pi-setup.sh — 个人 Pi(pi coding agent)一键配置(原生 MCP + magic-context + ponytail + subagent + claude-mem 官方扩展 + skills 本体)
# 仓库: brilliantrough/agent-skills
#
# 干什么(一次确认 + 幂等,重复跑安全):
#   全部确认在开始时一次性收集(collect_setup_plan):先只读探测现状,集中 ask 设置 PLAN_*,
#   最后收集网关/凭据;之后安装/更新/写配置阶段只按 PLAN 行动,不再提问。
#   询问默认:装缺的软件/包、写入条目 → [Y/n](回车即装);覆盖已有配置、无代理下继续、
#            版本不一致强启用 → [y/N];非交互环境按各自默认执行。AGENTS.tail 写入本宿主用户级规则文件，默认 Y。
#   凭据(前置阶段只问这一处):统一网关(回车=默认 https://api.pezayo.com/v1)+ 6 个 api key
#            (claude-newapi / codex-newapi / anthropic-newapi / magic-context embedding / claude-mem);
#            回车=跳过,占位符保留,之后按清单手工补(四处 <YOUR_NEWAPI_API_KEY> 按 provider 名各填各的;
#            新规则是占位符不再触发补问)
#   0. 代理环境提醒(大小写都查;未设则探测直连,透明代理不拦;都不通才要求确认,属前置阶段)
#   1. 依赖检查(全部前置):curl/git(缺失即退出)、python3(缺则由 uv 提供自管理 3.12)、npx(缺 → 征得同意装 fnm + Node LTS)、
#      bun(缺 → 征得同意装,claude-mem runtime 与 context-mode 所需依赖)、uv(可选,.sdoc 校验用)
#   2. pi 本体与已装包更新:已装 → 默认 Y,逐包 pi update(不用 --all,它会连带升 magic-context)
#      唯独不碰 magic-context:它与 opencode 侧共享 context.db,升级要迁移 DB、会打断正在跑的
#      进程,所以独立一问、默认 Y(步骤 3.1);仍须确认两边都没人使用
#   3. pi 包(pi install,幂等):@dietrichgebert/ponytail / pi-subagents-j0k3r /
#      pi-lens / @juicesharp/rpiv-ask-user-question / pi-autoname@0.6.8 / @cortexkit/pi-magic-context /
#      git:github.com/brilliantrough/agent-skills 的旧登记会退役；本仓库自身改从 SOURCE_ROOT
#      本地 staged 路径安装(含个性化 UI、later、任务耗时扩展、one-dark 主题；setup 刷新副本后重载)。
#      claude-mem 由官方安装器按 Pi 宿主单独部署——旧版散装部署文件会自动清理;pi install 对已登记
#      条目只说"已有"；npm/git 外部包的新版靠步骤 2 逐个 pi update，本地包随源码树更新)
#      另外装 context-mode fork(产物走 GitHub release:下载 launch 包到 ~/.pi/agent/vendor/context-mode
#      再 pi install;开发机用 bash context-mode/setup.sh --publish 发新版。
#      检测到上游 npm:context-mode 或旧的 clone 路径条目会提示卸载——它们与 magic-context 抢 ctx_search/重复注册)
#      启用 magic-context 前检查与 opencode 共享 context.db 的
#      版本守卫(opencode 插件缓存版本 < Pi 扩展版本时先提示,不清理就不启用)
#   4. 部署(字段级合并 本仓模板,api key/网关等本地敏感值保留;模板来自本地源码树,读取失败用内嵌兜底,models.json/mcp.json 同样从源码树取):
#      ~/.pi/agent/settings.json(含按模型 thinking、4 秒起步指数退避重试 8 次)、pi-autoname.json(低频命名)、
#      ~/.pi/agent/models.json、~/.pi/agent/auth.json(占位符初始化,
#      coding plan 等内置 provider 凭据)、~/.pi/agent/mcp.json(原生 MCP,Pi >= 0.99.0)
#      旧 adapter 配置先预览,确认后备份迁移;~/.agents/mcp.json 不修改
#      以及共用配置 ~/.claude-mem/settings.json、~/.config/cortexkit/magic-context.jsonc(含 historian.pi/dreamer.pi)
#   5. claude-mem 官方 runtime 与宿主入口同步——Pi/OpenCode 分别由官方安装器部署，settings 保留本机值
#   6. subagent 定义 ~/.pi/agent/agents/{explore,general,consolidation-reviewer,verification-reviewer}.md
#   7. skills:本仓 base/kb 刷新(漂移先备份)、accel 缺才装；补装外部设计依赖、更新第三方;pi 原生读 ~/.agents/skills
#   8. strictdoc 由 modules/strictdoc 装(.sdoc 校验依赖;uv 的安装/自升级/镜像见 1.3)
#
# 用法:bash pi-setup.sh [-y|--yes]   (-y 默认安装:前置阶段只问一次凭据、其余一律取默认——默认 Y 的照做,
#       默认 N 的跳过(pi update --all、插件缓存清理、magic-context 强启用、无代理继续),用户级规则块默认写入;
#       遵循 PI_CODING_AGENT_DIR,与 pi 一致)
# Windows:在 Git Bash(不是 WSL)里跑同一份脚本;Python 缺失由 uv 兜底(curl/git 由 Git for Windows 自带)。

set -euo pipefail

# ---- 平台:同一套逻辑跑 Linux/macOS 与 Windows 的 Git Bash(MSYS/MinGW),差异集中在这几处 ----
#   * python3 解析链(见 resolve_python3):系统 python3 → python → py → uv 自管理 3.12;Windows 没有 python3 这个名字
#   * 内嵌 python 的 os.getuid() 在 Windows 不存在 → 统一按 77 兜底,与 claude-mem 和本仓库桥扩展的
#     `process.getuid?.() ?? 77` 一致(端口 37700 + 77 = 37777)
#   * 写进 JSON 的路径要让 Windows 原生宿主(node/opencode/codex)认得,不能是 Git Bash 的 /c/...
IS_WIN=0
case "$(uname -s 2>/dev/null || true)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac
BIN_EXT=""; [ "$IS_WIN" = 1 ] && BIN_EXT=".exe"   # 手写兜底路径要带 .exe(PATH 查找不用)
resolve_python3() { # python3 就绪返回 0;否则 python → py → uv 自管理 3.12；函数与 UV_PY 导出给子 Bash
  # 候选一律先 -c pass 试跑:Windows 商店的 python.exe 占位 stub 能 command -v 到,一跑就报错
  if command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1; then return 0; fi
  if command -v python >/dev/null 2>&1 && python -c pass >/dev/null 2>&1; then python3() { python "$@"; }; export -f python3; return 0; fi
  if command -v py >/dev/null 2>&1 && py -3 -c pass >/dev/null 2>&1; then python3() { py -3 "$@"; }; export -f python3; return 0; fi
  [ "${PLAN_PYTHON_UV:-1}" = 1 ] || return 1
  command -v uv >/dev/null 2>&1 || [ -x "$HOME/.local/bin/uv$BIN_EXT" ] || {
    local sh_tmp rc=1
    sh_tmp="$(mktemp)" || return 1
    if curl -fsSL --connect-timeout 8 -m 60 -o "$sh_tmp" https://astral.sh/uv/install.sh; then
      UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$sh_tmp" && rc=0
    fi
    rm -f "$sh_tmp"
    [ $rc -eq 0 ] || return 1
  }
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || return 1
  uv python install 3.12 || return 1
  local p; p="$(uv python find 3.12 2>/dev/null || true)"
  [ -n "$p" ] || return 1
  if [ "$IS_WIN" = 1 ] && command -v cygpath >/dev/null 2>&1; then p="$(cygpath -u "$p")"; fi
  UV_PY="$p"; export UV_PY; python3() { "$UV_PY" "$@"; }; export -f python3
}
npath() { # POSIX 路径 → 宿主路径(Git Bash 的 /c/Users/x 对原生程序无效,要 C:/Users/x)
  if [ "$IS_WIN" = 1 ] && command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
rpath() { # 解析实际写入目标；更新内容时保留文件和父目录上的符号链接。
  local p
  p="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_posix())' "$(npath "$1")")" || return 1
  if [ "$IS_WIN" = 1 ]; then cygpath -u "$p"; else printf '%s' "$p"; fi
}
nbin() { # 可执行文件的宿主路径:MSYS 的 command -v 会去掉 .exe,宿主 spawn 前显式补回
  if [ "$IS_WIN" = 1 ] && [ -f "$1.exe" ]; then npath "$1.exe"; else npath "$1"; fi
}

# -y/--yes(或环境变量 ASSUME_YES=1)「默认安装」:前置计划不再逐项确认,一律取默认值 —— 默认 Y 的照做
# (装缺件、字段级合并写配置、刷新 skills、写用户级 AGENTS 规则块),默认 N 的跳过(覆盖缓存、版本不一致时强启用、无代理继续)。
# 唯一还会问的是凭据(网关 + 6 个 api key);没有终端时静默跳过、占位符保留(无人值守用环境变量预填)。
ASSUME_YES="${ASSUME_YES:-}"
CHOOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --choose) CHOOSE=1 ;;
    -h|--help) echo "用法: bash <本脚本> [-y|--yes] [--choose]   # 默认复用本机偏好；--choose 逐项修改；-y 不再逐项确认"; exit 0 ;;
    *) echo "未知参数: $1(仅支持 -y|--yes / --choose / -h|--help)" >&2; exit 2 ;;
  esac
  shift
done

AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
case "$AGENT_DIR" in /*|[A-Za-z]:/*) ;; *) AGENT_DIR="$PWD/${AGENT_DIR#./}" ;; esac
[ "$AGENT_DIR" = / ] || AGENT_DIR="${AGENT_DIR%/}"
if [ "$IS_WIN" != 1 ] && [ -x "$HOME/.local/share/pi-node/current/bin/pi" ]; then
  export PATH="$HOME/.local/share/pi-node/current/bin:$PATH"
fi
MODELS="$AGENT_DIR/models.json"
SETTINGS="$AGENT_DIR/settings.json"
MCP_CONFIG="$AGENT_DIR/mcp.json"
MC_SETTINGS="$HOME/.claude-mem/settings.json"
# 本仓库 Pi 包从本地源码树 staged 到这里；依赖安装在副本，不写候选工作树。
REPO_PI_SPEC="$AGENT_DIR/vendor/agent-skills"
REPO_PI_PKG="$REPO_PI_SPEC"
MC_CFG="$HOME/.config/cortexkit/magic-context.jsonc"
AUTH="$AGENT_DIR/auth.json"
OC_MC_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/packages/@cortexkit/opencode-magic-context@latest"
# opencode V2 把包放在同一缓存根的 npm/<数字代次>/ 下;旧 packages/ 布局只作兼容读取。
OC_NPM_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/npm/@cortexkit/opencode-magic-context@latest"

mc_cache_state() { # 任一缓存位置不可判定 → unknown;都不存在 → absent;其余 present
  local paths=("$OC_MC_CACHE")
  [ -z "${OC_NPM_CACHE:-}" ] || paths+=("$OC_NPM_CACHE")
  python3 - "${paths[@]}" 2>/dev/null <<'PY'
import os, pathlib, stat, sys
def state(raw):
    parts = pathlib.Path(os.path.abspath(raw)).parts
    current = parts[0]
    for part in parts[1:]:
        current = os.path.join(current, part)
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            return "absent"
        except OSError:
            return "unknown"
        if stat.S_ISLNK(info.st_mode):
            try:
                os.stat(current)
            except OSError:
                return "unknown"
    return "present"
states = [state(p) for p in sys.argv[1:]]
print("unknown" if "unknown" in states else "present" if "present" in states else "absent")
PY
}

mc_cache_version() { # V2 存在时只认当前代次；损坏不能用旧代次或旧布局代答。
  python3 - "$OC_MC_CACHE" "${OC_NPM_CACHE:-}" 2>/dev/null <<'PY'
import json, os, sys
from pathlib import Path
old, npm = sys.argv[1:]
name = '@cortexkit/opencode-magic-context'
try:
    if npm and os.path.lexists(npm):
        root = Path(npm)
        current = max((p for p in root.iterdir() if p.name.isdecimal()), key=lambda p: int(p.name), default=root)
        version = json.loads((current / 'node_modules' / name / 'package.json').read_text(encoding='utf-8'))['version']
    else:
        version = json.loads((Path(old) / 'package.json').read_text(encoding='utf-8'))['dependencies'][name]
    if isinstance(version, str): print(version.strip())
except (OSError, ValueError, KeyError, TypeError):
    pass
PY
}

ask_builtin() { # $1=提示 $2=默认(Y/N,缺省 N)
  local a="" def="${2:-N}" hint="y/N"
  [ "$def" = Y ] && hint="Y/n"
  # -y(默认安装):不再逐项确认,直接取默认 —— 默认 Y 的照做,默认 N 的跳过(凭据由 ask_value 单独问)
  if [ -n "$ASSUME_YES" ]; then
    if [ "$def" = Y ]; then echo "$1 [$hint] → 是 (-y)"; return 0
    else echo "$1 [$hint] → 否 (-y,跳过)"; return 1; fi
  fi
  # 不能把 read 的 stderr 丢掉:read -p 的提示符走 stderr,吞掉后提示不可见,脚本像卡死。
  # 用 fd 9 显式打开 /dev/tty:无控制终端时(CI/cron/管道)打开失败保持安静,直接走默认值。
  if { exec 9</dev/tty; } 2>/dev/null; then
    read -r -u 9 -p "$1 [$hint] " a || a=""
    exec 9<&-
    if [ -z "$a" ]; then [ "$def" = Y ]; else [[ "$a" =~ ^[Yy]$ ]]; fi
  else
    [ "$def" = Y ]  # 非交互(无 tty):按该询问的默认值
  fi
}

# 本机安装偏好：只保存经过校验的是非选择与模块名单，不保存凭据，也不执行文件内容。
PREF_FILE=""; PREF_SESSION=""; PREF_ORIGINAL=""; PREF_REUSE=0; PREF_WRITE=1; PREF_COUNT=0
PREF_KNOWN_KEYS="SHARED_PROXY SHARED_PYTHON_UV SHARED_NODE SHARED_BUN SHARED_UV_INSTALL SHARED_UV_UPGRADE SHARED_UV_MIRROR SHARED_RESEARCH SHARED_ACCEL SHARED_KB SHARED_PPT SHARED_EXTERNAL SHARED_AGENTS_TAIL \
PI_AGENTS_TAIL PI_GIT_BASH PI_INSTALL PI_UPDATE PI_PKGS PI_OC_CACHE_CLEAN PI_MC_UPGRADE PI_MC_FORCE PI_CM_GROUP PI_MCP_MIGRATE PI_WRITE_CFG PI_MEM_RUNTIME PI_LEGACY_CLEAN PI_MODULES PI_MODULES_KNOWN \
OC_AGENTS_TAIL OC_UPGRADE OC_PONYTAIL OC_MC_REFRESH OC_CLAUDE_MEM OC_WRITE_CFG OC_FORCE_MANUAL OC_COMPACTION OC_TUI_KEYS OC_MODULES OC_MODULES_KNOWN \
CODEX_AGENTS_TAIL CODEX_WRITE_CFG CODEX_MEM_INSTALLER CODEX_PLUGINS CODEX_HOOKS CODEX_REVIEWER CODEX_MODULES CODEX_MODULES_KNOWN \
DSH_AGENTS_TAIL DSH_NODE DSH_SKILLS DSH_MODULES DSH_MODULES_KNOWN SHARED_HOSTS SHARED_MODULES SHARED_MODULES_KNOWN"
PREF_RISKY_KEYS="SHARED_PROXY PI_AGENTS_TAIL OC_AGENTS_TAIL CODEX_AGENTS_TAIL DSH_AGENTS_TAIL OC_UPGRADE PI_OC_CACHE_CLEAN PI_MC_UPGRADE PI_MC_FORCE PI_MEM_RUNTIME OC_MC_REFRESH OC_CLAUDE_MEM CODEX_MEM_INSTALLER"
preference_get() {
  local key="$1" line
  line="$(printf '%s\n' "$PREF_SESSION" | grep "^${key}=" | tail -1)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}
preference_put() {
  local key="$1" value="$2" current
  [[ "$key" =~ ^(SHARED|PI|OC|CODEX|DSH)_[A-Z0-9_]+$ ]] || return 1
  case " $PREF_KNOWN_KEYS " in *" $key "*) ;; *) return 1 ;; esac
  case "$key" in SHARED_HOSTS) [[ "$value" = none || "$value" =~ ^(opencode|pi|dsh|codex|claude|antigravity)(,(opencode|pi|dsh|codex|claude|antigravity))*$ ]] || return 1 ;;
    *_MODULES|*_MODULES_KNOWN) [[ "$value" =~ ^[a-z0-9_,-]*$ ]] || return 1 ;;
    *) [[ "$value" =~ ^[01]$ ]] || return 1 ;;
  esac
  if current="$(preference_get "$key")" && [ "$current" = "$value" ]; then return 0; fi
  PREF_SESSION="$(printf '%s\n' "$PREF_SESSION" | grep -v "^${key}=" || true)"
  PREF_SESSION="${PREF_SESSION:+$PREF_SESSION
}${key}=${value}"
}
preferences_init() {
  local line key value lineno=0
  if [ "${CHOOSE:-0}" = 1 ]; then ASSUME_YES=""; YES=0; fi
  PREF_FILE="${AGENT_SKILLS_PREFERENCES:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-skills/preferences.conf}"
  case "$PREF_FILE" in /*|[A-Za-z]:/*) ;; *) PREF_FILE="$PWD/${PREF_FILE#./}" ;; esac
  PREF_SESSION="# agent-skills 本机安装偏好；只含非敏感选择，勿写入凭据"
  PREF_ORIGINAL=""; PREF_REUSE=0; PREF_WRITE=1
  [ "${CHECK_ONLY:-0}" = 0 ] && [ "${PLUGINS_ONLY:-0}" = 0 ] || PREF_WRITE=0
  if [ -L "$PREF_FILE" ]; then
    echo "WARN: 安装偏好目标是符号链接，忽略且不会替换" >&2
  elif [ -f "$PREF_FILE" ]; then
    PREF_ORIGINAL="$(cat "$PREF_FILE")"
    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno+1))
      line="${line%$'\r'}"
      case "$line" in
        ''|'#'*) continue ;;
        *=*)
          key="${line%%=*}"; value="${line#*=}"
          preference_put "$key" "$value" || echo "WARN: 忽略安装偏好第 $lineno 行（键或值无效）" >&2
          ;;
        *) echo "WARN: 忽略安装偏好第 $lineno 行（格式无效）" >&2 ;;
      esac
    done < "$PREF_FILE"
  fi
  PREF_COUNT="$(printf '%s\n' "$PREF_SESSION" | grep -c '=' || true)"
  if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ] && [ "${CHOOSE:-0}" != 1 ]; then
    case "${AGENT_SKILLS_HOST_PREFIX:-}" in PI|OC|CODEX|DSH)
      if grep -q "^${AGENT_SKILLS_HOST_PREFIX:-}_" <<< "$PREF_SESSION"; then PREF_REUSE=1; fi ;; esac
    return 0
  fi
  if [ "$PREF_COUNT" -gt 0 ] && [ "${CHOOSE:-0}" != 1 ] && [ "${CHECK_ONLY:-0}" = 0 ]; then
    if [ -n "${ASSUME_YES:-}" ] || [ "${YES:-0}" = 1 ]; then
      PREF_REUSE=1
    else
      echo "安装偏好: $PREF_FILE"
      printf '%s\n' "$PREF_SESSION" | while IFS= read -r line; do
        case "$line" in
          *_MODULES=*|*_MODULES_KNOWN=*) printf '%s=<待当前源码校验>\n' "${line%%=*}" ;;
          *) printf '%s\n' "$line" ;;
        esac
      done
      if ask_builtin "按以上安装偏好继续（否则逐项修改）？" Y; then PREF_REUSE=1; fi
    fi
  fi
}
ask() { # $1=提示 $2=默认 $3=稳定偏好键(可选)
  local key="${3:-}" value rc answer=0
  if [ -n "$key" ] && [ "${PREF_REUSE:-0}" = 1 ]; then
    if value="$(preference_get "$key")"; then
      [ "$value" = 1 ]; rc=$?
    else
      case " $PREF_RISKY_KEYS " in
        *" $key "*) if ask_builtin "$1" "${2:-N}"; then rc=0; else rc=$?; fi ;;
        *) if [ "${2:-N}" = Y ]; then rc=0; else rc=1; fi ;;
      esac
    fi
  else
    if ask_builtin "$1" "${2:-N}"; then rc=0; else rc=$?; fi
  fi
  [ "$rc" = 0 ] && answer=1
  if [ -n "$key" ] && ! preference_put "$key" "$answer"; then
    echo "WARN: 安装偏好键未登记，已忽略" >&2
  fi
  case "$key" in *_WRITE_CFG) PREF_WRITE="$answer" ;; esac
  return "$rc"
}
preferences_filter_modules() {
  local dir name valid="" line value item filtered key session="$PREF_SESSION"
  printf '%s\n' "$PREF_SESSION" | grep -qE '_(MODULES|MODULES_KNOWN)=' || return 0
  [ -n "${SOURCE_ROOT:-}" ] && [ -d "$SOURCE_ROOT/modules" ] || return 1
  for dir in "$SOURCE_ROOT"/modules/*/; do
    [ -f "$dir/setup.sh" ] || continue
    name="$(sed -n 's/^# module:[[:space:]]*//p' "$dir/setup.sh" | head -1)"
    name="${name:-$(basename "$dir")}"
    valid="${valid:+$valid }$name"
  done
  while IFS= read -r line; do
    case "$line" in
      *_MODULES=*|*_MODULES_KNOWN=*)
        key="${line%%=*}"; value="${line#*=}"; filtered=""
        for item in ${value//,/ }; do
          case " $valid " in
            *" $item "*) filtered="${filtered:+$filtered,}$item" ;;
          esac
        done
        [ "$filtered" = "$value" ] || preference_put "$key" "$filtered" || return 1
        ;;
    esac
  done < <(printf '%s\n' "$session")
}
preferences_lock() {
  PREF_LOCK="${PREF_FILE}.lock"
  if ! mkdir "$PREF_LOCK" 2>/dev/null; then
    echo "WARN: 检测到安装偏好锁: $PREF_LOCK；若确认无安装进程，可人工删除该目录后重试" >&2
    return 1
  fi
  if ! printf '%s\n' "$$" > "$PREF_LOCK/pid"; then
    rm -f "$PREF_LOCK/pid"; rmdir "$PREF_LOCK" 2>/dev/null || true
    echo "WARN: 无法记录安装偏好锁，本次跳过" >&2; return 1
  fi
}
preferences_commit_locked() {
  (
  trap 'rm -f "$PREF_LOCK/pid"; rmdir "$PREF_LOCK" 2>/dev/null || true' EXIT
  local dir tmp current
  dir="$(dirname "$PREF_FILE")"
  if [ -L "$PREF_FILE" ] || { [ -e "$PREF_FILE" ] && [ ! -f "$PREF_FILE" ]; }; then
    echo "WARN: 安装偏好目标已变为非普通文件或符号链接，未保存" >&2; return 0
  fi
  current=""; [ ! -f "$PREF_FILE" ] || current="$(cat "$PREF_FILE")"
  if [ "$current" = "$PREF_SESSION" ]; then
    echo "安装偏好: 未变化 ($PREF_FILE)"
    return 0
  fi
  if [ "$current" != "$PREF_ORIGINAL" ]; then
    echo "WARN: 安装偏好在本次运行期间已被其它进程修改，本次不覆盖；请重跑以合并选择" >&2
    return 0
  fi
  tmp="$(mktemp "$dir/.preferences.XXXXXX")" || { echo "WARN: 无法暂存安装偏好" >&2; return 0; }
  if printf '%s\n' "$PREF_SESSION" > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$PREF_FILE"; then
    echo "安装偏好: 已保存 ($PREF_FILE)"
  else
    rm -f "$tmp"; echo "WARN: 安装偏好保存失败；安装计划不变" >&2
  fi
  )
}
preferences_commit() {
  local dir
  [ "${PREF_WRITE:-0}" = 1 ] || { echo "安装偏好: 本次为只读／精简模式或拒绝配置写入，不保存"; return 0; }
  if [ -L "$PREF_FILE" ] || { [ -e "$PREF_FILE" ] && [ ! -f "$PREF_FILE" ]; }; then
    echo "WARN: 安装偏好目标不是普通文件或是符号链接，未保存" >&2; return 0
  fi
  PREF_COUNT="$(printf '%s\n' "$PREF_SESSION" | grep -c '=' || true)"
  [ "$PREF_COUNT" -gt 0 ] || return 0
  preferences_filter_modules || { echo "WARN: 模块偏好未通过当前源码校验，未保存" >&2; return 0; }
  dir="$(dirname "$PREF_FILE")"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" && chmod 700 "$dir" || { echo "WARN: 无法创建安装偏好目录: $dir" >&2; return 0; }
  fi
  preferences_lock || return 0
  preferences_commit_locked
}

# 内嵌逻辑保留 Pi 的单文件入口;回归检查见 tests/pi-setup-windows-git-bash.py。
ensure_git_bash_startup() {
  [ "$IS_WIN" = 1 ] || return 0
  [ "${PLAN_GIT_BASH:-0}" = 1 ] || return 0
  local bindir
  bindir="$(cygpath -u "$(dirname "$BUN_BIN")")" || return 1
  # 路径供 Bash 使用,不可被 MSYS 自动转换回 C:/...;仅对这一次 Python 调用禁用参数转换。
  MSYS2_ARG_CONV_EXCL='*' python3 - "$(npath "$HOME")" "$bindir" "${TERM_PROGRAM:-}" <<'PY_GIT_BASH'
import os, pathlib, shlex, shutil, sys, tempfile
home, bindir, terminal = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
changes = []

def read(p):
    if p.exists() and not p.is_file():
        raise SystemExit(f'ERROR: {p} 不是普通文件,保留原样')
    return p.read_bytes().decode('utf-8') if p.exists() else ''

def stage(p, old, new):
    if old != new:
        changes.append((p, new))

def block(p, name, body):
    old = read(p)
    start, end = f'# >>> agent-skills {name} >>>', f'# <<< agent-skills {name} <<<'
    managed = start + '\n' + body + '\n' + end
    if start in old or end in old:
        if old.count(start) != 1 or old.count(end) != 1 or old.index(start) > old.index(end):
            raise SystemExit(f'ERROR: {p} 的受管块不完整,保留原文件')
        new = old[:old.index(start)] + managed + old[old.index(end) + len(end):]
    else:
        new = old + ('\n' if old and not old.endswith('\n') else '') + managed + '\n'
    stage(p, old, new)

block(home / '.bashrc', 'Bun PATH',
      'case ":$PATH:" in\n'
      f'  *{shlex.quote(":" + bindir + ":")}*) ;;\n'
      f'  *) export PATH={shlex.quote(bindir)}:"$PATH" ;;\n'
      'esac\n__agent_skills_bashrc_loaded=1')
# Bash 只读第一个登录文件;不新建 .bash_profile 去遮蔽已有 .bash_login/.profile。
profiles = [home / n for n in ('.bash_profile', '.bash_login', '.profile')]
profile = next((p for p in profiles if p.exists() or p.is_symlink()), profiles[0])
block(profile, 'bashrc',
      'if [ "${__agent_skills_bashrc_loaded:-}" != 1 ] && [ -f "$HOME/.bashrc" ]; then\n'
      '  . "$HOME/.bashrc"\nfi')
if terminal == 'mintty':
    p = home / '.minttyrc'
    old = read(p)
    options = dict(line.split('=', 1) for line in old.splitlines()
                   if '=' in line and not line.lstrip().startswith('#'))
    options = {k.strip(): v.strip() for k, v in options.items()}
    wanted = {'CopyOnSelect': 'yes', 'CtrlShiftShortcuts': 'yes'}
    if options.get('CtrlExchangeShift', '').lower() in ('yes', 'true', 'on', '1'):
        wanted.pop('CtrlShiftShortcuts')
        print('WARN: CtrlExchangeShift 已启用,不自动开启 CtrlShiftShortcuts;保留现有按键')
    extra = ''.join(f'{k}={v}\n' for k, v in wanted.items() if k not in options)
    if extra:
        stage(p, old, old + ('\n' if old and not old.endswith('\n') else '') + extra)
# 所有输入先验证,写前备份;临时文件与目标同目录,替换失败不截断原文。符号链接写入链接目标。
for p, new in changes:
    if p.is_symlink():
        p = pathlib.Path(os.path.realpath(p))
    if p.exists():
        fd, backup = tempfile.mkstemp(prefix=p.name + '.bak-', dir=p.parent)
        os.close(fd)
        shutil.copy2(p, backup)
        print(f'backup: {backup}')
    fd, tmp = tempfile.mkstemp(prefix='.agent-skills-', dir=p.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
            f.write(new)
        if p.exists():
            shutil.copymode(p, tmp)
        os.replace(tmp, p)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print(f'updated: {p}')
print('Git Bash 启动配置已检查;新终端读取 PATH/mintty 配置,当前父终端不受子脚本 export 影响')
PY_GIT_BASH
}

# 把 worker 地址显式写进 settings(claude-mem 自身的默认是 37700 + uid%100,
# 目的就是同一台服务器上不同用户互不冲突;写出来是为了可见、可查,不改变取值)。
# 已存在的键一律保留(自定义端口/主机不被覆盖)。改前存 .bak。
ensure_mem_worker_keys() {
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || return 0
  local f="${1:-$SETTINGS}"
  [ -f "$f" ] || return 0
  local out
  out="$(python3 - "$f" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
try:
    s = json.load(open(p, encoding='utf-8'))
except Exception as e:
    print(f"WARN: 解析失败: {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(s, dict):
    sys.exit(1)
want = {'CLAUDE_MEM_WORKER_HOST': '127.0.0.1', 'CLAUDE_MEM_WORKER_PORT': str(37700 + getattr(os, 'getuid', lambda: 77)() % 100)}
missing = [k for k in want if not s.get(k)]
if not missing:
    print('unchanged'); sys.exit(0)
out = {}
for k, v in s.items():
    out[k] = v
    if k == 'CLAUDE_MEM_RUNTIME':
        for mk in missing:
            out[mk] = want[mk]
for mk in missing:          # 没有 RUNTIME 键时追加到末尾
    out.setdefault(mk, want[mk])
json.dump(out, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
open(p, 'a', encoding='utf-8').write('\n')
print('added: ' + ', '.join(f'{k}={want[k]}' for k in missing))
PYEOF
)" || { echo "WARN: $f 的 worker 键写入失败,保持原样" >&2; return 1; }
  case "$out" in
    unchanged) return 0 ;;
    added:*)   cp -p "$f" "$f.bak-$(date +%Y%m%d%H%M%S)"; printf '%s\n' "$out" ;;
    *)         return 0 ;;
  esac
}

# claude-mem worker 的 host:port(与 claude-mem/桥接同一优先级:环境变量 > settings.json > 默认公式)
mem_worker_url() {
  python3 - "$1" <<'PYEOF'
import json, os, sys
try:
    s = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    s = {}
host = os.environ.get('CLAUDE_MEM_WORKER_HOST') or s.get('CLAUDE_MEM_WORKER_HOST') or '127.0.0.1'
port = os.environ.get('CLAUDE_MEM_WORKER_PORT') or s.get('CLAUDE_MEM_WORKER_PORT') or str(37700 + getattr(os, 'getuid', lambda: 77)() % 100)
print(f'{host}:{port}')
PYEOF
}

# ---- 网关/凭据预填:新机器只需填网关 + 各 api key ----
# 环境变量优先(便于无人值守):PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY(兜底给没单独给的槽)
# / PI_{CLAUDE,CODEX,ANTHROPIC}_NEWAPI_API_KEY / PI_EMBEDDING_API_KEY / PI_CLAUDE_MEM_API_KEY / MCPHUB_HOST
DEFAULT_GW="https://api.pezayo.com/v1"
GW_BASE="${PI_GATEWAY_BASE_URL:-}"; MCPHUB_HOST="${MCPHUB_HOST:-}"
K_CLAUDE="${PI_CLAUDE_NEWAPI_API_KEY:-${PI_GATEWAY_API_KEY:-}}"
K_CODEX="${PI_CODEX_NEWAPI_API_KEY:-${PI_GATEWAY_API_KEY:-}}"
K_ANTHROPIC="${PI_ANTHROPIC_NEWAPI_API_KEY:-${PI_GATEWAY_API_KEY:-}}"
K_GEMINI="${PI_GEMINI_NEWAPI_API_KEY:-${PI_GATEWAY_API_KEY:-}}"
K_EMBED="${PI_EMBEDDING_API_KEY:-${PI_GATEWAY_API_KEY:-}}"
K_MEM="${PI_CLAUDE_MEM_API_KEY:-${PI_GATEWAY_API_KEY:-}}"

ask_value() { # $1=提示(括号里写协议/分组等说明) $2=输出变量 $3=非空则不回显(用于 key) $4=默认值(回车采用;输 - 留占位符)
  local a="" hint
  if [ -n "${4:-}" ]; then hint="$1;回车=默认 $4,输 - 留占位符"
  else hint="$1;回车跳过(占位符保留)"; fi
  # 有终端就问(-y 也问:凭据只能人工给);无终端(CI/管道)静默保持空 → 占位符保留。
  # 无人值守用环境变量预填(见上方 GW_BASE / K_*)。
  if { exec 9</dev/tty; } 2>/dev/null; then
    if [ -n "${3:-}" ]; then read -r -s -u 9 -p "$hint: " a || a=""; echo
    else read -r -u 9 -p "$hint: " a || a=""; fi
    exec 9<&-
    [ "$a" = "-" ] && a=""
    [ -z "$a" ] && a="${4:-}"
    printf -v "$2" '%s' "$a"
  fi
}

config_probe() { # $1=provider|embedding|mem|gateway|mcp $2=名称，其余为配置文件；0=有，1=缺，2=无法读取
  local node_bin kind name f rc
  local files=()
  kind="$1"; name="$2"; shift 2
  for f in "$@"; do [ ! -f "$f" ] || files+=("$(npath "$f")"); done
  [ "${#files[@]}" -gt 0 ] || return 1
  node_bin="$(command -v node 2>/dev/null || true)"
  [ -n "$node_bin" ] || [ ! -x "$HOME/.local/share/pi-node/current/bin/node" ] || node_bin="$HOME/.local/share/pi-node/current/bin/node"
  if [ -z "$node_bin" ]; then
    echo "WARN: 无可用 Node，无法核对既有配置；本次不追问，保留原值并用手工或环境变量补项" >&2
    return 2
  fi
  "$node_bin" - "$kind" "$name" "${files[@]}" <<'JS'
const fs = require('node:fs');
const [kind, name, ...files] = process.argv.slice(2);
function stripJsonc(text) {
  let out = '', string = false, escaped = false, line = false, block = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i], next = text[i + 1];
    if (line) { if (c === '\n') { out += c; line = false; } continue; }
    if (block) { if (c === '*' && next === '/') { block = false; i++; } else if (c === '\n') out += c; continue; }
    if (string) {
      out += c;
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') string = false;
      continue;
    }
    if (c === '"') { out += c; string = true; continue; }
    if (c === '/' && next === '/') { line = true; i++; continue; }
    if (c === '/' && next === '*') { block = true; i++; continue; }
    out += c;
  }
  return out.replace(/("(?:\\.|[^"\\])*")|,(\s*[}\]])/g, (match, string, tail) => string || tail);
}
let unreadable = false;
const docs = files.map(file => {
  try {
    const text = stripJsonc(fs.readFileSync(file, 'utf8'));
    return text.trim() ? JSON.parse(text) : {};
  } catch { unreadable = true; return null; }
});
if (unreadable) process.exit(2);
const object = value => value && typeof value === 'object' && !Array.isArray(value);
function merge(base, over) {
  const out = object(base) ? {...base} : {};
  if (!object(over)) return out;
  for (const [key, value] of Object.entries(over)) {
    out[key] = object(out[key]) && object(value) ? merge(out[key], value) : value;
  }
  return out;
}
const doc = docs.reduce(merge, {});
const credential = /^(api[_-]?key|authorization|token|secret|password|passwd|bearer|key)$/i;
const present = value => typeof value === 'string' && value.length > 0;
function hasKey(value, pattern, skipModels = false) {
  if (!value || typeof value !== 'object') return false;
  for (const [key, child] of Object.entries(value)) {
    if (skipModels && key === 'models') continue;
    if (pattern.test(key) && present(child)) return true;
    if (hasKey(child, pattern, skipModels)) return true;
  }
  return false;
}
function baseUrl(value) {
  if (!value || typeof value !== 'object') return false;
  const settings = object(value.settings) ? value.settings : {};
  const options = object(value.options) ? value.options : {};
  return [value.baseUrl, value.baseURL, value.base_url, value.endpoint,
          value.CLAUDE_MEM_OPENROUTER_BASE_URL,
          settings.baseUrl, settings.baseURL, settings.base_url, settings.endpoint,
          options.baseUrl, options.baseURL, options.base_url, options.endpoint].some(present);
}
function provider(doc, id) { return doc.providers?.[id] ?? doc.provider?.[id]; }
let ok = false;
if (kind === 'provider') ok = hasKey(provider(doc, name), credential, true);
else if (kind === 'embedding') ok = hasKey(doc.embedding, credential);
else if (kind === 'mem') ok = hasKey(doc, /^CLAUDE_MEM_OPENROUTER_API_KEY$/);
else if (kind === 'gateway') {
  const providers = ['claude-newapi', 'codex-newapi', 'anthropic-newapi', 'gemini-newapi'];
  ok = providers.every(id => baseUrl(provider(doc, id))) && baseUrl(doc.embedding) && baseUrl(doc);
} else if (kind === 'mcp') {
  const flat = object(doc.mcpServers) ? doc.mcpServers : {};
  const nested = object(doc.mcp?.servers) ? doc.mcp.servers : {};
  const candidates = [flat.web, flat['mcphub-web'], nested.web, nested['mcphub-web'], doc.mcp?.web];
  ok = candidates.some(entry => entry && typeof entry === 'object' &&
    (present(entry.url) || present(entry.baseUrl) || present(entry.command) ||
     (Array.isArray(entry.command) && entry.command.length > 0)));
}
process.exit(ok ? 0 : 1);
JS
  rc=$?
  [ "$rc" != 2 ] || echo "WARN: 既有配置无法解析；本次不追问，保留原值并先修复 JSON／JSONC" >&2
  return "$rc"
}

has_provider_config() { config_probe provider "$1" "$MODELS"; }
has_embedding_config() { config_probe embedding '' "$MC_CFG"; }
has_mem_config() { config_probe mem '' "$MC_SETTINGS"; }
has_gateway_config() { config_probe gateway '' "$MODELS" "$MC_CFG" "$MC_SETTINGS"; }
has_mcp_config() { config_probe mcp '' "$MCP_CONFIG"; }

# 按最终生效配置的实际槽位判断；占位符算已有，无法读取与确实缺项分开处理。
needs_gateway_fill() {
  local provider rc=0
  has_gateway_config || rc=$?
  [ "$rc" != 2 ] || return 2
  [ "$rc" = 0 ] || return 0
  for provider in claude-newapi codex-newapi anthropic-newapi gemini-newapi; do
    rc=0; has_provider_config "$provider" || rc=$?
    [ "$rc" != 2 ] || return 2
    [ "$rc" = 0 ] || return 0
  done
  rc=0; has_embedding_config || rc=$?
  [ "$rc" != 2 ] || return 2
  [ "$rc" = 0 ] || return 0
  rc=0; has_mem_config || rc=$?
  [ "$rc" != 2 ] || return 2
  [ "$rc" = 0 ] || return 0
  return 1
}

needs_mcphub_fill() {
  local rc=0
  has_mcp_config || rc=$?
  [ "$rc" != 2 ] || return 2
  [ "$rc" = 0 ] && return 1
  return 0
}

collect_gateway_values() {
  local need_keys=0 need_mcp=0 have_gw=0 gw_note
  needs_gateway_fill && need_keys=1
  needs_mcphub_fill && need_mcp=1
  [ "$need_keys" = 1 ] || [ "$need_mcp" = 1 ] || return 0
  if [ "$need_keys" = 1 ]; then
    has_gateway_config && have_gw=1
    [ -z "$GW_BASE" ] || have_gw=1
    [ "$have_gw" = 1 ] || ask_value "统一网关完整地址" GW_BASE '' "$DEFAULT_GW"
    [ -z "$GW_BASE" ] || have_gw=1
    if [ "$have_gw" = 0 ]; then
      echo "未提供网关地址:模板里的 <YOUR_*> 占位符保留,装完手工填(见文末清单)"
    else
      has_provider_config claude-newapi || [ -n "$K_CLAUDE" ] || ask_value "claude-newapi 的 API key(anthropic 协议 · claude 模型 · 网关 claude code 分组)" K_CLAUDE 1
      has_provider_config codex-newapi || [ -n "$K_CODEX" ] || ask_value "codex-newapi 的 API key(openai responses 协议 · gpt 模型 · 网关 codex 分组)" K_CODEX 1
      has_provider_config anthropic-newapi || [ -n "$K_ANTHROPIC" ] || ask_value "anthropic-newapi 的 API key(anthropic 协议 · 国产模型 · 网关 coding anthropic 分组)" K_ANTHROPIC 1
      has_provider_config gemini-newapi || [ -n "$K_GEMINI" ] || ask_value "gemini-newapi 的 API key(gemini 原生协议 · gemini 模型 · 网关 gemini 分组)" K_GEMINI 1
      has_embedding_config || [ -n "$K_EMBED" ] || ask_value "magic-context embedding 的 API key(openai 协议 · 嵌入模型 · 任意分组)" K_EMBED 1
      has_mem_config || [ -n "$K_MEM" ] || ask_value "claude-mem 的 API key(openai chat completions · mem-1 · coding openai / coding anthropic / codex / default 分组均可)" K_MEM 1
    fi
  fi
  [ "$need_mcp" = 1 ] && [ -z "$MCPHUB_HOST" ] && ask_value "mcphub MCP host(如 mcp.example.com)" MCPHUB_HOST
  if [ "$need_keys" = 1 ]; then
    gw_note="$GW_BASE"; [ -n "$gw_note" ] || gw_note="本机已有"; [ "$have_gw" = 1 ] || gw_note="未提供"
    echo "凭据:网关 $gw_note;已有配置未改动,未提供的缺项保留占位符"
  fi
  return 0
}

# 把已提供的值填进模板(python 负责 JSON 转义);未提供则原样保留占位符。
# <YOUR_GATEWAY_HOST> 填到主机名:pi 的 anthropic-messages provider 要根域(/v1 会 404),
# 而模板里的 <YOUR_GATEWAY_HOST>/v1 正好给 opencode/embedding/claude-mem 这类要 /v1 的。
# 四个 <YOUR_NEWAPI_API_KEY> 在同一份模板里对应不同 key,只能按 provider 块就近替换
# (不能全局 replace);embedding(magic-context 的 "api_key")与 claude-mem 按各自键名替,同样不全局换。
fill_template_placeholders() {
  [ -z "$GW_BASE$K_CLAUDE$K_CODEX$K_ANTHROPIC$K_GEMINI$K_EMBED$K_MEM$MCPHUB_HOST" ] && return 0
  python3 - "$1" "$GW_BASE" "$K_CLAUDE" "$K_CODEX" "$K_ANTHROPIC" "$K_GEMINI" "$K_EMBED" "$K_MEM" "$MCPHUB_HOST" <<'PYEOF'
import json, re, sys
p, base, k_claude, k_codex, k_anth, k_gemini, k_embed, k_mem, mcphub = sys.argv[1:10]
base = base.rstrip('/')
def esc(v): return json.dumps(v)[1:-1]
t = open(p, encoding='utf-8').read()
if base:
    # <YOUR_GATEWAY_HOST>/v1 这类槽位填完整 base(含路径);单独的 <YOUR_GATEWAY_HOST> 填主机名,
    # 因为 pi 的 anthropic-messages provider 要根域(/v1 会 404),模板自己在后面接 /v1。
    host = re.match(r'^(https?://[^/]+)', base)
    host = host.group(1) if host else base
    t = t.replace('https://<YOUR_GATEWAY_HOST>/v1beta', esc(host + '/v1beta'))
    t = t.replace('https://<YOUR_GATEWAY_HOST>/v1', esc(base))
    t = t.replace('<YOUR_GATEWAY_HOST>/v1', esc(base))
    t = t.replace('<YOUR_GATEWAY_HOST>', esc(re.sub(r'^https?://', '', host)))
    t = t.replace('<YOUR_NEWAPI_BASE_URL>', esc(base))
slot = '"apiKey": "<YOUR_NEWAPI_API_KEY>"'
names = {'claude-newapi': k_claude, 'codex-newapi': k_codex, 'anthropic-newapi': k_anth, 'gemini-newapi': k_gemini}
# 按 provider 名切块(到下一个 provider 名之前):只填该 provider 自己那处 apiKey,
# 已填过的块里没有槽位,不会把隔壁 provider 的 key 抢过来填。
blocks = [(m.start(), m.group(1)) for m in re.finditer(r'"(claude-newapi|codex-newapi|anthropic-newapi|gemini-newapi)"\s*:', t)]
for n, (start, name) in enumerate(blocks):
    end = blocks[n + 1][0] if n + 1 < len(blocks) else len(t)
    if names[name] and slot in t[start:end]:
        t = t[:start] + t[start:end].replace(slot, slot.replace('<YOUR_NEWAPI_API_KEY>', esc(names[name])), 1) + t[end:]
for anchor, key in (('"api_key": "<YOUR_API_KEY>"', k_embed),
                    ('"CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>"', k_mem)):
    if key and anchor in t:
        t = t.replace(anchor, anchor.replace('<YOUR_API_KEY>', esc(key)))
if mcphub:
    t = t.replace('<YOUR_MCPHUB_HOST>', esc(mcphub))
open(p, 'w', encoding='utf-8').write(t)
PYEOF
  return 0
}

# 画图凭据(~/.local/share/agent-skills/image-gen.json,image_gen 工具用):只补缺失字段,
# 已有 base_url/api_key 一律保留。检测规则与 image-gen/core.mjs 一致(第一个 openai 协议 provider);
# 拿不到 key 就不建文件——画图是可选能力,首次调用时工具自己提示。PI_IMAGE_GEN_API_KEY 可预填。
# opencode-setup.sh 里那份必须与这里逐字节一致。
ensure_image_gen() {
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || return 0
  python3 - "$HOME/.local/share/agent-skills/image-gen.json" "${GW_BASE:-}" \
    "${PI_IMAGE_GEN_API_KEY:-${IMAGE_GEN_API_KEY:-}}" "$HOME/.pi/agent/models.json" <<'PYEOF'
import json, os, re, sys
cfg, gw, key, models = sys.argv[1:5]
DEFAULT_MODEL = 'gpt-image-2.5-flare'
PLACEHOLDER = re.compile(r'^\s*<[^>]+>\s*$')
def ok(v): return isinstance(v, str) and v.strip() != '' and not PLACEHOLDER.match(v)
try:
    cur = json.load(open(cfg, encoding='utf-8'))
except FileNotFoundError:
    cur = {}
except Exception as e:
    print(f'image-gen: {cfg} 不是有效 JSON({e}),未改动'); sys.exit(0)
if not isinstance(cur, dict):
    cur = {}
det_base = det_key = ''
try:
    for p in json.load(open(models, encoding='utf-8')).get('providers', {}).values():
        if ok(p.get('apiKey')) and ok(p.get('baseUrl')) and str(p.get('api') or '').startswith('openai'):
            det_base, det_key = p['baseUrl'], p['apiKey']; break
except Exception:
    pass
base = cur['base_url'] if ok(cur.get('base_url')) else (gw if ok(gw) else det_base)
api_key = cur['api_key'] if ok(cur.get('api_key')) else (key if ok(key) else det_key)
if not (base and api_key):
    print(f'image-gen: 未配置(画图为可选项);需要时写 {cfg} 或设 PI_IMAGE_GEN_API_KEY')
    sys.exit(0)
new = dict(cur); new.setdefault('model', DEFAULT_MODEL)
new['base_url'] = base.rstrip('/'); new['api_key'] = api_key
if new == cur:
    print('image-gen: 已配置,保留本机值'); sys.exit(0)
os.makedirs(os.path.dirname(cfg), exist_ok=True)
with open(cfg, 'w', encoding='utf-8') as f:
    f.write(json.dumps(new, ensure_ascii=False, indent=2) + '\n')
os.chmod(cfg, 0o600)
print(('image-gen: 补齐缺失字段 -> ' if cur else 'image-gen: 写入凭据 -> ') + cfg)
PYEOF
  return 0
}

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

net_ok() { curl -fsSI --connect-timeout 5 -m 8 -o /dev/null https://github.com; }

# 只读探测:settings.json 的 packages 里是否已登记该 spec(按子串匹配,pi 会存相对/完整两种形式)
_pkg_registered() { [ -f "$SETTINGS" ] && grep -qF "$1" "$SETTINGS"; }

pkg_installed() { # $1=包 spec；本地路径按 AGENT_DIR 解析，兼容 Pi 写入的相对路径
  local target="$1"
  case "$target" in npm:*|git:*|http://*|https://*) ;; *) target="$(npath "$target")" ;; esac
  python3 - "$(npath "$SETTINGS")" "$target" "$(npath "$AGENT_DIR")" <<'PYEOF'
import json, os, sys
try:
    packages = json.load(open(sys.argv[1], encoding="utf-8")).get("packages") or []
except Exception:
    sys.exit(1)
target, agent_dir = sys.argv[2], os.path.abspath(sys.argv[3])
def source(package):
    value = package.get("source", "") if isinstance(package, dict) else package
    return value if isinstance(value, str) else ""
def resolve(value):
    if value.startswith(("npm:", "git:", "http://", "https://")):
        return value
    return os.path.normcase(os.path.realpath(os.path.join(agent_dir, value)))
wanted = resolve(target)
sys.exit(0 if any(source(p) == target or resolve(source(p)) == wanted for p in packages) else 1)
PYEOF
}

cm_package_entries() {
  [ -f "$SETTINGS" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$SETTINGS" <<'PY'
import json, sys
try:
    packages = json.load(open(sys.argv[1], encoding="utf-8")).get("packages") or []
except Exception:
    sys.exit(1)
for package in packages:
    value = package.get("source", "") if isinstance(package, dict) else package
    if isinstance(value, str):
        print(json.dumps(value))
PY
}
cm_vendor_in_settings() {
  cm_package_entries | python3 -c 'import json, os, sys
agent_dir = sys.argv[1]
managed_dir = os.path.normcase(os.path.normpath(os.path.join(agent_dir, "vendor/context-mode")))
for line in sys.stdin:
    value = json.loads(line).replace("\\", "/").rstrip("/")
    local = not value.startswith(("npm:", "git:", "http://", "https://"))
    candidate = os.path.normcase(os.path.normpath(value if os.path.isabs(value) else os.path.join(agent_dir, value)))
    if local and candidate == managed_dir:
        sys.exit(0)
sys.exit(1)' "$AGENT_DIR"
}
cm_conflicts_in_settings() {
  cm_package_entries | python3 -c 'import json, os, re, sys
agent_dir = sys.argv[1]
managed_dir = os.path.normcase(os.path.normpath(os.path.join(agent_dir, "vendor/context-mode")))
for line in sys.stdin:
    value = json.loads(line).replace("\\", "/").rstrip("/")
    local = not value.startswith(("npm:", "git:", "http://", "https://"))
    candidate = os.path.normcase(os.path.normpath(value if os.path.isabs(value) else os.path.join(agent_dir, value)))
    managed = local and candidate == managed_dir
    if managed:
        continue
    known_remote = bool(re.fullmatch(r"npm:context-mode(?:@[^/]+)?", value) or
                        re.fullmatch(r"(?:git:(?:https?://)?|https?://)github\.com/mksglu/context-mode(?:\.git)?(?:[@#].+)?", value, re.I))
    known_local = False
    if local:
        candidate = os.path.normpath(value if os.path.isabs(value) else os.path.join(agent_dir, value))
        try:
            known_local = json.load(open(os.path.join(candidate, "package.json"), encoding="utf-8")).get("name") == "context-mode"
        except Exception:
            pass
    if known_remote or known_local:
        print(json.dumps(value))' "$AGENT_DIR"
}

# ---- 前置计划:一次收集全部确认,执行阶段只看 PLAN_*,不再提问 ----
# 先只读探测现状,再集中 ask 设置 PLAN_*,最后收集网关/凭据。默认值与原来逐项询问时一致;
# 注入内容只写本宿主用户级规则文件，默认 Y。probe 与执行阶段用同一套判断,探测不到时执行阶段会再报。
collect_setup_plan() {
  local proxy pi_probe uvp uvcfg uv_cur uv_latest
  # 0. 代理(大小写都查;未设则探测直连;都不通才问)
  proxy="${http_proxy:-${https_proxy:-${all_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-${ALL_PROXY:-}}}}}}"
  if [ -n "$proxy" ]; then
    echo "代理: $proxy"
  elif net_ok 2>/dev/null; then
    echo "未设代理环境变量,但直连 github.com 可达(可能是透明代理),继续"
  else
    echo "提醒: 未检测到代理环境变量(大小写的 http(s)_proxy / all_proxy 都查了),且直连 github.com 不通。"
    echo "      建议先 export http_proxy/https_proxy 再继续;有透明代理则可忽略。"
    ask "仍要继续吗？" N SHARED_PROXY || exit 1
  fi

  # 1. Python 兜底(resolve_python3 用 PLAN_PYTHON_UV;本脚本不改它的 LOCKED 函数体)
  PLAN_PYTHON_UV=0
  if ! { command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1; } \
    && ! { command -v python >/dev/null 2>&1 && python -c pass >/dev/null 2>&1; } \
    && ! { command -v py >/dev/null 2>&1 && py -3 -c pass >/dev/null 2>&1; }; then
    ask "没有可用的 Python 3;用 uv 装一个自管理的 Python 3.12(会先装 uv 本体)?" Y SHARED_PYTHON_UV && PLAN_PYTHON_UV=1
  fi

  # 1.1 npx(fnm + Node)
  PLAN_NODE=0
  if ! command -v npx >/dev/null 2>&1; then
    ask "是否安装 fnm + Node LTS？" Y SHARED_NODE && PLAN_NODE=1
  fi

  # 1.2 bun
  PLAN_BUN=0
  if ! command -v bun >/dev/null 2>&1 && [ ! -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun$BIN_EXT" ]; then
    ask "是否安装 bun？" Y SHARED_BUN && PLAN_BUN=1
  fi

  # 1.2 Git Bash 启动文件(仅 Windows)
  PLAN_GIT_BASH=0
  if [ "$IS_WIN" = 1 ]; then
    ask '补齐 Git Bash 启动文件/Bun PATH及 mintty 缺省复制快捷键(已有配置保留,改前备份)?' Y PI_GIT_BASH && PLAN_GIT_BASH=1
  fi

  # 1.3 uv(可选):安装 / 自升级 / 清华镜像
  PLAN_UV_INSTALL=0; PLAN_UV_UPGRADE=0; PLAN_UV_MIRROR=0
  uvp="$HOME/.local/bin/uv$BIN_EXT"
  if ! command -v uv >/dev/null 2>&1 && [ ! -x "$uvp" ]; then
    ask "未检测到 uv,安装 uv(astral.sh 官方脚本,装到 ~/.local/bin)?" Y SHARED_UV_INSTALL && PLAN_UV_INSTALL=1
  fi
  # 自升级只针对已装的 uv(本次新装的由官方脚本给最新版)
  if command -v uv >/dev/null 2>&1 || [ -x "$uvp" ]; then
    uv_cur="$( (command -v uv >/dev/null 2>&1 && uv --version) 2>/dev/null | awk '{print $2}' || true)"
    uv_latest="$(curl -fsSL --connect-timeout 5 -m 8 https://api.github.com/repos/astral-sh/uv/releases/latest 2>/dev/null \
      | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
    if [ -z "$uv_latest" ]; then
      echo "跳过 uv 自升级:查不到最新版本(检查网络/代理)"
    elif [ "$uv_latest" != "$uv_cur" ]; then
      ask "uv ${uv_cur:-未知} → $uv_latest,升级(uv self update)?" Y SHARED_UV_UPGRADE && PLAN_UV_UPGRADE=1
    else
      echo "uv 已是最新(${uv_cur:-未知})"
    fi
  fi
  # 镜像:已装 uv 或本次将要安装时都按配置文件现状询问(新装的 uv 同样可配镜像)
  if command -v uv >/dev/null 2>&1 || [ -x "$uvp" ] || [ "$PLAN_UV_INSTALL" = 1 ]; then
    uvcfg="$HOME/.config/uv/uv.toml"
    if [ "$IS_WIN" = 1 ] && [ -n "${APPDATA:-}" ]; then uvcfg="$(cygpath -u "$APPDATA")/uv/uv.toml"; fi
    if grep -q 'pypi.tuna' "$uvcfg" 2>/dev/null; then
      echo "uv PyPI 镜像已配置(清华),跳过"
    elif [ -f "$uvcfg" ]; then
      echo "跳过 uv 镜像:$uvcfg 已存在(非本脚本写入),不覆盖"
    else
      ask "配置 uv 用清华 PyPI 镜像($uvcfg)?" Y SHARED_UV_MIRROR && PLAN_UV_MIRROR=1
    fi
  fi

  # 2/3. pi 本体、更新、缺失包
  PLAN_PI_INSTALL=0; PLAN_PI_UPDATE=0; PLAN_PI_PKGS=0
  pi_probe="$(command -v pi 2>/dev/null || true)"
  [ -x "$HOME/.local/share/pi-node/current/bin/pi" ] && pi_probe="$HOME/.local/share/pi-node/current/bin/pi"
  [ -n "$pi_probe" ] || { [ -x "$HOME/.local/share/pi-node/current/bin/pi" ] && pi_probe="$HOME/.local/share/pi-node/current/bin/pi"; }
  if [ -z "$pi_probe" ]; then
    if [ "$IS_WIN" = 1 ]; then
      if command -v npm >/dev/null 2>&1 || [ "$PLAN_NODE" = 1 ]; then
        ask "是否用 npm 全局安装 Pi(@earendil-works/pi-coding-agent)?" Y PI_INSTALL && PLAN_PI_INSTALL=1
      else
        echo "跳过 Pi 安装:未检测到 npm(先 winget install OpenJS.NodeJS.LTS,重开 Git Bash 后重跑)"
      fi
    else
      ask "是否安装 Pi(官方 install.sh,装到 ~/.local/share/pi-node)?" Y PI_INSTALL && PLAN_PI_INSTALL=1
    fi
  else
    ask "更新 pi 本体与已装包(逐个 pi update,不含 magic-context)?" Y PI_UPDATE && PLAN_PI_UPDATE=1
  fi
  # 缺失包:新装 Pi 时全部视为缺失(否则新机器不会装任何包);已装时按 settings.json 比对
  local missing=0 spec
  for spec in npm:@dietrichgebert/ponytail npm:pi-subagents-j0k3r npm:pi-lens \
              npm:@juicesharp/rpiv-ask-user-question npm:pi-background-tasks@2.6.10 \
              "$REPO_PI_SPEC" npm:@cortexkit/pi-magic-context; do
    pkg_installed "$spec" || missing=1
  done
  if [ "$AGENT_DIR" = "$HOME/.pi/agent" ]; then _pkg_registered npm:pi-autoname@0.6.8 || missing=1; fi
  if [ -n "$pi_probe" ]; then
    [ "$missing" = 1 ] && { ask "安装缺失的 Pi 包(ponytail/pi-subagents/pi-lens/rpiv-ask/background-tasks/autoname/本仓库/magic-context)?" Y PI_PKGS && PLAN_PI_PKGS=1; }
  elif [ "$PLAN_PI_INSTALL" = 1 ]; then
    ask "同时安装 Pi 包(ponytail/pi-subagents/pi-lens/rpiv-ask/background-tasks/autoname/本仓库/magic-context)?" Y PI_PKGS && PLAN_PI_PKGS=1
  fi

  # 3.1 magic-context:共享 context.db 的版本守卫(探测到不一致才问)
  # 执行段 mc_guard 与我们共用同一探测函数:opencode V2 把包放在 npm/<代次>/ 下,只查旧
  # packages/ 布局会把"已有缓存"误判成"没有缓存"而静默放行。
  PLAN_OC_CACHE_CLEAN=0; PLAN_MC_UPGRADE=0; PLAN_MC_FORCE=0; PLAN_MC_BLOCKED=0
  local oc_pinned_plan pi_latest_plan pi_plan_query_ok cache_plan_state
  if [ -n "$pi_probe" ] && command -v python3 >/dev/null 2>&1; then
    cache_plan_state="$(mc_cache_state)"; oc_pinned_plan=""
    if [ "$cache_plan_state" = present ]; then oc_pinned_plan="$(mc_cache_version)"; fi
    if [ -n "$oc_pinned_plan" ]; then
      pi_latest_plan=""; pi_plan_query_ok=0
      if command -v timeout >/dev/null 2>&1; then
        if pi_latest_plan="$(timeout 15 npm view @cortexkit/pi-magic-context version 2>/dev/null)" && [ -n "$pi_latest_plan" ]; then pi_plan_query_ok=1; fi
      else
        if pi_latest_plan="$(npm view @cortexkit/pi-magic-context version 2>/dev/null)" && [ -n "$pi_latest_plan" ]; then pi_plan_query_ok=1; fi
      fi
      if [ "$pi_plan_query_ok" != 1 ]; then
        PLAN_MC_BLOCKED=1
        echo "注意: 无法核实 magic-context 两端版本；默认不自动启用，不据此清理缓存。"
      elif [ "$oc_pinned_plan" != "$pi_latest_plan" ]; then
        PLAN_MC_BLOCKED=1
        echo "注意: magic-context 版本不一致 —— opencode 插件缓存 $oc_pinned_plan,Pi 扩展最新 $pi_latest_plan"
        echo "      两者共享 context.db,版本不一致时 Pi 主回合会被 fail-closed 拒绝。"
        if [ -d "$OC_MC_CACHE" ] && [ ! -e "${OC_NPM_CACHE:-}" ]; then
          ask "现在清理旧版 opencode 插件缓存目录?" N PI_OC_CACHE_CLEAN && PLAN_OC_CACHE_CLEAN=1
        fi
      fi
    elif [ "$cache_plan_state" != absent ]; then
      PLAN_MC_BLOCKED=1
      echo "注意: 发现 opencode 的 magic-context 缓存但读不出版本；默认不自动启用，不据此清理缓存。"
    fi
  fi
  if _pkg_registered npm:@cortexkit/pi-magic-context; then
    ask "现在升级 magic-context?(会迁移与 opencode 共享的 context.db;请放到两边都没人在用的时段做,两边版本必须一起升)" Y PI_MC_UPGRADE && PLAN_MC_UPGRADE=1
  elif [ "$PLAN_MC_BLOCKED" = 1 ]; then
    ask "仍要现在启用 Pi 版 magic-context(重启 opencode 前 Pi 主回合会被拒绝)?" N PI_MC_FORCE && PLAN_MC_FORCE=1
  fi

  # 3.2 context-mode:上游包卸载 / 旧路径摘除 / 发布包登记(合为一问)
  # 不依赖 python3:没有 Python 时用 grep 保守判断(Python 由执行段 resolve_python3 提供);
  # Pi 缺失但本次将安装时也要允许登记发布包,否则新机器插件不会登记。
  PLAN_CM_GROUP=0
  if [ -n "$pi_probe" ] || [ "$PLAN_PI_INSTALL" = 1 ]; then
    local cm_need_plan=0
    # 与执行段同一判据:缺 vendor 登记,或 vendor 之外仍有上游包/旧 clone 路径
    if ! cm_vendor_in_settings || [ -n "$(cm_conflicts_in_settings)" ]; then
      cm_need_plan=1
    fi
    [ "$cm_need_plan" = 1 ] && { ask "context-mode: 卸载上游包/摘掉旧路径/登记发布包(与 magic-context 抢同名工具,统一处理)?" Y PI_CM_GROUP && PLAN_CM_GROUP=1; }
  fi

  # 4. 原生 MCP 迁移(探测到需要迁移才问;无 python3 时不做版本门,执行段会再校验)
  PLAN_MCP_MIGRATE=0
  if [ -n "$pi_probe" ]; then
    local mcp_needed_plan=0 mcp_ver_ok=0
    if grep -qE 'pi-mcp-adapter|-builtin:mcp' "$SETTINGS" 2>/dev/null \
      || { [ -f "$HOME/.agents/mcp.json" ] && [ ! -f "$MCP_CONFIG" ]; }; then
      mcp_needed_plan=1
    fi
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$("$pi_probe" --version 2>/dev/null || echo 0)" <<'PY_MCP_VERSION' >/dev/null 2>&1 && mcp_ver_ok=1
import re, sys
m = re.match(r'(\d+)\.(\d+)\.(\d+)', sys.argv[1])
sys.exit(0 if m and tuple(map(int, m.groups())) >= (0, 99, 0) else 1)
PY_MCP_VERSION
    else
      mcp_ver_ok=1   # 保守列出;执行段用 resolve_python3 后的 Python 再校验版本
    fi
    if [ "$mcp_needed_plan" = 1 ] && [ "$mcp_ver_ok" = 1 ]; then
      ask "迁移到 Pi 原生 MCP?(备份配置、摘除 adapter 加载登记;旧共享配置不动,重开 Pi 生效)" N PI_MCP_MIGRATE && PLAN_MCP_MIGRATE=1
    fi
  fi

  # 4/6. 配置与 agent 文件写入(merge_cfg / deploy_file 统一用它,默认 Y)
  PLAN_WRITE_CFG=1
  ask "写入/更新 Pi 配置与 agent 文件(字段级合并,api key 等敏感值保留)?" Y PI_WRITE_CFG || PLAN_WRITE_CFG=0

  # 5. claude-mem runtime(npx 已存在,或本次 PLAN_NODE 会装好 npx 时都可前置选择)
  PLAN_MEM_RUNTIME=0
  if command -v npx >/dev/null 2>&1 || [ "$PLAN_NODE" = 1 ]; then
    ask "更新 claude-mem runtime 与 Pi 插件（会停止共享 worker，之后手工重启）?" Y PI_MEM_RUNTIME && PLAN_MEM_RUNTIME=1
  fi

  # 6.1 旧部署文件清理(合为一问)
  PLAN_LEGACY_CLEAN=0
  if [ -n "$pi_probe" ] && { [ -f "$AGENT_DIR/extensions/claude-mem.ts" ] \
    || [ -f "$AGENT_DIR/themes/onedark.json" ] \
    || [ -d "$AGENT_DIR/extensions/pi-pretty-tui" ]; }; then
    ask "把旧版部署文件/手工扩展移入 backups(官方 claude-mem/Pi 包已接管,统一处理)?" Y PI_LEGACY_CLEAN && PLAN_LEGACY_CLEAN=1
  fi

  # 7. skills 组与外部设计依赖:统一入口已在公共模式分发一次(AGENT_SKILLS_HOST_ONLY=1),
  #    宿主专用模式只写本宿主自己的用户级规则,这里不再询问或执行。
  PLAN_SKILL_RESEARCH=0; PLAN_SKILL_ACCEL=0; PLAN_SKILL_KB=0; PLAN_SKILL_PPT=0
  PLAN_SKILLS_EXTERNAL=1
  if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ]; then
    PLAN_SKILLS_EXTERNAL=0
  else
    ask "安装/更新 research 组(算法研究、实验、PyTorch 性能与 kernel;每次刷新·漂移自动备份)?" N SHARED_RESEARCH && PLAN_SKILL_RESEARCH=1
    ask "安装/更新 accel 组(算力平台模板;缺才装·本机特化不覆盖)?" N SHARED_ACCEL && PLAN_SKILL_ACCEL=1
    ask "安装/更新 kb 组(公共算力知识;每次刷新)?" N SHARED_KB && PLAN_SKILL_KB=1
    ask "安装/更新 ppt 组(南大 HTML/PPTX、Dashi、ppt-master 与独立依赖;需 Node 20+、Python 3.10+)?" N SHARED_PPT && PLAN_SKILL_PPT=1

    # 外部设计依赖；环境变量是已给出的前置答案，不覆盖
    case "${SKILLS_EXTERNAL:-}" in
      skip) PLAN_SKILLS_EXTERNAL=0 ;;
      install) ;;
      *) ask "安装/更新 3 个外部设计依赖(ui-ux-pro-max/huashu-design/design-taste-frontend;不装则降级为内置方法)?" Y SHARED_EXTERNAL || PLAN_SKILLS_EXTERNAL=0 ;;
    esac
  fi
  # 用户级 AGENTS 规则块:统一模式仍按 Pi 自己的偏好与路径单独写
  PLAN_AGENTS_TAIL=1
  case "${AGENTS_TAIL:-}" in
    0) PLAN_AGENTS_TAIL=0 ;;
    1) ;;
    *) # 旧键 SHARED_AGENTS_TAIL 只代表项目级同意：拒绝继续生效，同意不升级为全局同意。
       if [ "${PREF_REUSE:-0}" = 1 ] && [ "$(preference_get SHARED_AGENTS_TAIL || true)" = 0 ] \
          && ! preference_get PI_AGENTS_TAIL >/dev/null; then PLAN_AGENTS_TAIL=0
       elif ask "把记忆系统规范块写进 Pi 用户级 $AGENT_DIR/AGENTS.md(所有项目共用)?" Y PI_AGENTS_TAIL; then PLAN_AGENTS_TAIL=1
       else PLAN_AGENTS_TAIL=0; fi ;;
  esac

  # 凭据最后收集:只问这一处
  collect_gateway_values

  # 可选模块:两阶段,这里只取名单,执行阶段按名单安装
  # 源码基准在全部确认与凭据之后解析:此前不 clone、不 mkdir
  acquire_source || exit 1
  _AMOD="$SOURCE_ROOT/modules/run.sh"
  _mod_yes=""; [ "${ASSUME_YES:-0}" = 1 ] && _mod_yes="--yes"
  MODULE_SELECTION=""
  local saved_modules="" known_modules="" mod_env=("PATH=$PATH")
  if [ "${PREF_REUSE:-0}" = 1 ]; then
    saved_modules="$(preference_get PI_MODULES || true)"
    known_modules="$(preference_get PI_MODULES_KNOWN || true)"
    mod_env=("AGENT_SKILLS_MODULE_SELECTION=$saved_modules" "AGENT_SKILLS_MODULE_KNOWN=$known_modules")
  fi
  if [ -f "$_AMOD" ]; then
    if MODULE_SELECTION="$(env "${mod_env[@]}" bash "$_AMOD" --host pi --repo "${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}" \
      --ref "${AGENT_SKILLS_REF:-main}" $_mod_yes --select)"; then
      preference_put PI_MODULES "${MODULE_SELECTION//$'\n'/,}"
      if known_modules="$(bash "$_AMOD" --host pi --list)"; then
        known_modules="$(printf '%s\n' "$known_modules" | awk '{print $1}' | paste -sd, -)"
        preference_put PI_MODULES_KNOWN "$known_modules"
      fi
    else
      echo "WARN: 模块选择失败,本次不安装可选模块" >&2; MODULE_SELECTION=""
    fi
  else
    echo "WARN: 取不到 modules/run.sh,跳过可选模块" >&2
  fi
}

# merge_cfg <url> <dest> [mcp] — 拉本仓模板后做「字段级」合并,而非整文件覆盖:
#   模板中的非敏感字段值优先 → 新默认值能下发到服务器;
#   隐私内容永不覆盖:敏感键(api key / secret / token / password / credential / bearer / auth /
#     cookie / ingest / webhook / base_url / url / endpoint / host / 以 key 结尾)保留机器上已有值。
#     回归检查:tests/merge-private-preservation.py
#   模板里含 <占位符> 的值不覆盖本地已填内容;本地独有的键保留。
#   列表键 packages/enabledModels 走并集(本地顺序 + 模板新增);其余键模板优先,数组整体替换。
#   合并结果与本地一致时不写文件(幂等);有改动先存时间戳 .bak。
#   mcp 模式额外替换 <HOME>/<BUN_BIN>/<CODEGRAPH_BIN> 为本机路径。
#   dest 不存在则直接落模板。dest 是符号链接时写入链接目标,链接本身保留。
merge_cfg() {
  local url="$1" dest="$2" mode="${3:-}" tmp cand out target
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || { echo "跳过: $dest(前置计划未选择写入配置)"; return 2; }
  target="$(rpath "$dest")" || return 1
  # 操作员在提示里给了网关/密钥:先把本地文件里的占位符补上(改前存 .bak),再走正常合并
  # (补进去的是敏感键,合并会原样保留)。目标文件不存在时由模板侧的 fill_template_placeholders 负责。
  if [ -f "$dest" ] && [ -n "$GW_BASE$K_CLAUDE$K_CODEX$K_ANTHROPIC$K_GEMINI$K_EMBED$K_MEM$MCPHUB_HOST" ] && grep -q '<YOUR_' "$dest" 2>/dev/null; then
    cp -p "$dest" "$dest.bak-$(date +%Y%m%d%H%M%S)"
    fill_template_placeholders "$dest"
    echo "filled placeholders: $dest"
  fi
  tmp="$(mktemp)"
  echo "fetching: $url"
  if ! curl -fsSL --connect-timeout 8 -m 30 -o "$tmp" "$url"; then
    rm -f "$tmp"; echo "WARN: $url 下载失败,保留现有 $dest" >&2; return 1
  fi
  fill_template_placeholders "$tmp"
  # mintty 首次配置优先原生 scrollback/拖选;已有 tuiMode 在下方合并时保留。
  if [ "$dest" = "$SETTINGS" ] && [ "$IS_WIN" = 1 ] && [ "${TERM_PROGRAM:-}" = mintty ]; then
    python3 - "$tmp" <<'PY_MINTTY_MODE'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
d['tuiMode'] = 'regular'
with open(p, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
PY_MINTTY_MODE
  fi
  if [ "$mode" = mcp ]; then
    python3 - "$tmp" "$(npath "$HOME")" "$(nbin "$BUN_BIN")" "$(nbin "${CG_BIN:-codegraph}")" <<'PYEOF'
import sys
p, home, bun, cg = sys.argv[1:5]
t = open(p, encoding='utf-8').read()
t = (t.replace('<HOME>', home).replace('<BUN_BIN>', bun)
      .replace('<CODEGRAPH_BIN>', cg))
open(p, 'w', encoding='utf-8').write(t)
PYEOF
  fi
  if [ ! -f "$dest" ]; then
    mkdir -p "$(dirname "$target")"; cp "$tmp" "$target"; echo "wrote: $dest"
    rm -f "$tmp"
    return 0
  fi
  cand="$(mktemp)"
  out="$(python3 - "$dest" "$tmp" "$cand" <<'PYEOF'
import json, os, re, sys
dest, tpl = sys.argv[1], sys.argv[2]
SENSITIVE = re.compile(r'(api[_-]?key|secret|token|password|passwd|credential|bearer|auth|cookie|ingest|webhook|base[_-]?url|url|endpoint|host|(^|[._-])key$)', re.I)
PLACEHOLDER = re.compile(r'<[A-Za-z][A-Za-z0-9 _-]*>')

def load(p):  # JSONC 感知:去注释与尾逗号(字符串内的 // 不动)
    t = open(p, encoding='utf-8').read()
    out, i, n, instr = [], 0, len(t), False
    while i < n:
        c = t[i]
        if instr:
            out.append(c)
            if c == '\\': out.append(t[i + 1]); i += 2; continue
            if c == '"': instr = False
            i += 1; continue
        if c == '"': instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and t[i + 1] == '/':
            while i < n and t[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and t[i + 1] == '*':
            i += 2
            while i + 1 < n and not (t[i] == '*' and t[i + 1] == '/'): i += 1
            i += 2; continue
        out.append(c); i += 1
    return json.loads(re.sub(r'("(?:\\.|[^"\\])*")|,(\s*[}\]])', lambda m: m[1] or m[2], ''.join(out)))

try:
    cur, new = load(dest), load(tpl)
except Exception as e:
    print(f"WARN: {dest} 解析失败({e}),保留原文件不合并", file=sys.stderr)
    sys.exit(1)

# UI 模式是用户/终端偏好,重跑不能把已验证的 regular 又覆盖成 fullscreen。
# 例外:Windows 非 mintty 终端(如 Windows Terminal)里 regular 会让所有鼠标点击失效,
# 而侧栏是 overlay 挂载又会挡住 /settings 切换,只能按平台默认纠正。
if os.environ.get('TERM_PROGRAM') == 'mintty' or sys.platform != 'win32':
    if 'tuiMode' in cur:
        new['tuiMode'] = cur['tuiMode']
elif cur.get('tuiMode') == 'regular':
    new['tuiMode'] = 'fullscreen'
    print('WARN: tuiMode regular -> fullscreen(该终端下 regular 模式没有鼠标点击)', file=sys.stderr)

UNION_KEYS = ('packages', 'enabledModels')   # 列表型:并集而非整表替换,别把本机改动冲掉

def merge(cur, new):
    if not isinstance(new, dict) or not isinstance(cur, dict):
        return new
    out = dict(cur)
    for k, v in new.items():
        if k in cur and cur[k] is not None and cur[k] != '' and k.startswith('CLAUDE_MEM_') and k.endswith(('_BASE_URL', '_API_KEY', '_PORT', '_HOST')):
            continue  # 已有接口/凭据保留；模型名随模板
        if k in cur and cur[k] is not None and cur[k] != '' and SENSITIVE.search(k):                       # 敏感键:本地值优先
            continue
        if k in cur and cur[k] is not None and cur[k] != '' and isinstance(v, str) and PLACEHOLDER.search(v):  # 占位值不覆盖已填内容
            continue
        if k in UNION_KEYS and isinstance(v, list) and isinstance(cur.get(k), list):
            out[k] = cur[k] + [x for x in v if x not in cur[k]]        # 并集:本地顺序 + 模板新增
            continue
        out[k] = merge(cur.get(k), v) if isinstance(v, dict) else v
    return out

MANAGED_PROVIDERS = {"claude-newapi", "codex-newapi", "anthropic-newapi", "gemini-newapi"}
MANAGED_MCP = {"web", "codegraph"}

def managed_value(local, template):
    """模板控制结构；递归保留本机敏感叶子，模板未列出的条目不删除。"""
    if isinstance(template, list):
        if not isinstance(local, list):
            return template
        unused = [x for x in local if isinstance(x, dict) and x.get("id") is not None]
        out = []
        for item in template:
            match = None
            if isinstance(item, dict) and item.get("id") is not None:
                match = next((x for x in unused if x.get("id") == item.get("id")), None)
                if match is not None:
                    unused.remove(match)
            out.append(managed_value(match, item))
        return out
    if not isinstance(template, dict):
        return template
    out = dict(template)
    if not isinstance(local, dict):
        return out
    for k, v in local.items():
        if k == "maxTokens" and isinstance(v, (int, float)) and not isinstance(v, bool):
            continue  # 数值预算是受管非敏感字段，模板值已在 out 中。
        if SENSITIVE.search(k) and v is not None and v != '':
            out[k] = v
        elif isinstance(v, (dict, list)):
            nested = managed_value(v, out.get(k, {} if isinstance(v, dict) else []))
            if nested or k in out:
                out[k] = nested
    return out

def takeover_group(cur, new, merged, key, managed_names):
    old_group = cur.get(key) if isinstance(cur.get(key), dict) else {}
    tpl_group = new.get(key) if isinstance(new.get(key), dict) else {}
    if not tpl_group:
        return
    out_group = merged.get(key)
    if not isinstance(out_group, dict):
        out_group = {}
        merged[key] = out_group
    for name, template_value in tpl_group.items():
        if name in managed_names:
            out_group[name] = managed_value(old_group.get(name), template_value)

merged = merge(cur, new)
takeover_group(cur, new, merged, "providers", MANAGED_PROVIDERS)
takeover_group(cur, new, merged, "provider", MANAGED_PROVIDERS)
takeover_group(cur, new, merged, "mcpServers", MANAGED_MCP)
if isinstance(new.get("mcp"), dict) and isinstance(merged.get("mcp"), dict):
    takeover_group(cur.get("mcp") if isinstance(cur.get("mcp"), dict) else {},
                   new["mcp"], merged["mcp"], "servers", MANAGED_MCP)
# deprecated: memory-config-049；用户确认退役后删除此清理段。
if os.path.basename(dest) == "magic-context.jsonc":
    for key in ("clear_reasoning_age", "smart_drops", "sidekick"):
        merged.pop(key, None)
# deprecated: memory-config-049 结束。
if merged == cur:
    print("unchanged")
else:
    with open(sys.argv[3], 'w', encoding='utf-8') as f:
        json.dump(merged, f, indent=2, ensure_ascii=False)
        f.write("\n")
    top = [k for k in dict.fromkeys([*cur, *merged]) if cur.get(k) != merged.get(k)]
    print("变更: " + (", ".join(top) or "嵌套字段"))
PYEOF
)"
  rm -f "$tmp"
  local bak
  bak="$dest.bak-$(date +%Y%m%d%H%M%S)"
  case "$out" in
    unchanged) echo "unchanged: $dest(已与模板一致,无需改动)"; rm -f "$cand" ;;
    "")        echo "WARN: $dest 合并失败,保留原文件" >&2; rm -f "$cand"; return 1 ;;
    *)         cp "$dest" "$bak"; mv "$cand" "$target"; echo "updated: $dest" ;;
  esac
}

# 旧 UI 包(已被本仓库 UI 取代)留在 packages 里会双份加载,直接摘掉。
prune_legacy_ui_packages() {
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || return 0
  python3 - "$SETTINGS" <<'PY'
import json,sys,shutil,time
p=sys.argv[1]
legacy=("pi-zentui","pi-atelier","atelier-bridge")
try: d=json.load(open(p,encoding='utf-8'))
except Exception as e:
    print(f"WARN: 读取 {p} 失败({e}),跳过旧 UI 包清理",file=sys.stderr); sys.exit(0)
pkgs=d.get("packages") or []
def source(x):
    value = x.get("source", "") if isinstance(x, dict) else x
    return value if isinstance(value, str) else ""
kept=[x for x in pkgs if not any(s in source(x) for s in legacy)]
if kept==pkgs: sys.exit(0)
shutil.copy2(p,f"{p}.bak-ui-prune-{time.strftime('%Y%m%d%H%M%S')}")
d["packages"]=kept
json.dump(d,open(p,'w',encoding='utf-8'),indent=2,ensure_ascii=False); open(p,'a').write("\n")
removed=sorted(set(source(x) for x in pkgs if x not in kept))
print("removed legacy UI packages: "+", ".join(filter(None, removed)))
PY
}

# 记忆后端必须走 OpenAI 兼容的 openrouter provider;安装器或旧配置写成 claude 时纠正。
# 只改这一个键,模型/接口/凭据原样保留。
ensure_mem_provider() {
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || return 0
  local f="$1" tmp target
  [ -f "$f" ] || return 0
  target="$(rpath "$f")" || return 1
  grep -qE '"CLAUDE_MEM_PROVIDER"[[:space:]]*:[[:space:]]*"openrouter"' "$f" && return 0
  tmp="$(mktemp)"
  if python3 - "$f" "$tmp" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
d['CLAUDE_MEM_PROVIDER']='openrouter'
json.dump(d,open(sys.argv[2],'w',encoding='utf-8'),indent=2,ensure_ascii=False)
open(sys.argv[2],'a').write('\n')
PY
  then
    cp -p "$f" "$f.bak-provider-$(date +%Y%m%d%H%M%S)"
    mv "$tmp" "$target"; echo "updated: $f (CLAUDE_MEM_PROVIDER=openrouter)"
  else
    rm -f "$tmp"; echo "WARN: $f 解析失败,未改 provider;请手工设为 openrouter" >&2
  fi
}

# deploy_file <url> <dest> <label> — 整文件部署(用于 agents/*.md、extensions/*.ts):
#   内容一致则不写;有差异存 .bak 后覆盖;dest 是符号链接时写入链接目标
deploy_file() {
  local url="$1" dest="$2" label="$3" tmp target
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || { echo "跳过: $dest(前置计划未选择写入配置)"; return 2; }
  target="$(rpath "$dest")" || return 1
  tmp="$(mktemp)"
  if ! curl -fsSL --connect-timeout 8 -m 30 -o "$tmp" "$url"; then
    rm -f "$tmp"; echo "WARN: $label 下载失败,保留现有 $dest" >&2; return 1
  fi
  mkdir -p "$(dirname "$target")"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    echo "unchanged: $dest"; rm -f "$tmp"; return 0
  fi
  local bak=""
  [ -f "$dest" ] && bak="$dest.bak-$(date +%Y%m%d%H%M%S)"
  [ -n "$bak" ] && cp "$dest" "$bak"
  mv "$tmp" "$target"; echo "wrote: $dest"
}

echo "== Pi 一键配置 =="

# ---- 0. 前置计划:一次性收集全部确认(代理、依赖、安装/更新、写入、skills、模块)+ 凭据 ----
preferences_init
collect_setup_plan
preferences_commit

# ---- 1. 依赖(必需): curl / git / python3 ----
for tool in curl git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: 未检测到 $tool(下载模板/装依赖都要用它)。Git for Windows 自带 curl/git;Linux 用包管理器装(如 apt install $tool)。" >&2
    exit 1
  }
done
# python3 缺失不致命:resolve_python3 用 uv 自管理的 3.12 兜底(Git for Windows 不带 python)
resolve_python3 || { echo "ERROR: 没有可用的 Python 3(写配置依赖它)。可手工装(winget install Python.Python.3.12 / apt install python3)或允许脚本用 uv 装后重跑。" >&2; exit 1; }

# ---- 1.1 依赖: npx(fnm + Node)----
if ! command -v npx >/dev/null 2>&1; then
  echo "未检测到 npx(claude-mem 官方安装器、npm 包安装与 skills 安装需要 Node)。"
  if [ "${PLAN_NODE:-0}" = 1 ]; then
    curl -fsSL --connect-timeout 8 -m 60 https://fnm.vercel.app/install | bash
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env)"
    fnm install --lts
    fnm default lts-latest
    eval "$(fnm env)"
    command -v npx >/dev/null 2>&1 || {
      if [ "$IS_WIN" = 1 ]; then
        echo "ERROR: 安装后 npx 仍不可用。可改用 winget install OpenJS.NodeJS.LTS 装 Node,重开 Git Bash 后重跑本脚本。" >&2
      else
        echo "ERROR: 安装后 npx 仍不可用,请重开终端后重跑本脚本" >&2
      fi
      exit 1
    }
    echo "Node $(node --version) 就绪"
  else
    echo "跳过 Node(claude-mem 安装、pi 包与 skills 安装将不可用)"
  fi
fi

# ---- 1.2 依赖: bun ----
# 已安装但没进当前 PATH 时直接复用,也尊重自定义 BUN_INSTALL。
if [ "$IS_WIN" = 1 ] && [ -n "${BUN_INSTALL:-}" ]; then
  BUN_INSTALL="$(cygpath -u "$BUN_INSTALL")"; export BUN_INSTALL
fi
if [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun$BIN_EXT" ]; then
  export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
fi
if ! command -v bun >/dev/null 2>&1; then
  echo "未检测到 bun(claude-mem runtime 与 context-mode 所需依赖)。"
  if [ "${PLAN_BUN:-0}" = 1 ]; then
    curl -fsSL --connect-timeout 8 -m 60 https://bun.sh/install | bash
    export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
  else
    echo "跳过 bun；相关依赖由官方安装器检查。"
  fi
fi
# 只写真实存在的绝对路径;都没有时退化为裸命令名(交给运行时 PATH),别把猜测路径写进 MCP 配置
BUN_BIN="$(command -v bun 2>/dev/null || true)"; [ -n "$BUN_BIN" ] || BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun$BIN_EXT"
if [ -x "$BUN_BIN" ]; then
  "$BUN_BIN" --version && "$BUN_BIN" -e 'const {Database}=require("bun:sqlite"); const db=new Database(":memory:"); if(db.query("SELECT 1 AS ok").get().ok!==1) process.exit(1); db.close();' || {
    echo "ERROR: Bun 不能执行或 bun:sqlite 不可用;请修复 Bun 后重跑" >&2; exit 1;
  }
  ensure_git_bash_startup
else
  BUN_BIN=bun
fi

# ---- 1.3 依赖: uv(可选;strictdoc / .sdoc 校验用)----
UVP="$HOME/.local/bin/uv$BIN_EXT"
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$UVP" ]; then
  if [ "${PLAN_UV_INSTALL:-0}" = 1 ]; then
    uv_sh="$(mktemp)"
    if curl -fsSL --connect-timeout 8 -m 60 -o "$uv_sh" https://astral.sh/uv/install.sh; then
      UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$uv_sh" \
        || echo "WARN: uv 安装脚本退出码非 0,请看上方输出" >&2
    else
      echo "WARN: uv 安装脚本下载失败(检查代理)" >&2
    fi
    rm -f "$uv_sh"
  fi
fi
UV_BIN="$(command -v uv 2>/dev/null || echo "$UVP")"
if [ -x "$UV_BIN" ]; then
  export PATH="$HOME/.local/bin:$PATH"
  if [ "${PLAN_UV_UPGRADE:-0}" = 1 ]; then
    "$UV_BIN" self update || echo "WARN: uv 自升级失败(系统包管理器装的请用系统方式升级)" >&2
  fi
  UVCFG="$HOME/.config/uv/uv.toml"
  # uv 在 Windows 读 %APPDATA%\uv\uv.toml,不是 ~/.config
  if [ "$IS_WIN" = 1 ] && [ -n "${APPDATA:-}" ]; then UVCFG="$(cygpath -u "$APPDATA")/uv/uv.toml"; fi
  if [ "${PLAN_UV_MIRROR:-0}" = 1 ]; then
    mkdir -p "$(dirname "$UVCFG")"
    printf '%s\n' 'index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"' > "$UVCFG"
    echo "wrote: $UVCFG"
  fi
else
  echo "提示: 未检测到 uv;strictdoc 模块会跳过安装(.sdoc 校验依赖),装好 uv 后重跑本脚本即可"
fi

# ---- 2. pi 本体 ----
PI_BIN="$(command -v pi 2>/dev/null || true)"
if [ -x "$HOME/.local/share/pi-node/current/bin/pi" ]; then
  PI_BIN="$HOME/.local/share/pi-node/current/bin/pi"
  export PATH="$HOME/.local/share/pi-node/current/bin:$PATH"
fi
if [ -z "$PI_BIN" ]; then
  echo "未检测到 pi。"
  if [ "$IS_WIN" = 1 ]; then
    # Pi 官方 install.sh 在 Windows 上跑不了(内部 detect_node_binary_platform 只认 Darwin/Linux),
    # 走官方文档给的 npm 替代路径;Node/npm 由上面 1.1 的 fnm 提供。
    if ! command -v npm >/dev/null 2>&1; then
      echo "跳过 Pi 安装:未检测到 npm(先 winget install OpenJS.NodeJS.LTS,重开 Git Bash 后重跑)"
    elif [ "${PLAN_PI_INSTALL:-0}" = 1 ]; then
      npm install -g --ignore-scripts @earendil-works/pi-coding-agent || echo "WARN: npm 安装 Pi 失败,请看上方输出" >&2
      PI_BIN="$(command -v pi 2>/dev/null || true)"
    fi
  elif [ "${PLAN_PI_INSTALL:-0}" = 1 ]; then
    pi_sh="$(mktemp)"
    if curl -fsSL --connect-timeout 8 -m 60 -o "$pi_sh" https://pi.dev/install.sh; then
      sh "$pi_sh" || echo "WARN: pi 安装脚本退出码非 0,请看上方输出" >&2
    else
      echo "WARN: pi 安装脚本下载失败(检查代理)" >&2
    fi
    rm -f "$pi_sh"
    export PATH="$HOME/.local/share/pi-node/current/bin:$PATH"
    PI_BIN="$(command -v pi 2>/dev/null || true)"
    [ -n "$PI_BIN" ] || PI_BIN="$HOME/.local/share/pi-node/current/bin/pi"
  fi
fi
PI_OK=0
# 本仓库 Pi 包先准备新副本；只有准备成功才切换旧登记。
prepare_repo_pi_pkg() {
  [ -f "$REPO_PI_PKG/package.json" ] || {
    [ "${PLAN_PI_PKGS:-0}" = 1 ] || [ "${PLAN_PI_UPDATE:-0}" = 1 ] || return 1; }
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || return 0
  if [ "${PLAN_PI_PKGS:-0}" != 1 ] && [ "${PLAN_PI_UPDATE:-0}" != 1 ]; then
    echo "跳过: 未选择更新本仓库 Pi 本地包"; return 0
  fi
  local source_dir stage backup backup_base diff_rc n
  for source_dir in pi context-rewrite image-gen; do
    if [ ! -d "$SOURCE_ROOT/$source_dir" ] || [ -L "$SOURCE_ROOT/$source_dir" ]; then
      echo "WARN: Pi 源码目录缺失或是符号链接，保留旧副本: $source_dir" >&2; return 1
    fi
  done
  if [ ! -f "$SOURCE_ROOT/package.json" ] || [ ! -f "$SOURCE_ROOT/package-lock.json" ] ||
     [ -L "$SOURCE_ROOT/package.json" ] || [ -L "$SOURCE_ROOT/package-lock.json" ]; then
    echo "WARN: Pi 包清单或 lockfile 缺失、为符号链接，保留旧副本" >&2; return 1
  fi
  # 受管 vendor 不得写回候选树，也不能借 vendor 链接改写其他目录。
  if ! python3 - "$(npath "$AGENT_DIR")" "$(npath "$SOURCE_ROOT")" <<'PY'
import os, sys
agent, source = (os.path.normcase(os.path.realpath(p)) for p in sys.argv[1:3])
try:
    inside = os.path.commonpath([agent, source]) == source
except ValueError:
    inside = False
links = [os.path.join(agent, "vendor"), os.path.join(agent, "vendor", "agent-skills")]
sys.exit(1 if inside or any(os.path.islink(p) for p in links) else 0)
PY
  then
    echo "ERROR: Pi vendor 指向候选树或含符号链接，拒绝写入" >&2; return 1
  fi
  stage="$REPO_PI_PKG.tmp-$$"
  if ! rm -rf "$stage" || ! mkdir -p "$(dirname "$REPO_PI_PKG")"; then
    echo "WARN: Pi 暂存目录准备失败，保留旧副本" >&2; return 1
  fi
  if [ -d "$REPO_PI_PKG" ]; then
    if ! cp -a "$REPO_PI_PKG" "$stage"; then
      rm -rf "$stage"; echo "WARN: Pi 旧副本暂存失败，未替换" >&2; return 1
    fi
  elif ! mkdir -p "$stage"; then
    echo "WARN: Pi 暂存目录创建失败" >&2; return 1
  fi
  # 整目录刷新会同时退役已删除的 output-store；历史 context-output 文件不在受管目录内，保持不动。
  if ! rm -rf "$stage/pi" "$stage/context-rewrite" "$stage/image-gen" ||
     ! cp -a "$SOURCE_ROOT/pi" "$SOURCE_ROOT/context-rewrite" "$SOURCE_ROOT/image-gen" "$stage/" ||
     ! rm -rf "$stage/pi/node_modules" "$stage/context-rewrite/node_modules" "$stage/image-gen/node_modules" ||
     ! rm -rf "$stage/package.json" "$stage/package-lock.json" ||
     ! cp -a "$SOURCE_ROOT/package.json" "$SOURCE_ROOT/package-lock.json" "$stage/"; then
    rm -rf "$stage"; echo "WARN: Pi 源码复制失败，保留旧副本" >&2; return 1
  fi
  if [ ! -d "$stage/node_modules/acp-kernel" ] || ! cmp -s "$SOURCE_ROOT/package-lock.json" "$REPO_PI_PKG/package-lock.json"; then
    if ! (cd "$stage" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund); then
      rm -rf "$stage"; echo "WARN: Pi 本地包依赖安装失败，保留旧副本" >&2; return 1
    fi
  fi
  if [ -d "$REPO_PI_PKG" ] && [ ! -L "$REPO_PI_PKG/package.json" ] && [ ! -L "$REPO_PI_PKG/package-lock.json" ]; then
    diff_rc=0
    diff -qr -x node_modules -x .git "$REPO_PI_PKG" "$stage" >/dev/null 2>&1 || diff_rc=$?
    if [ "$diff_rc" = 0 ]; then
      rm -rf "$stage"; echo "unchanged: 本仓库 Pi 本地包"; return 0
    elif [ "$diff_rc" != 1 ]; then
      rm -rf "$stage"; echo "WARN: Pi 副本比较失败，保留旧副本" >&2; return 1
    fi
  fi
  backup_base="$REPO_PI_PKG.bak-$(date +%Y%m%d%H%M%S)-$$"
  backup="$backup_base"; n=0
  while [ -e "$backup" ]; do n=$((n + 1)); backup="$backup_base-$n"; done
  if [ -d "$REPO_PI_PKG" ] && ! mv "$REPO_PI_PKG" "$backup"; then
    rm -rf "$stage"; echo "WARN: Pi 旧包备份失败，未替换" >&2; return 1
  fi
  if ! mv "$stage" "$REPO_PI_PKG"; then
    [ ! -d "$backup" ] || mv "$backup" "$REPO_PI_PKG"
    rm -rf "$stage"; echo "WARN: Pi 本地包替换失败，已恢复旧副本" >&2; return 1
  fi
}
install_repo_pi_pkg() {
  local old_spec="git:github.com/brilliantrough/agent-skills"
  prepare_repo_pi_pkg || { echo "WARN: 本仓库 Pi 本地包未准备，保留现有登记" >&2; return 1; }
  [ "${PLAN_WRITE_CFG:-1}" = 1 ] || return 0
  if _pkg_registered "$old_spec"; then
    if pkg_installed "$REPO_PI_SPEC"; then
      "$PI_BIN" remove "$old_spec" < /dev/null || { echo "ERROR: 旧 git 包退役失败，仍存在双份登记" >&2; return 1; }
    else
      "$PI_BIN" remove "$old_spec" < /dev/null || { echo "ERROR: 旧 git 包退役失败，保留原登记" >&2; return 1; }
      if ! "$PI_BIN" install "$REPO_PI_SPEC" < /dev/null; then
        echo "WARN: 本地包登记失败，尝试恢复旧 git 登记" >&2
        "$PI_BIN" install "$old_spec" < /dev/null || echo "ERROR: 旧 git 登记恢复失败，请手工执行 pi install $old_spec" >&2
        return 1
      fi
    fi
  else
    pi_install "$REPO_PI_SPEC" || return 1
  fi
}
report_repo_pi_pkg() {
  local now
  now="$(git -C "$SOURCE_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  echo "本仓库 Pi 插件: $REPO_PI_PKG ← $SOURCE_ROOT (${now:-工作树})"
}
if [ -x "$PI_BIN" ]; then
  echo "pi 就绪: $("$PI_BIN" --version 2>/dev/null || echo 未知版本) ($PI_BIN)"
  PI_OK=1
  # 已登记包的更新清单:magic-context 一律排除(它与 opencode 侧共享 context.db,升级只能
  # 在两边都没人用的时段单独做,见步骤 3.1 的独立询问);本地路径包(context-mode fork)
  # 走步骤 3.2 的 release 比对,而 pi update 也不认这类 spec。
  pkg_filter() { # $1=1 只列 magic-context;$1=0 列其余可 update 的包
    python3 - "$SETTINGS" "$1" <<'PYEOF'
import json, sys
try:
    pkgs = json.load(open(sys.argv[1], encoding="utf-8")).get("packages") or []
except Exception:
    pkgs = []
only_mc = sys.argv[2] == "1"
for p in pkgs:
    s = str(p)
    if "pi-mcp-adapter" in s:
        continue
    if ("magic-context" in s) != only_mc:
        continue
    if not only_mc and not s.startswith(("npm:", "git:")):
        continue
    print(s)
PYEOF
  }
  # 默认 Y:除 magic-context 外逐个 pi update(不再用 --all —— 它会把 magic-context 一起拖下水)
  if [ "${PLAN_PI_UPDATE:-0}" = 1 ]; then
    "$PI_BIN" update pi --no-approve < /dev/null || echo "WARN: pi 本体更新失败(可稍后手动重试)" >&2
    while IFS= read -r spec; do
      [ -n "$spec" ] || continue
      "$PI_BIN" update "$spec" --no-approve < /dev/null || echo "WARN: $spec 更新失败" >&2
    done < <(pkg_filter 0)
    mc_left="$(pkg_filter 1)"
    if [ -n "$mc_left" ]; then echo "已跳过 magic-context(需在步骤 3.1 单独确认): $mc_left"; fi
  else
    # 静默跳过会让人以为"检查过了、没有新版":本步骤不跑,后面报告的"本次无更新"就只是
    # 上次留下的 HEAD,并不代表已是最新。
    echo "跳过: 未更新 pi 本体与已装包(含本仓库 Pi 插件);要更新请重跑并答 Y,或手动: $PI_BIN update --extensions"
  fi
else
  echo "WARN: 未找到 pi,跳过所有 Pi 相关配置(装好后重跑本脚本即可)" >&2
fi

# ---- 3. pi 包(pi install 幂等;写 ~/.pi/agent/settings.json 的 packages 数组)----
if [ "$PI_OK" -eq 1 ]; then
  pi_install() { # $1=spec
    if pkg_installed "$1"; then
      echo "已有: $1"
    elif [ "${PLAN_PI_PKGS:-0}" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
      "$PI_BIN" install "$1" < /dev/null || { echo "WARN: $1 安装失败(检查网络/代理)" >&2; return 1; }
    else
      echo "跳过: $1"
    fi
  }
  pi_install npm:@dietrichgebert/ponytail
  pi_install npm:pi-subagents-j0k3r
  pi_install npm:pi-lens
  pi_install npm:@juicesharp/rpiv-ask-user-question
  # 2.6.10 实测：11 个工具的模型可见 JSON 约 15.1k 字符、约 3.8k token；钉版，避免 latest 漂移。
  pi_install npm:pi-background-tasks@2.6.10
  # 0.6.8 上游将配置路径硬编码到 ~/.pi/agent,自定义 agent dir 暂不部署此插件。
  if [ "$AGENT_DIR" = "$HOME/.pi/agent" ]; then
    pi_install npm:pi-autoname@0.6.8
  else
    echo "WARN: pi-autoname 0.6.8 不遵循 PI_CODING_AGENT_DIR,跳过自动命名"
  fi
  # 本仓库自身：新副本准备成功后才切换登记，失败保留旧包。
  install_repo_pi_pkg || echo "WARN: 本仓库 Pi 包迁移未完成" >&2
  if pkg_installed "$REPO_PI_SPEC"; then report_repo_pi_pkg; else echo "WARN: 本仓库 Pi 本地路径包未登记" >&2; fi

  # ---- 3.1 magic-context:共享 context.db 的版本守卫(不一致时 Pi 主回合会被拒绝) ----
  # 升级后可再跑一次:重算两边版本差并重新提示
  mc_guard() {
  mc_blocked="${PLAN_MC_BLOCKED:-0}"
  cache_state="$(mc_cache_state)"
  if [ "$cache_state" = absent ]; then
    # 两处缓存都不存在:版本无从比较,按"未装缓存"放行(旧行为)。缓存被删后重启 opencode 会自建。
    mc_blocked=0
    return
  elif [ "$cache_state" != present ]; then
    mc_blocked=1
    echo "WARN: magic-context 缓存路径不可访问或链接不可解析；不自动启用" >&2
    return
  fi
  oc_pinned="$(mc_cache_version)"
  if [ -z "$oc_pinned" ]; then
    mc_blocked=1
    echo "WARN: magic-context 缓存清单不可读；不自动启用" >&2
    return
  fi
  pi_latest=""; pi_query_ok=0
  if command -v timeout >/dev/null 2>&1; then
    if pi_latest="$(timeout 15 npm view @cortexkit/pi-magic-context version 2>/dev/null)" && [ -n "$pi_latest" ]; then pi_query_ok=1; fi
  else
    if pi_latest="$(npm view @cortexkit/pi-magic-context version 2>/dev/null)" && [ -n "$pi_latest" ]; then pi_query_ok=1; fi
  fi
  if [ "$pi_query_ok" = 1 ] && [ "$oc_pinned" = "$pi_latest" ]; then
    mc_blocked=0
    return
  fi
  if [ "$pi_query_ok" = 1 ]; then
    mc_blocked=1
    echo ""
    echo "注意: magic-context 版本不一致 —— opencode 插件缓存 $oc_pinned,Pi 扩展最新 $pi_latest"
    echo "      两者共享 context.db,版本不一致时 Pi 主回合会被 fail-closed 拒绝。"
    echo "      请在两端都停用并备份后，通过 OpenCode 安装器同步插件版本。"
    if [ "${PLAN_OC_CACHE_CLEAN:-0}" = 1 ] && [ -d "$OC_MC_CACHE" ] && [ ! -e "${OC_NPM_CACHE:-}" ]; then
      rm -rf "$OC_MC_CACHE"
      echo "removed: $OC_MC_CACHE(重启 opencode 后自动重新下载)"
    fi
    echo ""
  else
    mc_blocked=1
    echo "WARN: 无法复查 magic-context 版本；不自动启用" >&2
  fi
  }
  mc_guard
  if pkg_installed npm:@cortexkit/pi-magic-context; then
    echo "已有: npm:@cortexkit/pi-magic-context(magic-context)"
    # 单独一问、默认 Y:升级会迁移两边共享的 context.db,必须在 OpenCode 与 Pi 都停用、
    # 没有会话在跑的时候做(夜里没人用的窗口),否则会打断正在使用的进程。
    if [ "${PLAN_MC_UPGRADE:-0}" = 1 ]; then
      if "$PI_BIN" update npm:@cortexkit/pi-magic-context --no-approve < /dev/null; then
        echo "  已升 Pi 侧；请核对 OpenCode 对应的插件版本后再启动两端。"
        mc_guard
      else
        echo "WARN: magic-context 升级失败(可稍后手动重试)" >&2
      fi
    else
      echo "跳过: magic-context 保持当前版本(需升级时脚本会再问一次,也可手动 pi update npm:@cortexkit/pi-magic-context)"
    fi
    [ "$mc_blocked" -eq 1 ] && echo "  WARN: 仍存在版本不一致,重启 opencode 前 Pi 记忆功能不可用"
  elif [ "$mc_blocked" -eq 1 ]; then
    if [ "${PLAN_MC_FORCE:-0}" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
      "$PI_BIN" install npm:@cortexkit/pi-magic-context < /dev/null || echo "WARN: magic-context 安装失败" >&2
    else
      echo "跳过: 暂不启用 Pi 版 magic-context(清理 opencode 插件缓存并重启后,重跑本脚本即可)"
    fi
  else
    pi_install npm:@cortexkit/pi-magic-context
  fi

  # ---- 3.2 context-mode fork(从 GitHub release 装;上游 npm 包会与 magic-context 抢 ctx_search)----
  CM_DIR="$AGENT_DIR/vendor/context-mode"
  CM_URL="https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz"
  cm_registered() {
    cm_vendor_in_settings
  }
  # 旧的 clone 路径条目必须摘掉(与 release 副本同时登记会让 Pi 启动失败)
  cm_stale="$(cm_conflicts_in_settings | python3 -c 'import json, os, sys
agent_dir = sys.argv[1]
for line in sys.stdin:
    value = json.loads(line).replace("\\", "/")
    local = not value.startswith(("npm:", "git:", "http://", "https://"))
    print(os.path.normpath(value if os.path.isabs(value) else os.path.join(agent_dir, value)) if local else value)' "$AGENT_DIR")"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    echo "WARN: 包列表里还登记着上游包／旧路径 $s —— 它和发布包副本会同时注册 ctxm_* 工具,Pi 启动会失败"
    if [ "${PLAN_CM_GROUP:-0}" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
      "$PI_BIN" remove "$s" < /dev/null || echo "WARN: 卸载失败,请手动 pi remove $s" >&2
    fi
  done <<< "$cm_stale"
  # 拉最新发布包:内容与已装的一致就不动(幂等),变了才替换
  cm_tmp="$(mktemp -d)"; cm_ok=0
  if ! command -v node >/dev/null 2>&1 || ! node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>24||a===24&&b>=15?0:1)' 2>/dev/null; then
    echo "WARN: context-mode v2 需要 Pi 实际运行的 Node >=24.15；保留现有安装，不更新。用 Node 24 启动 Pi 后重跑本步骤。" >&2
    cm_ok=1
  elif curl -fsSL --connect-timeout 8 -m 120 -o "$cm_tmp/vendor.tar.gz" "$CM_URL" 2>/dev/null && mkdir -p "$cm_tmp/pkg" && tar -xzf "$cm_tmp/vendor.tar.gz" -C "$cm_tmp/pkg"; then
    cm_ver="$(python3 -c "import json;print(json.load(open('$cm_tmp/pkg/VENDORED.json'))['upstream']['version'])" 2>/dev/null || echo '?')"
    if [ -d "$CM_DIR" ] && diff -rq "$cm_tmp/pkg" "$CM_DIR" >/dev/null 2>&1; then
      echo "已有: context-mode fork $cm_ver"
    else
      rm -rf "$CM_DIR"; mkdir -p "$(dirname "$CM_DIR")"; mv "$cm_tmp/pkg" "$CM_DIR"
      echo "已更新: context-mode fork → $cm_ver"
    fi
    cm_ok=1
  else
    echo "WARN: 下载/解包发布包失败（${CM_URL}）——网络问题?还是开发机还没 --publish?" >&2
  fi
  rm -rf "$cm_tmp"
  if [ "$cm_ok" = 1 ] && [ -d "$CM_DIR" ]; then
    if [ -n "$(cm_conflicts_in_settings)" ]; then
      echo "WARN: context-mode 上游包／旧路径仍未清除；不登记发布包，先手工消除同名工具冲突" >&2
    elif cm_registered; then
      echo "已登记: ${CM_DIR}（改动重启 Pi 生效）"
    elif [ "${PLAN_CM_GROUP:-0}" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
      "$PI_BIN" install "$CM_DIR" < /dev/null || echo "WARN: pi install $CM_DIR 失败" >&2
    fi
  fi
fi

# ---- 4. 部署 Pi 配置(字段级合并 本仓模板)----
# 凭据已在前置计划(collect_setup_plan)里收集,这里只按 PLAN_WRITE_CFG 决定是否写。
if [ "$PI_OK" -eq 1 ]; then
  mcp_ready=1
  if ! python3 - "$("$PI_BIN" --version)" <<'PY_MCP_VERSION'
import re, sys
match = re.match(r'(\d+)\.(\d+)\.(\d+)', sys.argv[1])
sys.exit(0 if match and tuple(map(int, match.groups())) >= (0, 99, 0) else 1)
PY_MCP_VERSION
  then
    mcp_ready=0
    echo "WARN: 原生 MCP 需要 Pi >= 0.99.0;请升级后重跑,不改现有 MCP/settings" >&2
  fi
  mcp_needed=0
  if [ "$mcp_ready" = 1 ]; then
    mcp_needed="$(python3 - "$SETTINGS" "$MCP_CONFIG" "$HOME/.agents/mcp.json" <<'PY_MCP_NEEDED'
import json, pathlib, sys
p, native, shared = map(pathlib.Path, sys.argv[1:])
d = json.loads(p.read_text(encoding='utf-8')) if p.exists() else {}
needed = 'pi-mcp-adapter' in json.dumps([d.get('packages', []), d.get('extensions', [])])
needed = needed or '-builtin:mcp' in d.get('extensions', [])
print(int(needed or (shared.exists() and not native.exists())))
PY_MCP_NEEDED
)" || mcp_ready=0
  fi
  if [ "$mcp_ready" = 1 ] && [ "$mcp_needed" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
    _mcp_migrate="$(mktemp)"
    if curl -fsSL --connect-timeout 8 -m 30 -o "$_mcp_migrate" "$SELF_RAW/pi/migrate-mcp.py" \
      && PI_CODING_AGENT_DIR="$(npath "$AGENT_DIR")" python3 "$_mcp_migrate"; then
      if [ "${PLAN_MCP_MIGRATE:-0}" = 1 ]; then
        PI_CODING_AGENT_DIR="$(npath "$AGENT_DIR")" python3 "$_mcp_migrate" --apply || mcp_ready=0
      else
        mcp_ready=0
      fi
    else
      mcp_ready=0
    fi
    rm -f "$_mcp_migrate"
  elif [ "$mcp_ready" = 1 ] && [ "$mcp_needed" = 1 ]; then
    echo "保留: 未选择写配置，跳过原生 MCP 迁移与模板合并"
  fi
  if [ "$mcp_ready" = 1 ]; then
    merge_cfg "$RAW/pi/settings.json" "$SETTINGS" || true
  else
    echo "WARN: 原生 MCP 迁移未完成,保留原 settings/MCP,不合并新模板" >&2
  fi
  if [ "$AGENT_DIR" = "$HOME/.pi/agent" ]; then
    merge_cfg "$RAW/pi/pi-autoname.json" "$AGENT_DIR/pi-autoname.json" || true
  fi
  merge_cfg "$RAW/pi/models.json" "$MODELS" || true
  CG_BIN="$(command -v codegraph 2>/dev/null || true)"; [ -n "$CG_BIN" ] || CG_BIN="$HOME/.local/bin/codegraph$BIN_EXT"
  [ -x "$CG_BIN" ] || CG_BIN=codegraph
  # deprecated: mcphub-web-rename；用户确认退役后删除此段及 migrate-web-mcp.py。
  if [ "${PLAN_WRITE_CFG:-1}" = 1 ] && [ "$mcp_ready" = 1 ] && grep -qs '"mcphub-web"[[:space:]]*:' "$MCP_CONFIG"; then
    web_migrate="$(mktemp)"
    if ! curl -fsSL --connect-timeout 8 -m 30 -o "$web_migrate" "$SELF_RAW/migrate-web-mcp.py" \
      || ! python3 "$web_migrate" pi "$(npath "$MCP_CONFIG")" --apply; then
      mcp_ready=0
      echo "WARN: web MCP 改名未完成，跳过 MCP 模板合并；其他配置继续部署" >&2
    fi
    rm -f "$web_migrate"
  fi
  # deprecated: mcphub-web-rename 结束。
  if [ "$mcp_ready" = 1 ]; then
    merge_cfg "$RAW/pi/mcp.json" "$MCP_CONFIG" mcp || true
    [ "${PLAN_WRITE_CFG:-1}" != 1 ] || [ ! -f "$MCP_CONFIG" ] || chmod 600 "$MCP_CONFIG"
  fi

  # ---- 4.05 凭据(auth.json,coding plan 等内置 provider)----
  # 只初始化缺失文件(占位符);已有条目的 key 是敏感值,合并时保留本地,不覆盖。
  auth_rc=0; merge_cfg "$RAW/pi/auth.json" "$AUTH" || auth_rc=$?
  if [ "$auth_rc" = 1 ] && [ ! -f "$AUTH" ]; then
    if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
      mkdir -p "$AGENT_DIR"
      cat > "$AUTH" <<'EOF'
{
  "zai-coding-cn": {
    "type": "api_key",
    "key": "<YOUR_ZAI_CODING_CN_API_KEY>"
  },
  "kimi-coding": {
    "type": "api_key",
    "key": "<YOUR_KIMI_API_KEY>"
  }
}
EOF
      echo "wrote: $AUTH(含占位符)"
    fi
  fi
  [ "${PLAN_WRITE_CFG:-1}" != 1 ] || [ ! -f "$AUTH" ] || chmod 600 "$AUTH"

fi

# 画图凭据放在 models.json 合并之后:检测要读的是填好 key 的那份
ensure_image_gen

# ---- 5. claude-mem:官方 runtime + Pi 插件 ----
# 官方安装器负责更新 ~/.claude/plugins/cache/... runtime 与 ~/.pi/agent/extensions/claude-mem；
# 本仓库不再复制 bundle 或维护第二套 Pi bridge。
[ "${PLAN_WRITE_CFG:-1}" != 1 ] || mkdir -p "$HOME/.claude-mem"
if ! command -v npx >/dev/null 2>&1; then
  echo "WARN: 未检测到 npx，跳过 claude-mem runtime/Pi 插件更新" >&2
elif [ "${PLAN_MEM_RUNTIME:-0}" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
  # 安装器会写 provider；退出时原样恢复共享 settings，不启动 worker。
  (
    saved="$(mktemp)"; chmod 600 "$saved"
    had_settings=0
    if [ -f "$MC_SETTINGS" ]; then cp -p "$MC_SETTINGS" "$saved" || exit 1; had_settings=1; fi
    restore_mem_settings() {
      if [ "$had_settings" = 1 ]; then
        cp -p "$saved" "$MC_SETTINGS" || { echo "ERROR: 请从 $saved 恢复 $MC_SETTINGS" >&2; exit 1; }
      else
        rm -f "$MC_SETTINGS"
      fi
      rm -f "$saved"
    }
    trap restore_mem_settings EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    PI_CODING_AGENT_DIR="$(npath "$AGENT_DIR")" npx -y claude-mem@latest install --ide pi --provider claude --no-auto-start < /dev/null || exit 1
  ) || echo "WARN: claude-mem 更新失败；请检查上方恢复提示" >&2
  ensure_mem_provider "$MC_SETTINGS"
fi

if [ "${PLAN_WRITE_CFG:-0}" = 1 ] && { [ "${PLAN_MEM_RUNTIME:-0}" = 1 ] || [ -f "$AGENT_DIR/extensions/claude-mem/index.js" ]; }; then
  [ -f "$AGENT_DIR/extensions/claude-mem/index.js" ] || { echo "ERROR: Pi claude-mem 扩展未就绪，不能启用 mem-search" >&2; exit 1; }
  node "$(npath "$SOURCE_ROOT/scripts/link-mem-search.mjs")" "$(npath "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")" "$(npath "$HOME/.agents/skills")"
fi

# deprecated: claude-mem-legacy 迁移段；用户确认退役后整段删除。
if [ "${PLAN_WRITE_CFG:-0}" = 1 ] && { [ "${PLAN_MCP_MIGRATE:-0}" = 1 ] || [ "${PLAN_MEM_RUNTIME:-0}" = 1 ] || [ "${PLAN_LEGACY_CLEAN:-0}" = 1 ]; } \
   && [ -f "$AGENT_DIR/extensions/claude-mem/index.js" ] && [ -f "$MCP_CONFIG" ]; then
  python3 - "$(npath "$MCP_CONFIG")" "$(npath "$HOME")" <<'PY_MEM_MIGRATE' || echo "WARN: claude-mem 旧 MCP 迁移失败，保留原配置" >&2
import json, re, shutil, sys
from datetime import datetime
from pathlib import Path
path, home = Path(sys.argv[1]), sys.argv[2].replace('\\', '/').rstrip('/')
text = path.read_text(encoding='utf-8')
string = r'"(?:\\.|[^"\\])*"'
text = re.sub(f'({string})|//[^\n]*|/\\*[\\s\\S]*?\\*/', lambda m: m[1] or '', text)
text = re.sub(f'({string})|,(\\s*[}}\\]])', lambda m: m[1] or m[2], text)
config = json.loads(text)
servers = config.get('mcpServers', {})
entry = servers.get('claude-mem')
if entry is None:
    sys.exit(0)
expected = home + '/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs'
args = entry.get('args', []) if isinstance(entry, dict) else []
script = str(args[0]).replace('\\', '/') if isinstance(args, list) and len(args) == 1 else ''
command = str(entry.get('command', '')).replace('\\', '/') if isinstance(entry, dict) else ''
if (script not in (expected, '<MCP_CJS>')
        or command.split('/')[-1] not in ('bun', 'bun.exe', 'node', 'node.exe', '<BUN_BIN>')
        or set(entry) - {'command', 'args', 'exposure', 'description'}):
    print('WARN: 保留自定义 claude-mem MCP；如不需要额外工具，可手工移除')
    sys.exit(0)
backup = path.with_name(path.name + '.bak-claude-mem-' + datetime.now().strftime('%Y%m%d%H%M%S%f'))
shutil.copy2(path, backup)
del servers['claude-mem']
path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'migrated: 删除旧模板 claude-mem MCP，改用官方原生 mem_* 工具；备份 {backup}')
PY_MEM_MIGRATE
elif [ "${PLAN_WRITE_CFG:-0}" = 1 ] && { [ "${PLAN_MCP_MIGRATE:-0}" = 1 ] || [ "${PLAN_MEM_RUNTIME:-0}" = 1 ] || [ "${PLAN_LEGACY_CLEAN:-0}" = 1 ]; } && [ -f "$MCP_CONFIG" ]; then
  echo "WARN: Pi 官方 claude-mem 扩展未就绪，暂不迁移旧 MCP" >&2
fi
# deprecated: claude-mem-legacy 迁移段结束。

# ---- 6. 共用配置:claude-mem settings + magic-context.jsonc(与 opencode-setup.sh 同一套;下载失败用内嵌兜底)----
[ "${PLAN_WRITE_CFG:-1}" != 1 ] || mkdir -p "$HOME/.claude-mem"
mc_rc=0; merge_cfg "$RAW/opencode/claude-mem.settings.json" "$MC_SETTINGS" || mc_rc=$?
# 含密钥/本机路径的配置统一 600(对齐 codex-setup.sh 的 umask 077);文件可能还不存在
if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then chmod 600 "$MODELS" "$AUTH" "$MC_SETTINGS" "$MC_CFG" 2>/dev/null || true; fi
ensure_mem_worker_keys "$MC_SETTINGS" 2>/dev/null || true
echo "claude-mem worker: http://$(mem_worker_url "$MC_SETTINGS")(健康检查: curl -s http://$(mem_worker_url "$MC_SETTINGS")/api/health)"
if [ "$mc_rc" = 1 ] && [ ! -f "$MC_SETTINGS" ]; then
  if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
  cat > "$MC_SETTINGS" <<'EOF'
{
  "CLAUDE_MEM_RUNTIME": "worker",
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_MODE": "code--zh",
  "CLAUDE_MEM_QUOTA_FALLBACK_PROVIDER": "off",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "<YOUR_NEWAPI_BASE_URL>",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-1",
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "30",
  "CLAUDE_MEM_CONTEXT_SESSION_COUNT": "5",
  "CLAUDE_MEM_CONTEXT_FULL_COUNT": "0",
  "CLAUDE_MEM_CONTEXT_SHOW_LAST_SUMMARY": "true",
  "CLAUDE_MEM_LLM_TIMEOUT_MS": "120000",
  "CLAUDE_MEM_SKIP_TOOLS": "ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>"
}
EOF
  echo "wrote: $MC_SETTINGS(含占位符)"
  else
    echo "跳过: $MC_SETTINGS 未创建"
  fi
fi

mcc_rc=0; merge_cfg "$RAW/opencode/magic-context.jsonc" "$MC_CFG" || mcc_rc=$?
if [ "$mcc_rc" = 1 ] && [ ! -f "$MC_CFG" ]; then
  if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
  mkdir -p "$HOME/.config/cortexkit"
  cat > "$MC_CFG" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/cortexkit/magic-context/master/assets/magic-context.schema.json",
  "language": "zh",
  "todowrite": { "enabled": true, "overlay": false },
  "historian": {
    "opencode": {
      "model": "anthropic-newapi/deepseek-flash"
    },
    "pi": {
      "model": "anthropic-newapi/deepseek-flash"
    }
  },
  "embedding": {
    "provider": "openai-compatible",
    "model": "text-embedding-3-large",
    "endpoint": "<YOUR_NEWAPI_BASE_URL>",
    "api_key": "<YOUR_API_KEY>"
  },
  "dreamer": {
    "opencode": {
      "model": "anthropic-newapi/deepseek-flash"
    },
    "pi": {
      "model": "anthropic-newapi/deepseek-flash"
    }
  }
}
EOF
  echo "wrote: $MC_CFG(含占位符;historian/dreamer 的 model 用 <provider>/<model-id>)"
  else
    echo "跳过: $MC_CFG 未创建"
  fi
fi

# deprecated: claude-mem-legacy 的旧 bridge 退役；用户确认后删除该文件迁移项。
# ---- 6.1 旧 bridge/主题已迁入官方或 git 包，散装文件移入 backups ----
if [ "$PI_OK" -eq 1 ]; then
  if pkg_installed "$REPO_PI_SPEC"; then
    for legacy in "$AGENT_DIR/extensions/claude-mem.ts" "$AGENT_DIR/themes/onedark.json"; do
      if [ "$legacy" = "$AGENT_DIR/extensions/claude-mem.ts" ] && [ ! -f "$AGENT_DIR/extensions/claude-mem/index.js" ]; then
        echo "WARN: 官方 claude-mem 扩展未就绪，保留旧 bridge" >&2
        continue
      fi
      if [ -f "$legacy" ] && [ ! -L "$legacy" ]; then
        if [ "${PLAN_LEGACY_CLEAN:-0}" = 1 ]; then
          legacy_dest="$AGENT_DIR/backups/legacy-claude-mem-$(date +%Y%m%d%H%M%S)/$(basename "$legacy")"
          mkdir -p "$(dirname "$legacy_dest")" && mv "$legacy" "$legacy_dest" && echo "moved: $legacy -> $legacy_dest"
        fi
      fi
    done
    # 手拷到 ~/.pi/agent/extensions 的 pi-pretty-tui:包内(pi/extensions/pretty-tui)已提供同一份,
    # 两份同时加载会重复注册内置工具。移到 backups 而不是删,误判可恢复。
    if [ -d "$AGENT_DIR/extensions/pi-pretty-tui" ] && [ -f "$REPO_PI_PKG/pi/extensions/pretty-tui/index.ts" ]; then
      if [ "${PLAN_LEGACY_CLEAN:-0}" = 1 ]; then
        pp_dest="$AGENT_DIR/backups/pi-pretty-tui-$(date +%Y%m%d%H%M%S)"
        mkdir -p "$AGENT_DIR/backups" && mv "$AGENT_DIR/extensions/pi-pretty-tui" "$pp_dest" && echo "moved: $pp_dest"
      fi
    fi
  fi
  # ---- 6. subagent 定义 + 个性化 UI 配置(仓库模板整文件覆盖;有差异先存 .bak)----
  # 不做一次性迁移:仓库模板就是当前已验证的配置,直接覆盖。
  # 想保留本机在 /ui 里的改动,就把它同步回模板,否则下次 setup 会覆盖回去。
  prune_legacy_ui_packages
  deploy_file "$RAW/pi/agent-skills-ui.json" "$AGENT_DIR/agent-skills-ui.json" "个性化 UI 布局/侧栏" || true
  deploy_file "$RAW/pi/agent-skills-editor.json" "$AGENT_DIR/agent-skills-editor.json" "个性化 UI 编辑器/页脚" || true
  deploy_file "$RAW/pi/keybindings.json" "$AGENT_DIR/keybindings.json" "按键(Enter 发送、Shift+Enter 换行等)" || true
  deploy_file "$RAW/pi/agents/explore.md" "$AGENT_DIR/agents/explore.md" "explore 子代理" || true
  deploy_file "$RAW/pi/agents/general.md" "$AGENT_DIR/agents/general.md" "general 子代理" || true
  deploy_file "$RAW/pi/agents/consolidation-reviewer.md" "$AGENT_DIR/agents/consolidation-reviewer.md" "整理审查子代理" || true
  deploy_file "$RAW/pi/agents/verification-reviewer.md" "$AGENT_DIR/agents/verification-reviewer.md" "功能复核子代理" || true
fi

# ---- 7. skills 本体 ----
# 分组 = 仓库 skills/{base,research,accel,kb,ppt}/ 目录,策略由 skills-sync.sh 执行:
# base/research 每次刷新且漂移先备份;accel 缺才装(本机特化不覆盖);kb 每次刷新。
# 客户端实体直落 ~/.agents/skills/<名>(装了 Claude Code 时同步 ~/.claude/skills/<名>)。
# 同步器随后用 npx skills 补装外部设计依赖、更新已登记第三方。
if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ]; then
  # 统一入口已一次性分发公共 Skill 与外部设计依赖;这里只写 Pi 自己的用户级规则块,
  # 仍按 PI_AGENTS_TAIL 的同意结果与 PI_CODING_AGENT_DIR 路径。
  if [ "${PLAN_AGENTS_TAIL:-1}" = 1 ]; then
    _mt="$SOURCE_ROOT/scripts/migrate-agents-tail.py"
    if [ -f "$_mt" ]; then
      PI_CODING_AGENT_DIR="$AGENT_DIR" python3 "$_mt" --sync-host pi \
        || { echo "ERROR: Pi 用户级规则块写入失败，项目与全局 AGENTS 均未改动" >&2; tail_sync_failed=1; }
    else
      echo "ERROR: 源码树缺 scripts/migrate-agents-tail.py，无法写入用户级规则块；项目与全局 AGENTS 均未改动" >&2
      tail_sync_failed=1
    fi
  fi
else
  _ss="$SOURCE_ROOT/skills-sync.sh"
  if [ -f "$_ss" ]; then
    SKILL_GROUPS=(base)
    [ "${PLAN_SKILL_RESEARCH:-0}" = 1 ] && SKILL_GROUPS+=(research)
    [ "${PLAN_SKILL_ACCEL:-0}" = 1 ] && SKILL_GROUPS+=(accel)
    [ "${PLAN_SKILL_KB:-0}" = 1 ] && SKILL_GROUPS+=(kb)
    [ "${PLAN_SKILL_PPT:-0}" = 1 ] && SKILL_GROUPS+=(ppt)
    _ext="skip"; [ "${PLAN_SKILLS_EXTERNAL:-1}" = 1 ] && _ext="install"
    _tail=0; [ "${PLAN_AGENTS_TAIL:-1}" = 1 ] && _tail=1
    # 旧缓存里的 skills-sync 仍写当前项目:委派前先确认它自己走用户级 helper,否则规则块不交给它。
    if [ "$_tail" = 1 ] && ! grep -q 'migrate-agents-tail.py' "$_ss"; then
      echo "ERROR: 源码树 skills-sync.sh 不是用户级规则版本(缺 scripts/migrate-agents-tail.py);本次不改项目/全局 AGENTS,请更新源码树后重跑" >&2
      _tail=0; tail_sync_failed=1
    fi
    AGENTS_TAIL="$_tail" AGENTS_TAIL_HOST=pi PI_CODING_AGENT_DIR="$AGENT_DIR" \
      SKILLS_EXTERNAL="$_ext" ASSUME_YES="${ASSUME_YES:-0}" \
      AGENT_SKILLS_SOURCE="$SOURCE_ROOT" \
      bash "$_ss" "${SKILL_GROUPS[@]}" || echo "WARN: skills 同步未完全成功" >&2
  else
    echo "WARN: 源码树缺 skills-sync.sh,跳过 skills 同步" >&2
    [ "${PLAN_AGENTS_TAIL:-1}" = 1 ] && { echo "ERROR: 无法写入记忆系统规则块,项目与全局 AGENTS 均未改动" >&2; tail_sync_failed=1; }
  fi
fi

# ---- 可选模块:前置阶段已选好名单,这里只执行 ----
if [ -n "${_AMOD:-}" ]; then
  bash "$_AMOD" --host pi --repo "${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}" \
    --ref "${AGENT_SKILLS_REF:-main}" --selected "$MODULE_SELECTION" || { echo 'ERROR: Pi 所选模块未完成' >&2; exit 1; }
else
  echo "WARN: 未取得 modules/run.sh,跳过可选模块" >&2
fi

# ---- 自检:UI 到底会不会生效(这几个是"没生效"的常见原因)----
echo ""
# ---- 9. 开发本仓库时的类型诊断软链(仅本地;不影响运行)----
# 仓库不装 node_modules,Pi 运行时自己提供这些模块;但编辑器/pi-lens 的 TS 诊断会报
# “Cannot find module '@earendil-works/pi-*' / 'node:*'” 这类假报错。把已装 Pi 包软链进
# 仓库 node_modules 即可消失(node_modules 已在 .gitignore 中排除,不会被提交)。
link_dev_types() {
  [ -f "$PWD/pi/extensions/ui/index.ts" ] || return 0   # 只在仓库源码目录里跑
  case "$(pwd -P)/" in "$SOURCE_ROOT/"*) echo "类型诊断软链: 跳过(候选源码树只读)"; return 0 ;; esac
  # Windows 上 ln -s 需要开发者模式,否则 MSYS 会退化成整目录深拷贝(pi 包很大),直接跳过
  if [ "$IS_WIN" = 1 ]; then echo "类型诊断软链: Windows 跳过"; return 0; fi
  local pkg=""
  if [ -n "${PI_BIN:-}" ]; then
    pkg="$(readlink -f "$PI_BIN" 2>/dev/null || true)"
    case "$pkg" in */dist/bundle/cli.js) pkg="${pkg%/dist/bundle/cli.js}" ;; *) pkg="" ;; esac
  fi
  [ -d "$pkg/node_modules" ] || pkg="$HOME/.local/share/pi-node/current/lib/node_modules/@earendil-works/pi-coding-agent"
  if [ ! -d "$pkg/node_modules" ]; then
    echo "类型诊断软链: 跳过(未找到 Pi 包目录)"; return 0
  fi
  mkdir -p "$PWD/node_modules/@earendil-works" "$PWD/node_modules/@types"
  [ -e "$PWD/node_modules/@earendil-works/pi-coding-agent" ] || \
    ln -sfn "$pkg" "$PWD/node_modules/@earendil-works/pi-coding-agent"
  [ -e "$PWD/node_modules/@earendil-works/pi-tui" ] || \
    ln -sfn "$pkg/node_modules/@earendil-works/pi-tui" "$PWD/node_modules/@earendil-works/pi-tui"
  [ -e "$PWD/node_modules/@types/node" ] || \
    ln -sfn "$pkg/node_modules/@types/node" "$PWD/node_modules/@types/node"
  echo "类型诊断软链: node_modules/@earendil-works/* + @types/node 就绪(仅本机,已被 .gitignore 排除)"
}
link_dev_types

echo "本机自检:"
PI_PKG_DIR="$REPO_PI_PKG"
if [ -f "$PI_PKG_DIR/package.json" ]; then
  echo "  UI 包(local): $PI_PKG_DIR ← $(git -C "$SOURCE_ROOT" rev-parse --short HEAD 2>/dev/null || echo 工作树)"
else
  echo "  UI 包(local): 未安装 -> 检查步骤 3 的 $REPO_PI_SPEC"
fi
if pkg_installed "$REPO_PI_SPEC"; then
  echo "  packages[]: 已登记本地源码 $REPO_PI_SPEC"
else
  echo "  packages[]: 未登记(扩展不会被加载;可运行: pi install \"$REPO_PI_SPEC\")"
fi
# context-mode fork:本地路径包,登记了才会加载(改完只需重启 pi)
python3 - "$SETTINGS" <<'PYEOF'
import json, sys
try:
    pkgs = json.load(open(sys.argv[1], encoding="utf-8")).get("packages") or []
except Exception:
    pkgs = []
print("  packages[]: context-mode fork " + ("已登记" if any("vendor/context-mode" in str(p) for p in pkgs) else "未登记(bash context-mode/setup.sh --publish 后重跑本脚本)"))
PYEOF
ui_mode="$(python3 - "$SETTINGS" <<'PYEOF'
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get("tuiMode") or "(未设置=regular)")
except Exception:
    print("(无法读取)")
PYEOF
)"
echo "  tuiMode: $ui_mode  (侧栏/分栏需要 fullscreen)"
for f in "$AGENT_DIR/agent-skills-ui.json" "$AGENT_DIR/agent-skills-editor.json" "$AGENT_DIR/keybindings.json"; do
  [ -f "$f" ] && echo "  配置: $f" || echo "  配置缺失: $f"
done
echo "  扩展/配置改动后要重启 pi(或 /reload)才生效"

# ---- 完成:占位符清单 + 收尾动作 ----
echo ""
echo "== done. 需要你手工完成的 =="
n=1
echo "$n. 网关/凭据:脚本启动时已问过「统一网关 + 6 个 api key」并填进各配置(可用环境变量预填、非交互跑:PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY / MCPHUB_HOST)"; n=$((n+1))
echo "   当时跳过了才会剩下占位符(<YOUR_*>):"
_ph=0
for _f in "$MODELS" "$AUTH" "$MCP_CONFIG" "$MC_SETTINGS" "$MC_CFG" "$HOME/.func"; do
  if [ -f "$_f" ] && grep -q '<YOUR_' "$_f" 2>/dev/null; then
    echo "   - $_f:$(grep -o '<YOUR_[A-Z_]*>' "$_f" | sort -u | tr '\n' ' ')"; _ph=1
  fi
done
[ "$_ph" = 0 ] && echo "   (无,凭据已齐)"
echo "   提示:claude-mem 走 openrouter(OpenAI 协议),它的 key 与 magic-context embedding 的各自独立;historian/dreamer 的 model 用 <provider>/<model-id>"
echo "$n. 重启 claude-mem worker 并验证:"; n=$((n+1))
echo "      cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart"
echo "      curl -s http://$(mem_worker_url "$MC_SETTINGS")/api/health   # 端口取自 $MC_SETTINGS(见下方提示)"
echo "$n. 记忆系统规则:已按计划写入 Pi 用户级 $AGENT_DIR/AGENTS.md(或跳过);项目自身的 AGENTS.md 保持原样,项目规则仍写在仓库里"; n=$((n+1))
if [ -x "${CG_BIN:-}" ]; then
  echo "$n. 代码知识图谱(按项目):cd <项目> && codegraph init(建 .codegraph/ 索引;不 init 则 MCP 无内容可查)"; n=$((n+1))
fi
echo "$n. 重启 pi(新配置生效;pi 内 /model 可查看已配置模型)"; n=$((n+1))
echo "   MCP: pi mcp list 检查连接;Pi 内 /mcp 管理服务器,tool_search 发现工具、codemode 批量调用"
[ "${mc_blocked:-0}" -eq 1 ] && echo "!! magic-context 版本尚未对齐：停用两端并备份后同步插件，再重跑本脚本"
[ "${tail_sync_failed:-0}" = 0 ] || { echo "ERROR: 记忆系统规则块未写入(源码树缺用户级同步实现),项目与全局 AGENTS 均未改动" >&2; exit 1; }
