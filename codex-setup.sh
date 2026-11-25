#!/usr/bin/env bash
# codex-setup.sh — Codex 插件配置(best effort;本仓库仍以 OpenCode 为主)
# 0. 检查 Codex >=0.128.0 及插件命令、Python 3.11+、网络;不安装/升级 Codex 本体
# 1. 缺失时询问安装 Node LTS、Bun、uv;strictdoc 由 modules/strictdoc 装
# 2. claude-mem:优先复用本机 runtime;缺失时运行官方 codex-cli 安装器
#    安装器会修改共享配置并停止 worker;恢复 settings.json/原 Codex 配置,再原生注册;
#    settings.json 用 本仓模板做字段级合并(与 pi/opencode 两侧同一份,敏感值保留)
# 3. 原生安装 Ponytail;安装缺失的本仓库 skills(不修改内容);CodeGraph 由 modules/codegraph 模块处理
# 4. 提示 /hooks 信任和 /mcp 检查;Magic Context、notify 不安装,原生压缩不变
# 计划:所有安装/写配置的人工确认(含代理、Node/Bun/uv、skills 组、外部设计、AGENTS.tail、
#    可选模块)在任何改动之前一次问完,最后集中问网关/凭据;执行阶段只按 PLAN_* 执行,不再提问。
# 已配置项不重写、不自动升级;冲突/显式禁用项保留;修改前备份,不碰模型/认证配置
# (例外:~/.claude-mem/settings.json 走 本仓模板字段级合并,api key/base url 等敏感值仍保留)
# 用法:bash codex-setup.sh [-y|--yes](-y 默认安装:不再逐项确认、只问凭据);支持 CODEX_HOME(首次 claude-mem 官方安装仅支持默认路径)
# Windows:在 Git Bash(不是 WSL)里跑同一份脚本;Python 3.11+ 缺了由 uv 自管理提供。
set -euo pipefail

# ---- 平台:同一套逻辑跑 Linux/macOS 与 Windows 的 Git Bash(MSYS/MinGW),差异集中在这几处 ----
#   * python3 解析链(见 resolve_python3):系统 python3 → python → py → uv 自管理 3.12;Windows 没有 python3 这个名字
#   * 内嵌 python 的 os.getuid() 在 Windows 不存在 → 统一按 77 兜底,与 claude-mem 和本仓库桥扩展的
#     `process.getuid?.() ?? 77` 一致(端口 37700 + 77 = 37777)
#   * 传给 codex(Windows 原生程序)的本机路径不能是 Git Bash 的 /c/...
IS_WIN=0
case "$(uname -s 2>/dev/null || true)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac
BIN_EXT=""; [ "$IS_WIN" = 1 ] && BIN_EXT=".exe"
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

# -y/--yes(或环境变量 ASSUME_YES=1)「默认安装」:前置计划采用默认值,默认 Y 执行、默认 N 跳过;
# 用户级 AGENTS 规则块默认写入。已有凭据不再询问,缺项凭据仍在计划阶段收集;无终端时占位符保留。
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

CFG="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CFG/config.toml"
MEM_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/thedotmack"
SETTINGS="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json"
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
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
errors=0

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
warn() { echo "WARN: $*" >&2; errors=$((errors + 1)); }

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
for mk in missing:
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

# worker 是否响应健康检查；没有 curl 或超时都按"没在运行"处理
mem_worker_alive() {
  local url
  url="$(mem_worker_url "$1")"
  curl -fsS -m 2 -o /dev/null "http://$url/api/health" 2>/dev/null
}

# 官方安装器覆盖文件前会停 worker；只在安装前确实在运行时恢复，
# 避免把本来没跑 worker 的机器变成常驻进程（恢复状态，不是启用功能）。
mem_worker_restore() {  # $1=settings.json $2=安装前是否在运行(1/0)
  [ "${2:-0}" = 1 ] || return 0
  [ "${AGENT_SKILLS_MEM_RESTART:-1}" = 1 ] || return 0
  local url
  url="$(mem_worker_url "$1")"
  if npx -y claude-mem@latest restart >/dev/null 2>&1 && mem_worker_alive "$1"; then
    echo "claude-mem worker 已重启: http://$url/api/health"
    return 0
  fi
  echo "WARN: claude-mem worker 未恢复运行;手工执行 npx -y claude-mem@latest restart" >&2
  return 1
}

# ---- 网关/凭据预填:新机器只需填网关 + claude-mem 的 key ----
# 环境变量优先(便于无人值守):PI_GATEWAY_BASE_URL / PI_CLAUDE_MEM_API_KEY(或 PI_GATEWAY_API_KEY)
# codex 侧不配 models.json / magic-context:下面四个变量只为与 pi/opencode 的 fill/merge 保持逐字节一致
DEFAULT_GW="https://api.pezayo.com/v1"
GW_BASE="${PI_GATEWAY_BASE_URL:-}"
K_MEM="${PI_CLAUDE_MEM_API_KEY:-${PI_GATEWAY_API_KEY:-}}"
K_CLAUDE=""; K_CODEX=""; K_ANTHROPIC=""; K_GEMINI=""; K_EMBED=""
# codex 侧不配 mcphub;此变量仅为与 pi/opencode 的 merge_cfg 保持逐字节一致
MCPHUB_HOST="${MCPHUB_HOST:-}"

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

needs_gateway_fill() {
  [ -f "$SETTINGS" ] && grep -q '"CLAUDE_MEM_OPENROUTER_API_KEY"[[:space:]]*:' "$SETTINGS" 2>/dev/null && return 1
  return 0
}

collect_gateway_values() {
  needs_gateway_fill || return 0
  [ -z "$GW_BASE" ] && ask_value "统一网关完整地址" GW_BASE '' "$DEFAULT_GW"
  if [ -z "$GW_BASE" ]; then
    echo "未提供网关地址:占位符保留,装完手工填"
    return 0
  fi
  [ -z "$K_MEM" ] && ask_value "claude-mem 的 API key(openai chat completions · mem-1 · coding openai / coding anthropic / codex / default 分组均可)" K_MEM 1
  if [ -n "$K_MEM" ]; then echo "凭据:网关 $GW_BASE;claude-mem key:已填"
  else echo "凭据:网关 $GW_BASE;claude-mem key:留空(占位符保留)"; fi
  return 0
}

# ---- 安装计划:所有人工确认在任何写动作之前一次问完;执行阶段只按 PLAN_* 执行 ----
# 变量由 collect_setup_plan 赋值;-y 时 ask 直接取默认,凭据仍由 collect_gateway_values 问。
PLAN_NODE=0; PLAN_BUN=0; PLAN_UV=0; PLAN_PYTHON_UV=0
PLAN_MEM=0; PLAN_WRITE_CFG=0; PLAN_MEM_INSTALLER=0; PLAN_PLUGINS=0
PLAN_HOOKS=0; PLAN_REVIEWER=0
PLAN_SKILL_RESEARCH=0; PLAN_SKILL_ACCEL=0; PLAN_SKILL_KB=0; PLAN_SKILL_PPT=0
PLAN_EXTERNAL_DESIGN=1; PLAN_AGENTS_TAIL=1; PLAN_MODULES=""; PLAN_MOD_PATH=""

fetch_modules() { # 模块分发器直接从同一棵源码树取
  local m="$SOURCE_ROOT/modules/run.sh"
  [ -f "$m" ] && printf '%s' "$m"
}

# 计划阶段读取配置:解释器已在 collect_setup_plan 最开始建立;仍读不到才按"未配置"处理
pval() { local v; v="$(value "$@" 2>/dev/null)" || v=null; printf '%s' "$v"; }

mem_ready() {
  [ -f "$MEM_ROOT/.agents/plugins/marketplace.json" ] &&
  [ -f "$MEM_ROOT/plugin/.codex-plugin/plugin.json" ] &&
  [ -f "$MEM_ROOT/plugin/hooks/codex-hooks.json" ] &&
  [ -f "$MEM_ROOT/plugin/.mcp.json" ] &&
  [ -f "$MEM_ROOT/plugin/scripts/worker-service.cjs" ] &&
  [ -f "$MEM_ROOT/plugin/scripts/mcp-server.cjs" ]
}

# 显式禁用、旧 thedotmack 插件或旧独立 claude-mem MCP 都表示"不要碰记忆后端"。
# 计划阶段与执行阶段共用同一判定;调用前必须先有可用 python3。
mem_disabled() {
  [ "$(value plugins 'claude-mem@claude-mem-local' enabled)" = false ] ||
  [ "$(value plugins 'claude-mem@thedotmack')" != null ] ||
  [[ "$(value mcp_servers)" == *claude-mem* ]]
}

collect_setup_plan() {
  local proxy def
  # 最先建立只读解释器:后面的配置判定(pval/mem_disabled)全靠它;此处不装任何东西。
  PLAN_PYTHON_UV=0 resolve_python3 || true
  proxy="${http_proxy:-${https_proxy:-${all_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-${ALL_PROXY:-}}}}}}"
  if [ -z "$proxy" ] && ! curl -fsSI --connect-timeout 5 -m 8 -o /dev/null https://github.com; then
    ask '未设代理且 github.com 不可达,仍继续?' N SHARED_PROXY || { echo '未继续:用户选择中止'; exit 1; }
  fi
  if ! command -v npx >/dev/null || ! command -v node >/dev/null; then
    ask '安装 fnm + Node LTS?' Y SHARED_NODE && PLAN_NODE=1
  fi
  if ! command -v bun >/dev/null; then
    ask '安装 Bun(claude-mem runtime)?' Y SHARED_BUN && PLAN_BUN=1
  fi
  if ! command -v uv >/dev/null && [ ! -x "$HOME/.local/bin/uv$BIN_EXT" ]; then
    ask '安装 uv(claude-mem/StrictDoc 依赖)?' Y SHARED_UV_INSTALL && PLAN_UV=1
  fi
  # 没有 Python 时，无论 uv 是否已存在，都在前置阶段决定是否允许用它提供 3.12
  if ! PLAN_PYTHON_UV=0 resolve_python3; then
    ask '没有可用的 Python 3;用 uv 装一个自管理的 Python 3.12(会先装 uv 本体)?' Y SHARED_PYTHON_UV && PLAN_PYTHON_UV=1
  fi

  # claude-mem:无解释器无法核对 TOML，保守跳过；显式禁用或旧接入同样不进入计划
  if ! PLAN_PYTHON_UV=0 resolve_python3; then
    warn '无可用 Python，无法核对 Codex TOML；本次跳过 claude-mem 配置与官方安装器。安装 Python 后重跑'
    PLAN_MEM=0
  elif mem_disabled; then
    PLAN_MEM=0
  else
    PLAN_MEM=1
    ask "写入/更新 $SETTINGS(claude-mem 记忆后端;字段级合并,现有 key/地址保留)?" Y CODEX_WRITE_CFG && PLAN_WRITE_CFG=1
    if ! mem_ready; then
      def=Y; [ ! -d "$MEM_ROOT" ] || def=N
      ask '运行官方 claude-mem 安装器(更新共享资产并停止 worker;随后按原状恢复)?' "$def" CODEX_MEM_INSTALLER && PLAN_MEM_INSTALLER=1
    fi
  fi
  ask '安装插件(claude-mem 原生注册、Ponytail;已显式禁用的保留)?' Y CODEX_PLUGINS && PLAN_PLUGINS=1
  if [ "$(pval features hooks)" = null ]; then
    ask '添加 features.hooks=true(仍需在 /hooks 信任具体 hooks)?' Y CODEX_HOOKS && PLAN_HOOKS=1
  fi
  ask '安装/更新 verification-reviewer 与 consolidation-reviewer（Codex 原生审查代理）?' Y CODEX_REVIEWER && PLAN_REVIEWER=1
  # 统一入口已在公共模式分发 Skill 组与外部设计依赖;这里只保留 Codex 自己的规则块。
  if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ]; then
    PLAN_EXTERNAL_DESIGN=0
  else
  ask "安装/更新 research 组(算法研究、实验、PyTorch 性能与 kernel;每次刷新·漂移自动备份)?" N SHARED_RESEARCH && PLAN_SKILL_RESEARCH=1
  ask "安装/更新 accel 组(算力平台模板;缺才装·本机特化不覆盖)?" N SHARED_ACCEL && PLAN_SKILL_ACCEL=1
  ask "安装/更新 kb 组(公共算力知识;每次刷新)?" N SHARED_KB && PLAN_SKILL_KB=1
  ask "安装/更新 ppt 组(南大 HTML/PPTX、Dashi、ppt-master 与独立依赖;需 Node 20+、Python 3.10+)?" N SHARED_PPT && PLAN_SKILL_PPT=1
  case "${SKILLS_EXTERNAL:-}" in
    skip) PLAN_EXTERNAL_DESIGN=0 ;;
    install) ;;
    *) ask '安装/更新外部设计依赖(ui-ux-pro-max、huashu-design、design-taste-frontend)?' Y SHARED_EXTERNAL || PLAN_EXTERNAL_DESIGN=0 ;;
  esac
  fi
  case "${AGENTS_TAIL:-}" in
    0) PLAN_AGENTS_TAIL=0 ;;
    1) ;;
    *) # 旧键 SHARED_AGENTS_TAIL 只代表项目级同意：拒绝继续生效，同意不升级为全局同意。
       if [ "${PREF_REUSE:-0}" = 1 ] && [ "$(preference_get SHARED_AGENTS_TAIL || true)" = 0 ] \
          && ! preference_get CODEX_AGENTS_TAIL >/dev/null; then PLAN_AGENTS_TAIL=0
       elif ask "把记忆系统规范块写进 Codex 用户级 $CFG/AGENTS.md(所有项目共用)?" Y CODEX_AGENTS_TAIL; then PLAN_AGENTS_TAIL=1
       else PLAN_AGENTS_TAIL=0; fi ;;
  esac
  # 模块名单在任何执行之前一次问完;执行阶段只用 --selected 跑已选项
  # 计划末尾才解析源码基准:全部确认已完成,此前不 clone、不 mkdir
  acquire_source || exit 1
  PLAN_MOD_PATH="$(fetch_modules)"
  if [ -n "$PLAN_MOD_PATH" ]; then
    local msel="" saved_modules="" known_modules="" mod_env=("PATH=$PATH")
    [ -n "$ASSUME_YES" ] && msel="--yes"
    if [ "${PREF_REUSE:-0}" = 1 ]; then
      saved_modules="$(preference_get CODEX_MODULES || true)"
      known_modules="$(preference_get CODEX_MODULES_KNOWN || true)"
      mod_env=("AGENT_SKILLS_MODULE_SELECTION=$saved_modules" "AGENT_SKILLS_MODULE_KNOWN=$known_modules")
    fi
    if PLAN_MODULES="$(env "${mod_env[@]}" bash "$PLAN_MOD_PATH" --host codex $msel --select)"; then
      preference_put CODEX_MODULES "${PLAN_MODULES//$'\n'/,}"
      if known_modules="$(bash "$PLAN_MOD_PATH" --host codex --list)"; then
        known_modules="$(printf '%s\n' "$known_modules" | awk '{print $1}' | paste -sd, -)"
        preference_put CODEX_MODULES_KNOWN "$known_modules"
      fi
    else
      PLAN_MODULES=""
    fi
  fi
  if [ "$PLAN_MEM" = 1 ] && [ "$PLAN_WRITE_CFG" = 1 ]; then
    collect_gateway_values
  fi
}

# 把已提供的值填进文件(python 负责 JSON 转义);未提供则原样保留占位符。
# 5 个槽位与 pi/opencode 逐字节一致(codex 只用 GW_BASE/K_MEM);四个 <YOUR_NEWAPI_API_KEY>
# 在同一份模板里对应不同 key,只能按 provider 块就近替换;embedding/claude-mem 按各自键名替。
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
merge_cfg() {
  local url="$1" dest="$2" tmp cand out target
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
  if [ ! -f "$dest" ]; then
    if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
      mkdir -p "$(dirname "$target")"; cp "$tmp" "$target"; echo "wrote: $dest(含占位符)"
    else
      echo "跳过: $dest 未创建"
      rm -f "$tmp"
      return 2
    fi
    rm -f "$tmp"
    return 0
  fi
  cand="$(mktemp)"
  out="$(python3 - "$dest" "$tmp" "$cand" <<'PYEOF'
import json, re, sys
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
if merged == cur:
    print("unchanged")
else:
    with open(sys.argv[3], 'w', encoding='utf-8') as f:
        json.dump(merged, f, indent=2, ensure_ascii=False)
        f.write("\n")
    top = [k for k in merged if cur.get(k) != merged.get(k)]
    print("变更: " + (", ".join(top) or "嵌套字段"))
PYEOF
)"
  rm -f "$tmp"
  local bak
  bak="$dest.bak-$(date +%Y%m%d%H%M%S)"
  case "$out" in
    unchanged) echo "unchanged: $dest(已与模板一致,无需改动)"; rm -f "$cand" ;;
    "")        echo "WARN: $dest 合并失败,保留原文件" >&2; rm -f "$cand"; return 1 ;;
    *)         if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
                 cp "$dest" "$bak"; mv "$cand" "$target"; echo "updated: $dest"
               else
                 echo "保留原文件: $dest"; rm -f "$cand"; return 2
               fi ;;
  esac
}

backup() {
  if [ -f "$1" ]; then
    local bak
    bak="$(mktemp "$1.bak-$(date +%Y%m%d%H%M%S)-XXXXXX")" || return 1
    cp -p "$1" "$bak" || return 1
    echo "backup: $bak"
  fi
}
# 只读 TOML;写入交给 Codex CLI,保留其余键和注释。
value() {
  python3 - "$CONFIG" "$@" <<'PY'
import json, pathlib, sys, tomllib
p = pathlib.Path(sys.argv[1])
v = tomllib.loads(p.read_text()) if p.exists() else {}
for key in sys.argv[2:]:
    v = v.get(key) if isinstance(v, dict) else None
print(json.dumps(v))
PY
}
download_run() {
  local tmp rc=0
  tmp="$(mktemp)" || return 1
  if curl -fsSL --connect-timeout 8 -m 60 -o "$tmp" "$1"; then
    bash "$tmp" || rc=$?
  else rc=1; fi
  rm -f "$tmp"
  return "$rc"
}
install_plugin() {
  local id="$1" source="$2" listing
  if [ "$(value plugins "$id" enabled)" = false ]; then
    echo "保留: $id 已被显式禁用"
    return
  fi
  listing="$(codex plugin list --marketplace "${id#*@}")" || return 1
  if python3 -c 'import sys; sys.exit(not any(l.split()[:1] == [sys.argv[1]] and "installed, enabled" in l for l in sys.stdin))' "$id" <<< "$listing"; then
    echo "unchanged: $id 已安装"
    return
  fi
  echo "待添加: 插件 $id;市场来源 $source"
  backup "$CONFIG" || return 1
  # 市场来源可能是本机路径(Windows 上要给原生 codex 传 C:/... 而不是 /c/...)
  local src="$source"; case "$src" in /*) src="$(npath "$src")";; esac
  codex plugin marketplace add "$src" || return 1
  codex plugin add "$id" || return 1
}

echo "== Codex 插件配置(best effort) =="
[ "$IS_WIN" = 1 ] && echo "提示: Codex 原生 Windows 仍是 experimental(官方推荐 WSL);本脚本按 best effort 配置。"
for cmd in curl git codex; do
  command -v "$cmd" >/dev/null || { echo "ERROR: 缺少 $cmd,请先安装后重跑" >&2; exit 1; }
done
codex plugin marketplace add --help >/dev/null
codex features enable --help >/dev/null
version="$(codex --version)"
# 计划阶段在所有写动作之前;缺 Python 时 pval 读不到配置就按"未配置"处理
preferences_init
collect_setup_plan
preferences_commit
# python3 缺失不致命:resolve_python3 用 uv 自管理的 3.12 兜底。是否装 uv 已在计划阶段问过,
# 这里按 PLAN_PYTHON_UV 先装好,执行阶段不会再提问。
if [ "$PLAN_PYTHON_UV" = 1 ] && ! command -v uv >/dev/null && [ ! -x "$HOME/.local/bin/uv$BIN_EXT" ]; then
  UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 download_run https://astral.sh/uv/install.sh || true
  export PATH="$HOME/.local/bin:$PATH"
fi
resolve_python3 || { echo 'ERROR: 没有可用的 Python 3(读 config.toml 依赖它);可手工装 Python 3.11+ 或允许脚本用 uv 装后重跑' >&2; exit 1; }
python3 -c 'import tomllib' 2>/dev/null || { echo 'ERROR: 需要 Python 3.11+(tomllib);请在合适的环境中重跑,脚本不会升级系统 Python' >&2; exit 1; }
python3 - "$version" <<'PY'
import re, sys
m = re.search(r'(\d+)\.(\d+)\.(\d+)', sys.argv[1])
if not m or tuple(map(int, m.groups())) < (0, 128, 0):
    sys.exit('ERROR: 需要 Codex >=0.128.0,请手工升级后重跑')
PY
echo "$version;配置目录: $CFG"
value >/dev/null  # 解析失败立即退出,绝不将损坏配置当成空文件
mkdir -p "$CFG"
# 给原生 codex 的必须是宿主路径(MSYS 不会转换环境变量里的 /c/...)
CODEX_HOME="$(npath "$CFG")"; export CODEX_HOME

proxy="${http_proxy:-${https_proxy:-${all_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-${ALL_PROXY:-}}}}}}"
if [ -n "$proxy" ]; then
  echo '已检测到代理环境变量'
elif curl -fsSI --connect-timeout 5 -m 8 -o /dev/null https://github.com; then
  echo '未设代理,但 github.com 可直连,继续'
fi

# ---- 1. runtime 依赖 ----
if [ "$PLAN_NODE" = 1 ]; then
  if download_run https://fnm.vercel.app/install; then
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env)"
    fnm install --lts
    fnm default lts-latest
    eval "$(fnm env)"
  else warn 'Node 安装失败'; fi
fi
if command -v node >/dev/null; then
  node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 20 ? 1 : 0)' || {
    echo 'ERROR: claude-mem 需要 Node >=20,请切换 Node 后重跑' >&2; exit 1;
  }
fi
if [ "$PLAN_BUN" = 1 ]; then
  download_run https://bun.sh/install || warn 'Bun 安装失败'
fi
if [ "$PLAN_UV" = 1 ]; then
  UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 download_run https://astral.sh/uv/install.sh || warn 'uv 安装失败'
fi

# ---- 2. claude-mem:复用资产可避免改动共享 worker/provider ----
# 记忆后端必须走 OpenAI 兼容的 openrouter provider;安装器或旧配置写成 claude 时纠正。
# 只改这一个键,模型/接口/凭据原样保留。
ensure_mem_provider() {
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
    rm -f "$tmp"; warn "$f 解析失败,未改 provider;请手工设为 openrouter"
  fi
}

install_mem_runtime() (
  # upstream CodexCliInstaller 写死 ~/.codex;不让它误写自定义 CODEX_HOME 外的配置。
  if [ "$CFG" != "$HOME/.codex" ]; then
    echo 'ERROR: 首次 claude-mem 安装器仅支持 ~/.codex;请先在默认 CODEX_HOME 安装 runtime,再重跑' >&2
    return 1
  fi
  local saved original had_config=0
  saved="$(mktemp)" || return 1
  original="$(mktemp)" || return 1
  cp -p "$SETTINGS" "$saved" || return 1
  if [ -f "$CONFIG" ]; then cp -p "$CONFIG" "$original" || return 1; had_config=1; fi
  # 即使官方安装失败/被中断也恢复共享配置;恢复失败时保留快照供手工恢复。
  # upstream 会强制启用 hooks、禁用旧插件;丢弃这些配置改动,由下面原生注册按需添加。
  restore() {
    if ! cmp -s "$saved" "$SETTINGS"; then
      cp -p "$saved" "$SETTINGS" || { echo "ERROR: 请从 $saved 恢复 $SETTINGS" >&2; exit 1; }
    fi
    if [ "$had_config" = 1 ]; then
      if ! cmp -s "$original" "$CONFIG"; then
        cp -p "$original" "$CONFIG" || { echo "ERROR: 请从 $original 恢复 $CONFIG" >&2; exit 1; }
      fi
    else rm -f "$CONFIG"; fi
    rm -f "$saved" "$original"
  }
  trap restore EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  backup "$CONFIG" || return 1
  backup "$SETTINGS" || return 1
  backup "$HOME/.codex/AGENTS.md" || return 1
  backup "${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/transcript-watch.json" || return 1
  npx -y claude-mem@latest install --ide codex-cli --provider claude --no-auto-start < /dev/null
)
if [ "$PLAN_MEM" = 0 ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo '保留: 无可用 Python，未读取或更改 claude-mem 配置'
  elif [ "$(value plugins 'claude-mem@claude-mem-local' enabled)" = false ]; then
    echo '保留: claude-mem 已被显式禁用'
  elif [ "$(value plugins 'claude-mem@thedotmack')" != null ] || [[ "$(value mcp_servers)" == *claude-mem* ]]; then
    warn '发现已有 claude-mem 旧插件或独立 MCP 配置,保留原配置;请手工处理后再接入原生插件,避免重复加载'
  fi
elif ! command -v python3 >/dev/null 2>&1; then
  warn '无可用 Python，无法复核 Codex TOML；跳过 claude-mem 官方安装器'
elif mem_disabled; then
  # 计划阶段与执行之间配置可能变化;以执行时的真实 TOML 为准,绝不为"已禁用/已有旧接入"跑官方安装器。
  echo '保留: 执行时重新核对到已有 claude-mem 配置(显式禁用/旧插件/旧 MCP),跳过安装器'
elif ! command -v npx >/dev/null || ! command -v bun >/dev/null || ! command -v uv >/dev/null; then
  warn '缺少 npx/Bun/uv,跳过 claude-mem'
else
  mem_ok=1
  if [ "$PLAN_WRITE_CFG" = 1 ]; then
    # 已存在但仍含占位符时按提示补上(改前存 .bak);不存在则由下面的内嵌模板写入后再补
    if [ -f "$SETTINGS" ] && [ -n "$GW_BASE$K_CLAUDE$K_CODEX$K_ANTHROPIC$K_GEMINI$K_EMBED$K_MEM$MCPHUB_HOST" ] && grep -q '<YOUR_' "$SETTINGS" 2>/dev/null; then
      backup "$SETTINGS" >/dev/null || true
      fill_template_placeholders "$SETTINGS"
      echo "filled placeholders: $SETTINGS"
    fi
    [ -f "$SETTINGS" ] && ensure_mem_worker_keys "$SETTINGS" 2>/dev/null || true
    if [ ! -e "$SETTINGS" ]; then
      mkdir -p "$(dirname "$(rpath "$SETTINGS")")"
      (umask 077; cat > "$SETTINGS" <<'JSON'
{
  "CLAUDE_MEM_RUNTIME": "worker",
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "<YOUR_NEWAPI_BASE_URL>",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-1",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>",
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "20",
  "CLAUDE_MEM_LLM_TIMEOUT_MS": "120000"
}
JSON
      )
      echo "wrote: $SETTINGS;使用前请填写占位符"
      fill_template_placeholders "$SETTINGS"
    fi
    # 与 pi/opencode-setup.sh 用同一份 本仓模板做字段级合并,避免三脚本的 claude-mem 配置漂移
    merge_cfg "$RAW/opencode/claude-mem.settings.json" "$SETTINGS" || true
  else
    [ -e "$SETTINGS" ] || echo "跳过: $SETTINGS 未创建"
    [ -f "$SETTINGS" ] || mem_ok=0
  fi
  if [ "$mem_ok" = 1 ] && ! mem_ready; then
    if [ "$PLAN_MEM_INSTALLER" = 1 ]; then
      echo 'claude-mem runtime 缺失或过旧;官方安装器会更新共享资产、Claude 插件注册并停止 worker。'
      echo '已有 settings.json 将原样恢复;安装后按原状恢复 worker。'
      mem_was_alive=0; mem_worker_alive "$SETTINGS" && mem_was_alive=1
      install_mem_runtime || { warn 'claude-mem runtime 安装失败'; mem_ok=0; }
    else mem_ok=0; fi
  fi
  if [ "$mem_ok" = 1 ] && [ "$PLAN_PLUGINS" = 1 ]; then
    if mem_ready; then
      install_plugin 'claude-mem@claude-mem-local' "$MEM_ROOT" || warn 'claude-mem 插件注册失败'
    else warn 'claude-mem 资产不完整,请检查官方安装器输出'; fi
  fi
  if [ "$PLAN_WRITE_CFG" = 1 ]; then ensure_mem_provider "$SETTINGS"; fi
  mem_worker_restore "$SETTINGS" "${mem_was_alive:-0}" || true
fi

# ---- 3. Ponytail + hooks ----
if [ "$PLAN_PLUGINS" = 1 ]; then
  if command -v node >/dev/null; then
    install_plugin 'ponytail@ponytail' 'DietrichGebert/ponytail' || warn 'Ponytail 安装失败'
  else warn '缺少 Node,跳过 Ponytail'; fi
fi
hooks="$(value features hooks)"
if [ "$hooks" = false ] || [ "$(value features codex_hooks)" = false ]; then
  echo '保留: hooks 已显式禁用;claude-mem/Ponytail 自动注入不会运行'
elif [ "$PLAN_HOOKS" = 1 ]; then
  backup "$CONFIG"
  codex features enable hooks || warn '启用 hooks 失败'
fi

# ---- 4. CodeGraph 与其它可选能力统一由 modules/run.sh 处理(本脚本不再内联注册)----

# ---- 5. skills:共用同步器刷新 base/research(漂移先备份)、补装外部设计依赖并更新第三方 ----
# Codex 0.158.0 的插件不注册 agent roles；使用原生 agents TOML。
if [ "$PLAN_REVIEWER" = 1 ]; then
  if python3 - "$version" <<'PY_REVIEWER_VERSION'
import re, sys
m = re.search(r'(\d+)\.(\d+)\.(\d+)', sys.argv[1])
sys.exit(not m or tuple(map(int, m.groups())) < (0, 158, 0))
PY_REVIEWER_VERSION
  then
    _reviewer_ts="$(date +%Y%m%d%H%M%S)"
    for _role in consolidation-reviewer verification-reviewer; do
      _reviewer="$(mktemp)"
      _agent="$CFG/agents/$_role.toml"
      case "$_role" in
        consolidation-reviewer) _reviewer_url="$RAW/codex/agents/consolidation-reviewer.toml" ;;
        verification-reviewer) _reviewer_url="$RAW/codex/agents/verification-reviewer.toml" ;;
      esac
      if curl -fsSL --connect-timeout 8 -m 60 -o "$_reviewer" "$_reviewer_url" &&
           python3 -c 'import sys,tomllib;tomllib.load(open(sys.argv[1],"rb"))' "$_reviewer"; then
        if [ -f "$_agent" ] && cmp -s "$_reviewer" "$_agent"; then
          echo "unchanged: $_agent"
        else
          mkdir -p "$CFG/agents"
          [ ! -f "$_agent" ] || cp -p "$_agent" "$_agent.bak-$_reviewer_ts"
          mv "$_reviewer" "$(rpath "$_agent")"; echo "wrote: $_agent"
        fi
      else warn "审查代理 $_role 下载或解析失败，未修改原配置"; fi
      rm -f "$_reviewer"
    done
  else warn '审查代理接入要求已验证的 Codex >=0.158.0；未自动升级宿主'; fi
fi
if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ]; then
  # 公共 Skill 已由统一入口分发;Codex 专用模式只写自己的用户级规则块。
  if [ "$PLAN_AGENTS_TAIL" = 1 ]; then
    _mt="$SOURCE_ROOT/scripts/migrate-agents-tail.py"
    if [ -f "$_mt" ]; then
      CODEX_HOME="$CFG" python3 "$_mt" --sync-host codex \
        || warn 'Codex 用户级规则块写入失败，项目与全局 AGENTS 均未改动'
    else
      warn '源码树缺 scripts/migrate-agents-tail.py，无法写入用户级规则块；项目与全局 AGENTS 均未改动'
    fi
  fi
else
  _ss="$SOURCE_ROOT/skills-sync.sh"
  if [ -f "$_ss" ]; then
    if [ "$PLAN_AGENTS_TAIL" = 1 ] && ! grep -q 'migrate-agents-tail.py' "$_ss"; then
      echo "ERROR: 源码树 skills-sync.sh 不是用户级规则版本(缺 scripts/migrate-agents-tail.py);本次不改项目/全局 AGENTS,请更新源码树后重跑" >&2
      PLAN_AGENTS_TAIL=0; errors=$((errors + 1))
    fi
    SKILL_GROUPS=(base)
    [ "$PLAN_SKILL_RESEARCH" = 1 ] && SKILL_GROUPS+=(research)
    [ "$PLAN_SKILL_ACCEL" = 1 ] && SKILL_GROUPS+=(accel)
    [ "$PLAN_SKILL_KB" = 1 ] && SKILL_GROUPS+=(kb)
    [ "$PLAN_SKILL_PPT" = 1 ] && SKILL_GROUPS+=(ppt)
    AGENTS_TAIL="$PLAN_AGENTS_TAIL" \
    AGENTS_TAIL_HOST=codex CODEX_HOME="$CFG" \
    SKILLS_EXTERNAL="$([ "$PLAN_EXTERNAL_DESIGN" = 1 ] && echo install || echo skip)" \
      ASSUME_YES="${ASSUME_YES:-0}" AGENT_SKILLS_SOURCE="$SOURCE_ROOT" \
      bash "$_ss" "${SKILL_GROUPS[@]}" || warn 'skills 同步未完全成功'
  else
    [ "$PLAN_AGENTS_TAIL" = 1 ] \
      && warn '源码树缺 skills-sync.sh,记忆系统规则块未写入;项目与全局 AGENTS 均未改动' \
      || warn '源码树缺 skills-sync.sh,跳过 skills 同步'
  fi
fi

# ---- 可选模块:统一分发(新增模块只加 modules/<名>/,本脚本不用改)----
# 名单在计划阶段用 --select 一次问完,这里只执行已选项。
if [ -f "$PLAN_MOD_PATH" ]; then
  bash "$PLAN_MOD_PATH" --host codex --repo "${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}" \
    --ref "${AGENT_SKILLS_REF:-main}" --selected "$PLAN_MODULES" || warn "模块安装未完全成功"
else
  warn "取不到 modules/run.sh,跳过可选模块"
fi

echo '== 配置步骤结束 =='
echo '1. 在 Codex /hooks 审阅并信任插件 hooks,然后重开会话;更新 hooks 后可能需要重新信任。'
echo '2. 用 /mcp 检查连接,实际调用 claude-mem 查询和 CodeGraph 工具。'
echo "3. claude-mem worker 地址 http://$(mem_worker_url "$SETTINGS")(端口取自 $SETTINGS,默认 37700)。后端配置: $SETTINGS（启动时已检测已有配置并只收集缺项;留空的占位符按清单手工补;环境变量预填方式:PI_GATEWAY_BASE_URL / PI_CLAUDE_MEM_API_KEY)。安装前在运行的话会自动恢复;本次没在跑就手工执行 npx claude-mem@latest restart。"
echo '4. 新项目执行 codegraph init;已有项目索引可复用。'
echo '5. skills 原样复用;缺少 Magic Context 的 ctx_* 工具时仅 best effort,以 OpenCode 为主。'
echo '6. 本脚本不升级已有插件；skills 已经共用同步器刷新，第三方由 npx skills 更新。'
if [ "$errors" != 0 ]; then
  echo "WARN: $errors 项未完成,请检查上方输出后重跑" >&2
  exit 1
fi
