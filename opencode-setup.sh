#!/usr/bin/env bash
# opencode-setup.sh — OpenCode V2 套装配置与旧配置／插件迁移
# 仓库: brilliantrough/agent-skills
#
# 用法：bash opencode-setup.sh [-y|--yes] [--plugins-only|--check]；先安装 OpenCode V2，再拉取预构建包。
# 两阶段：collect_setup_plan 先做只读探测（命令、代理、npm 版本、live 配置），把宿主升级、Python/uv 兜底、
#   Bun、Node、Ponytail、Magic Context、配置写入、自动更新、claude-mem、compaction、TUI 按键、uv、
#   skills 组、外部设计依赖、AGENTS.tail、可选模块与凭据一次性问完，结果放 PLAN_*；
#   之后各步骤只按计划执行，不再提问。-y 与无 tty 都在计划阶段取默认值。
# 完整安装含宿主升级(默认 Y)、配置、依赖与通用 skills；--plugins-only 仅插件及 context-mode skills；--check 只读校验后退出（不问安装项）。
# 配置默认关闭 OpenCode 自动更新(update:disable)，宿主只在本脚本里升级。
# 更新前先退出 TUI 和后台服务；已知旧入口移到配置目录 .agent-skills-backups/。
# 第三方 npm 插件先查本地/npm latest；Ponytail 常规更新默认 Y，Magic Context 单独默认 Y（共享 context.db 风险单独提示）；claude-mem 由官方安装器更新 runtime 与宿主入口。
# 确认后只备份移走对应 latest 缓存并改回官方包登记；下次宿主启动下载。
# 不启动服务、不迁移数据库；宿主升级在本脚本里问一次(默认 Y)后执行(opencode upgrade)，自动更新默认关闭；官方 npm 缺包由宿主启动时下载。
# 配置：本地敏感值保留；四个 newapi provider、自有 web/codegraph MCP 的非敏感结构由模板/模块接管。
# AGENTS.tail 记忆规范块默认写入 OpenCode 用户级规则文件（计划阶段可跳过）；--check 不写任何配置。
# 凭据可交互输入或通过环境变量填写。
# OPENCODE_CONFIG_DIR 优先，其次 XDG_CONFIG_HOME/opencode。Windows 使用 Git Bash。

set -euo pipefail

# ---- 平台:同一套逻辑跑 Linux/macOS 与 Windows 的 Git Bash(MSYS/MinGW),差异集中在这几处 ----
#   * python3 解析链(见 resolve_python3):系统 python3 → python → py → uv 自管理 3.12;Windows 没有 python3 这个名字
#   * 内嵌 python 的 os.getuid() 在 Windows 不存在 → 统一按 77 兜底,与 claude-mem 和本仓库桥扩展的
#     `process.getuid?.() ?? 77` 一致(端口 37700 + 77 = 37777)
#   * 写进 opencode.json 的路径要让 Windows 原生 opencode 认得,不能是 Git Bash 的 /c/...
IS_WIN=0
case "$(uname -s 2>/dev/null || true)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac
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

# -y/--yes(或环境变量 ASSUME_YES=1)「默认安装」:计划阶段不再逐项确认,一律取默认值 —— 默认 Y 的照做
# (装缺件、字段级合并写配置、刷新 base skills、写用户级 AGENTS 规则块),默认 N 的跳过(算力/知识/ppt 组)。
# 凭据在计划末尾一并收集;没有终端时静默跳过、占位符保留(无人值守用环境变量预填)。
# 所有提问集中在 collect_setup_plan;执行段只按 PLAN_* 执行,不再提问。
ASSUME_YES="${ASSUME_YES:-}"
PLUGINS_ONLY=0; CHECK_ONLY=0; CHOOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --choose) CHOOSE=1 ;;
    --plugins-only) PLUGINS_ONLY=1 ;;
    --check) CHECK_ONLY=1; PLUGINS_ONLY=1 ;;
    -h|--help)
      cat <<'HELP'
用法: bash <本脚本> [-y|--yes] [--choose] [--plugins-only|--check]
  默认             完整配置、插件、依赖与通用 skills；有本机偏好时摘要一次确认后复用
  --choose         忽略已保存答案并逐项选择，完成后保存新偏好
  --plugins-only   同步插件及 context-mode skills，转换旧配置格式；不更新模型/Python/通用 skills
  --check          下载校验自维护包、查询第三方版本、检查配置；不部署，不更改配置/认证/数据库
  -y, --yes        计划阶段采用各项默认值（默认 N 仍跳过）；凭据仍可交互询问
先安装 OpenCode V2；V1 请先自行升级。精简模式需要已有 Python 3、curl、Bun。
所有确认与凭据在开头一次问完（代理、宿主升级、依赖、插件刷新、配置写入、skills 组、外部设计依赖、
模块选择、AGENTS.tail、凭据），之后只执行不再提问；--check 只做校验，不做安装选择。
已知旧入口备份到 $CFG/.agent-skills-backups/；不启动宿主、不迁移数据库。
查询 Ponytail/Magic Context 的本地版本与 npm latest；失败只警告。Ponytail 有新版默认 Y，钉版/本地路径默认 N。
Magic Context 旧缓存路径自动迁回官方包名，保留当前缓存；--check 只预览。实际刷新默认 Y，确认后下次启动下载。
官方 claude-mem 安装器更新 runtime/入口/MCP，会停止共享 worker；--check 只报告、不询问刷新，仍联网，宿主 --version 可能写日志。
AGENTS.tail 记忆规范块默认写入 OpenCode 用户级 AGENTS.md（所有项目共用），计划阶段可跳过。
HELP
      exit 0 ;;
    *) echo "未知参数: $1(支持 -y|--yes / --choose / --plugins-only / --check / -h|--help)" >&2; exit 2 ;;
  esac
  shift
done

# 只读取版本；不安装/升级宿主，也不触发首次运行的数据库迁移。
command -v opencode >/dev/null 2>&1 || { echo "ERROR: 请先安装 OpenCode V2，再运行本脚本" >&2; exit 1; }
OC_VERSION="$(opencode --version)"
if [[ "$OC_VERSION" =~ (^|[[:space:]])v?([12])\.[0-9]+\.[0-9]+ ]]; then OC_MAJOR="${BASH_REMATCH[2]}"
else echo "ERROR: 无法识别或暂不支持的 OpenCode 版本: $OC_VERSION" >&2; exit 1; fi
[ "$OC_MAJOR" = 2 ] || { echo "ERROR: 当前 setup 只维护 OpenCode V2；请先升级宿主，现有配置未改动。" >&2; exit 1; }
echo "客户端: $OC_VERSION → v$OC_MAJOR 插件包；自动更新默认关闭,宿主只在本脚本里升级/不迁移数据库"
OC_RELEASE="opencode-plugins-1.0.26"
CFG="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
PLUGINS="$CFG/plugins"
CLAUDE_PLUGIN="$PLUGINS/claude-mem.js"
SETTINGS="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json"
MC_CFG="$HOME/.config/cortexkit/magic-context.jsonc"

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
  local tmp
  PREF_LOCK="${PREF_FILE}.lock"
  # uutils mkdir can report success on EEXIST; link creates the exact destination atomically.
  tmp="$(mktemp "${PREF_LOCK}.XXXXXX")" || { echo "WARN: 无法暂存安装偏好锁" >&2; return 1; }
  if printf '%s\n' "$$" > "$tmp" && link "$tmp" "$PREF_LOCK" 2>/dev/null \
    && [ ! -L "$PREF_LOCK" ] && [ "$tmp" -ef "$PREF_LOCK" ]; then
    rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"
  echo "WARN: 安装偏好锁已存在或无法创建: $PREF_LOCK；请确认 link 可用且文件系统支持硬链接，确认无安装进程后可人工删除残留锁" >&2
  return 1
}
preferences_commit_locked() {
  (
  trap 'rm -f "$PREF_LOCK"' EXIT
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

# 宿主升级挪到计划阶段之后（见 collect_setup_plan 调用处），避免提问前就升级。
# 代理探测与计划段共用。
net_ok() { curl -fsSI --connect-timeout 5 -m 8 -o /dev/null https://github.com; }
# 计划结果默认值(collect_setup_plan 会覆盖);未定义时按 0/skip 处理
PLAN_PROXY=1; PLAN_UPGRADE=0; PLAN_PYTHON_UV=0; PLAN_BUN=0; PLAN_NODE=0; PLAN_PONYTAIL=0
PLAN_MC_REFRESH=0; PLAN_WRITE_CFG=1; PLAN_FORCE_MANUAL=0; PLAN_CLAUDE_MEM=0
PLAN_COMPACTION=0; PLAN_TUI_KEYS=0; PLAN_UV_INSTALL=0; PLAN_UV_UPGRADE=0; PLAN_UV_MIRROR=0
PLAN_SKILLS_EXTERNAL=install; PLAN_AGENTS_TAIL=0; SKILL_GROUPS=(); MODULE_SELECTION=""; MODULE_RUN=""
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
# merge_cfg <url> <dest> — 拉本仓模板后做「字段级」合并,而非整文件覆盖:
#   模板中的非敏感字段值优先 → 新默认值能下发到服务器;
#   隐私内容永不覆盖:敏感键(api key / secret / token / password / credential / bearer / auth /
#     cookie / ingest / webhook / base_url / url / endpoint / host / 以 key 结尾)保留机器上已有值。
#     回归检查:tests/merge-private-preservation.py
#   模板里含 <占位符> 的值不覆盖本地已填内容;本地独有的键保留。
#   列表键 packages/enabledModels 走并集(本地顺序 + 模板新增);其余键模板优先,数组整体替换。
#   合并结果与本地一致时不写文件(幂等);有改动先存时间戳 .bak。
#   dest 不存在则直接落模板；符号链接写入实际目标，保留链接本身。
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

has_provider_config() { config_probe provider "$1" "$CFG/opencode.json" "$CFG/opencode.jsonc"; }
has_embedding_config() { config_probe embedding '' "$MC_CFG"; }
has_mem_config() { config_probe mem '' "$SETTINGS"; }
has_gateway_config() { config_probe gateway '' "$CFG/opencode.json" "$CFG/opencode.jsonc" "$MC_CFG" "$SETTINGS"; }
has_mcp_config() { config_probe mcp '' "$CFG/opencode.json" "$CFG/opencode.jsonc"; }

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

# ---- 计划阶段:只读探测 + 一次性收集全部确认与凭据,结果放 PLAN_* ----
# 执行段只按 PLAN_* 执行,不再提问。-y 与无 tty 在这一阶段取默认值。
# 需要新增确认时只在这里加,并把结果在下方对应步骤用掉。
plan_pony_default() { # 只读:与 deploy.py 的 plugin_versions 同规则;钉版/本地路径/同版本/探测失败 → N
  local f ver latest
  for f in "$CFG/opencode.json" "$CFG/opencode.jsonc"; do
    [ -f "$f" ] || continue
    grep -q 'ponytailPackage' "$f" 2>/dev/null && { echo N; return 0; }
    # 官方 @latest／无版本登记之外的都是钉版或本地路径
    if grep -oE '"@dietrichgebert/ponytail(@[^"]*)?' "$f" 2>/dev/null | grep -qvE '"@dietrichgebert/ponytail(@latest)?$'; then
      echo N; return 0
    fi
    # 本地路径登记（file:、相对/绝对路径、盘符）；skills.paths 里的 .../ponytail/skills 不算
    if grep -oE '"(file:|\.{1,2}/|/)[^"]*ponytail[^"]*"|"[A-Za-z]:[^"]*ponytail[^"]*"' "$f" 2>/dev/null | grep -qv '/skills"$'; then
      echo N; return 0
    fi
  done
  ver=""
  for cache in "${XDG_CACHE_HOME:-$HOME/.cache}"/opencode/npm/'@dietrichgebert/ponytail@latest'; do
    [ -d "$cache" ] || continue
    # 与 deploy.py 一致：只认纯数字代次目录并取最大；没有代次时用缓存根
    gen="$(find "$cache" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -E '/[0-9]+$' | sort -n | tail -1)"
    f="${gen:-$cache}/node_modules/@dietrichgebert/ponytail/package.json"
    [ -f "$f" ] || continue
    ver="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  done
  if [ -z "$ver" ]; then
    echo "提示: 未检测到 Ponytail @latest 缓存版本，缺包由宿主启动安装，本次不刷新" >&2
    echo N; return 0
  fi
  latest="$(curl -fsSL --connect-timeout 5 -m 15 https://registry.npmjs.org/@dietrichgebert%2Fponytail/latest 2>/dev/null \
    | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  if [ -z "$latest" ]; then
    echo "提示: 未能只读查询 Ponytail npm latest,保留现状(不刷新;需要更新时手工确认)" >&2
    echo N; return 0
  fi
  if [ -n "$ver" ]; then
    if [ "$ver" = "$latest" ]; then echo "提示: Ponytail 本地缓存已是 npm latest $latest,无需更新" >&2; echo N; return 0; fi
    local highest
    highest="$(printf '%s\n%s\n' "$ver" "$latest" | sort -V 2>/dev/null | tail -1 || :)"
    if [ -z "$highest" ]; then
      echo "提示: 无法比较 Ponytail 版本($ver / $latest),保留现状" >&2; echo N; return 0
    fi
    if [ "$highest" = "$ver" ]; then
      echo "提示: Ponytail 本地 $ver 不低于 npm latest $latest,不降级" >&2; echo N; return 0
    fi
  fi
  echo Y
}

collect_setup_plan() {
  local proxy uv_present=0 npx_present=0 bun_present=0 uvcfg
  # --check 只校验下载与配置:不询问,也不做代理探测等任何安装前判断。
  if [ "$CHECK_ONLY" = 1 ]; then
    PLAN_PROXY=1; PLAN_UPGRADE=0; PLAN_PYTHON_UV=0; PLAN_BUN=0; PLAN_NODE=0; PLAN_PONYTAIL=0
    PLAN_MC_REFRESH=0; PLAN_WRITE_CFG=0; PLAN_FORCE_MANUAL=0; PLAN_CLAUDE_MEM=0
    PLAN_COMPACTION=0; PLAN_TUI_KEYS=0; PLAN_UV_INSTALL=0; PLAN_UV_UPGRADE=0; PLAN_UV_MIRROR=0
    PLAN_SKILLS_EXTERNAL=skip; PLAN_AGENTS_TAIL=0; SKILL_GROUPS=(base); MODULE_SELECTION=""
    # --check 也要核对模板与迁移脚本,因此同样需要源码树;不询问、不写配置
    acquire_source || exit 1
    MODULE_RUN="$SOURCE_ROOT/modules/run.sh"
    [ -f "$MODULE_RUN" ] || MODULE_RUN=""
    return 0
  fi

  # 0) 代理:无代理变量且直连 github 不通时才问(其余情况只打印)
  proxy="${http_proxy:-${https_proxy:-${all_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-${ALL_PROXY:-}}}}}}"
  if [ -n "$proxy" ]; then
    echo "代理: $proxy"
    PLAN_PROXY=1
  elif net_ok 2>/dev/null; then
    echo "未设代理环境变量,但直连 github.com 可达(可能是透明代理),继续"
    PLAN_PROXY=1
  else
    echo "提醒: 未检测到代理环境变量(大小写的 http(s)_proxy / all_proxy 都查了),且直连 github.com 不通。"
    echo "      建议先 export http_proxy/https_proxy 再继续;有透明代理则可忽略。"
    if ask "仍要继续吗？" N SHARED_PROXY; then PLAN_PROXY=1; else PLAN_PROXY=0; fi
  fi

  if command -v uv >/dev/null 2>&1 || [ -x "$HOME/.local/bin/uv$BIN_EXT" ]; then uv_present=1; fi
  if command -v npx >/dev/null 2>&1; then npx_present=1; fi
  if command -v bun >/dev/null 2>&1; then bun_present=1; fi

  # 1) 宿主升级与依赖
  if [ "$PLUGINS_ONLY" = 0 ]; then
    if ask "更新 OpenCode 到最新版(opencode upgrade)?" Y OC_UPGRADE; then PLAN_UPGRADE=1; else PLAN_UPGRADE=0; fi
    if ! { command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1; } \
       && ! { command -v python >/dev/null 2>&1 && python -c pass >/dev/null 2>&1; } \
       && ! { command -v py >/dev/null 2>&1 && py -3 -c pass >/dev/null 2>&1; }; then
      if ask "缺少 Python 3 时用 uv 装自管理的 Python 3.12?" Y SHARED_PYTHON_UV; then PLAN_PYTHON_UV=1; else PLAN_PYTHON_UV=0; fi
    else PLAN_PYTHON_UV=0; fi
  else
    PLAN_UPGRADE=0; PLAN_PYTHON_UV=0
  fi
  if [ "$PLUGINS_ONLY" = 0 ] && [ "$bun_present" = 0 ]; then
    if ask "是否安装 Bun（配置转换与 context-mode 所需）？" Y SHARED_BUN; then PLAN_BUN=1; else PLAN_BUN=0; fi
  else PLAN_BUN=0; fi
  if [ "$PLUGINS_ONLY" = 0 ] && [ "$npx_present" = 0 ]; then
    echo "未检测到 npx(claude-mem 官方安装器与 skills 安装需要 Node)。"
    if ask "是否安装 fnm + Node LTS？" Y SHARED_NODE; then PLAN_NODE=1; else PLAN_NODE=0; fi
  else PLAN_NODE=0; fi

  # 2) 第三方插件缓存刷新
  # Ponytail 默认值由只读探测直接决定：只有确认有可更新版本才询问，其余（钉版/本地路径/同版本/更高/探测失败）跳过。
  if [ "$(plan_pony_default)" = Y ]; then
    if ask "是否将 Ponytail 更新为 npm latest（旧缓存备份；钉版/本地登记不动）?" Y OC_PONYTAIL; then
      PLAN_PONYTAIL=1
    else PLAN_PONYTAIL=0; fi
  else
    PLAN_PONYTAIL=0
    echo "Ponytail: 无需更新或无法只读探测(钉版／本地路径／同版本／更高／查询失败)，跳过并保留现状。"
  fi
  echo "注意：新版首次加载可能迁移共享 context.db。确认前请退出 OpenCode/Desktop/Pi 并备份共享库；同机 Pi 版本需另行同步。"
  if ask "是否刷新 Magic Context（已确认相关宿主停用并备份）?" Y OC_MC_REFRESH; then PLAN_MC_REFRESH=1; else PLAN_MC_REFRESH=0; fi

  if [ "$PLUGINS_ONLY" = 1 ]; then
    # 精简模式到此为止:配置、skills、uv、模块都不执行
    if command -v npx >/dev/null 2>&1 && ask "更新 claude-mem runtime／官方插件／MCP（会停止共享 worker，随后自动恢复）?" Y OC_CLAUDE_MEM; then
      PLAN_CLAUDE_MEM=1
    else PLAN_CLAUDE_MEM=0; fi
    PLAN_WRITE_CFG=1; PLAN_FORCE_MANUAL=0; PLAN_COMPACTION=0; PLAN_TUI_KEYS=0
    PLAN_UV_INSTALL=0; PLAN_UV_UPGRADE=0; PLAN_UV_MIRROR=0
    PLAN_SKILLS_EXTERNAL=skip; PLAN_AGENTS_TAIL=0; SKILL_GROUPS=(base); MODULE_SELECTION=""
    # 精简模式仍读本地源码树的迁移脚本，但只在确实需要 web MCP 改名时才取源，
    # 无关的离线机器不因缺源码而中断。
    if grep -qs '"mcphub-web"[[:space:]]*:' "$CFG/opencode.json" "$CFG/opencode.jsonc"; then
      acquire_source || exit 1
    fi
    return 0
  fi

  # 3) 配置写入与自动更新档位(只读检查 live 配置)
  if ask "写入/更新套件管理的配置文件（字段级合并，API key 等敏感值保留）?" Y OC_WRITE_CFG; then PLAN_WRITE_CFG=1; else PLAN_WRITE_CFG=0; fi
  PLAN_FORCE_MANUAL=0
  if [ "$PLAN_WRITE_CFG" = 1 ] && grep -qE '"update"[[:space:]]*:[[:space:]]*(true|"auto")|"autoupdate"[[:space:]]*:[[:space:]]*(true|"auto")' \
     "$CFG/opencode.json" "$CFG/opencode.jsonc" 2>/dev/null; then
    if ask "OpenCode 当前允许自动更新(升级会打断正在运行的进程),改为只在 setup 里手动升级?" Y OC_FORCE_MANUAL; then PLAN_FORCE_MANUAL=1; fi
  fi
  if [ "$PLAN_WRITE_CFG" = 1 ]; then
    if { command -v npx >/dev/null 2>&1 || [ "$PLAN_NODE" = 1 ]; } \
       && ask "更新 claude-mem runtime／官方插件／MCP（会停止共享 worker，随后自动恢复）?" Y OC_CLAUDE_MEM; then
      PLAN_CLAUDE_MEM=1
    else PLAN_CLAUDE_MEM=0; fi
    if ask "在 opencode.json 写入 compaction auto=false(让 magic-context 接管压缩;已有 compaction 则跳过)?" Y OC_COMPACTION; then
      PLAN_COMPACTION=1
    else PLAN_COMPACTION=0; fi
    if ask "统一 TUI 按键为 Enter 发送、Shift+Enter 换行，取消旧 Ctrl+Enter/Ctrl+J 发送绑定?" Y OC_TUI_KEYS; then
      PLAN_TUI_KEYS=1
    else PLAN_TUI_KEYS=0; fi
  else
    # 不写配置时这些步骤无处落地，也不让官方安装器改写 opencode.json。
    PLAN_CLAUDE_MEM=0; PLAN_COMPACTION=0; PLAN_TUI_KEYS=0
  fi

  # 4) uv(安装/升级/镜像);镜像目标按平台算好
  uvcfg="$HOME/.config/uv/uv.toml"
  if [ "$IS_WIN" = 1 ] && [ -n "${APPDATA:-}" ]; then uvcfg="$(cygpath -u "$APPDATA")/uv/uv.toml"; fi
  if [ "$uv_present" = 0 ]; then
    if ask "未检测到 uv,安装 uv(astral.sh 官方脚本,装到 ~/.local/bin)?" Y SHARED_UV_INSTALL; then PLAN_UV_INSTALL=1; else PLAN_UV_INSTALL=0; fi
    PLAN_UV_UPGRADE=0
  else
    PLAN_UV_INSTALL=0
    if ask "uv 有新版本时升级(uv self update)?" Y SHARED_UV_UPGRADE; then PLAN_UV_UPGRADE=1; else PLAN_UV_UPGRADE=0; fi
  fi
  if grep -q 'pypi.tuna' "$uvcfg" 2>/dev/null || [ -f "$uvcfg" ]; then
    PLAN_UV_MIRROR=0   # 已配置或已有用户自建文件:沿用现有处理,只报告
  elif ask "配置 uv 用清华 PyPI 镜像($uvcfg)?" Y SHARED_UV_MIRROR; then PLAN_UV_MIRROR=1
  else PLAN_UV_MIRROR=0; fi

  # 5) skills 分组、外部设计依赖、用户级 AGENTS 规则块
  # 统一入口已在公共模式分发一次(AGENT_SKILLS_HOST_ONLY=1);这里只保留 OpenCode 自己的规则块。
  SKILL_GROUPS=()
  if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ]; then
    PLAN_SKILLS_EXTERNAL=skip
  else
  SKILL_GROUPS=(base)
  ask "安装/更新 research 组(算法研究、实验、PyTorch 性能与 kernel;每次刷新·漂移自动备份)?" N SHARED_RESEARCH && SKILL_GROUPS+=(research)
  ask "安装/更新 accel 组(算力平台模板;缺才装·本机特化不覆盖)?" N SHARED_ACCEL && SKILL_GROUPS+=(accel)
  ask "安装/更新 kb 组(公共算力知识;每次刷新)?" N SHARED_KB && SKILL_GROUPS+=(kb)
  ask "安装/更新 ppt 组(南大 HTML/PPTX、Dashi、ppt-master 与独立依赖;需 Node 20+、Python 3.10+)?" N SHARED_PPT && SKILL_GROUPS+=(ppt)
  case "${SKILLS_EXTERNAL:-}" in
    skip) PLAN_SKILLS_EXTERNAL=skip ;;
    install) PLAN_SKILLS_EXTERNAL=install ;;
    *) if ask "安装外部设计依赖（ui-ux-pro-max / huashu-design / design-taste-frontend）?" Y SHARED_EXTERNAL; then
         PLAN_SKILLS_EXTERNAL=install
       else PLAN_SKILLS_EXTERNAL=skip; fi ;;
  esac
  fi
  case "${AGENTS_TAIL:-}" in
    0) PLAN_AGENTS_TAIL=0 ;;
    1) PLAN_AGENTS_TAIL=1 ;;
    *) # 旧键 SHARED_AGENTS_TAIL 只代表项目级同意：拒绝继续生效，同意不升级为全局同意。
       if [ "${PREF_REUSE:-0}" = 1 ] && [ "$(preference_get SHARED_AGENTS_TAIL || true)" = 0 ] \
          && ! preference_get OC_AGENTS_TAIL >/dev/null; then PLAN_AGENTS_TAIL=0
       elif ask "把记忆系统规范块写进 OpenCode 用户级 $CFG/AGENTS.md(所有项目共用)?" Y OC_AGENTS_TAIL; then PLAN_AGENTS_TAIL=1
       else PLAN_AGENTS_TAIL=0; fi ;;
  esac

  # 6) 凭据(网关 + 各 api key):不写配置时无需凭据
  #    放在源码解析之前,占位符/非法网关在任何 clone 或 mkdir 之前就拒绝
  [ "$PLAN_WRITE_CFG" = 1 ] && collect_gateway_values

  # 7) 可选模块:这里只问一次并记下名单,执行时按名单装
  # 源码基准在全部确认与凭据之后解析:此前不 clone、不 mkdir
  MODULE_SELECTION=""
  acquire_source || exit 1
  MODULE_RUN="$SOURCE_ROOT/modules/run.sh"
  [ -f "$MODULE_RUN" ] || MODULE_RUN=""
  if [ -n "$MODULE_RUN" ]; then
    local sel_args=(--host opencode --repo "${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}" --ref "${AGENT_SKILLS_REF:-main}")
    local sel_env=("PATH=$PATH") saved_modules="" known_modules=""
    [ "${ASSUME_YES:-0}" = 1 ] && sel_args+=(--yes)
    if [ "${PREF_REUSE:-0}" = 1 ]; then
      saved_modules="$(preference_get OC_MODULES || true)"
      known_modules="$(preference_get OC_MODULES_KNOWN || true)"
      sel_env=("AGENT_SKILLS_MODULE_SELECTION=$saved_modules" "AGENT_SKILLS_MODULE_KNOWN=$known_modules")
    fi
    if MODULE_SELECTION="$(env "${sel_env[@]}" bash "$MODULE_RUN" "${sel_args[@]}" --select)"; then
      preference_put OC_MODULES "${MODULE_SELECTION//$'\n'/,}"
      if known_modules="$(bash "$MODULE_RUN" --host opencode --list)"; then
        known_modules="$(printf '%s\n' "$known_modules" | awk '{print $1}' | paste -sd, -)"
        preference_put OC_MODULES_KNOWN "$known_modules"
      fi
    else
      echo "WARN: 可选模块选择失败,本次跳过模块" >&2; MODULE_SELECTION=""
    fi
  else
    echo "WARN: 取不到 modules/run.sh,本次跳过可选模块" >&2
  fi
  return 0
}


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
    *)         if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then
                 cp "$dest" "$bak"; mv "$cand" "$target"; echo "updated: $dest"
               else
                 echo "保留原文件: $dest"; rm -f "$cand"; return 2
               fi ;;
  esac
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

echo "== opencode 一键配置 =="

# ---- 0. 计划阶段:一次问完(代理、宿主升级、依赖、插件、配置、skills、模块、凭据) ----
preferences_init
collect_setup_plan
[ "$PLAN_PROXY" = 1 ] || { echo "已取消:未确认在无代理环境下继续。"; exit 1; }
preferences_commit

# ---- 0.1 宿主升级(自动更新关掉之后,升级只发生在这里;失败只警告) ----
if [ "$PLAN_UPGRADE" = 1 ]; then
  if opencode upgrade; then
    OC_VERSION="$(opencode --version)"
    if [[ "$OC_VERSION" =~ (^|[[:space:]])v?(2)\.[0-9]+\.[0-9]+ ]]; then
      OC_MAJOR="${BASH_REMATCH[2]}"; echo "客户端: $OC_VERSION → v$OC_MAJOR"
    else echo "ERROR: 升级后版本不受支持($OC_VERSION)，配置未改动" >&2; exit 1; fi
  else echo "WARN: opencode upgrade 失败，继续用当前版本 $OC_VERSION" >&2; fi
fi

# ---- 1. 依赖: python3(必需;缺失时用 uv 自管理 3.12 兜底,Git for Windows 不带 python) ----
if [ "$PLUGINS_ONLY" = 1 ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1; then :
  elif command -v python >/dev/null 2>&1 && python -c pass >/dev/null 2>&1; then python3() { python "$@"; }
  elif command -v py >/dev/null 2>&1 && py -3 -c pass >/dev/null 2>&1; then python3() { py -3 "$@"; }
  else echo "ERROR: 插件检查／同步需要现成的 Python 3；请先安装或运行完整 setup" >&2; exit 1; fi
else
  # 计划阶段已决定 PLAN_PYTHON_UV;未选 uv 兜底且没有现成 Python 时直接报错,不在这里补问。
  if [ "$PLAN_PYTHON_UV" = 0 ] && ! { command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1; } \
     && ! { command -v python >/dev/null 2>&1 && python -c pass >/dev/null 2>&1; } \
     && ! { command -v py >/dev/null 2>&1 && py -3 -c pass >/dev/null 2>&1; }; then
    echo "ERROR: 没有可用的 Python 3,且计划阶段未选择用 uv 兜底(配置写入依赖它)。可手工装 Python 3 后重跑。" >&2; exit 1
  fi
  resolve_python3 || { echo "ERROR: 没有可用的 Python 3(配置写入依赖它)。可手工装(winget install Python.Python.3.12 / apt install python3)或允许脚本用 uv 装后重跑。" >&2; exit 1; }
  # resolve_python3 消费前置的 PLAN_PYTHON_UV，并把 fallback 解释器导出给子 Bash。
fi

# ---- 1.1 下载对应主版本的发布包；下载/解包失败即停止，保留原配置 ----
oc_stage="$(mktemp -d)"
trap 'rm -rf "$oc_stage"' EXIT
OC_URL="https://github.com/brilliantrough/agent-skills/releases/download/$OC_RELEASE/opencode-plugins-v$OC_MAJOR.tar.gz"
curl -fsSL --connect-timeout 8 -m 120 -o "$oc_stage/package.tgz" "$OC_URL"
python3 - "$oc_stage/package.tgz" "$oc_stage" <<'PYEOF'
import pathlib, sys, tarfile
root = pathlib.Path(sys.argv[2]).resolve()
with tarfile.open(sys.argv[1]) as archive:
    for member in archive.getmembers():
        dest = (root / member.name).resolve()
        if (root != dest and root not in dest.parents) or not (member.isfile() or member.isdir()):
            raise SystemExit('ERROR: 发布包包含非法路径或链接')
    if hasattr(tarfile, 'data_filter'):
        archive.extractall(root, filter='data')
    else:
        archive.extractall(root)
PYEOF
python3 "$oc_stage/deploy.py" "$oc_stage" "$(npath "$CFG")" "$OC_MAJOR" --check --versions "$(npath "$oc_stage/versions.json")"

# deprecated: config-v2-native；迁移期结束后删除旧格式转换，保留原生模板合并。
migrate_opencode_config() {
  command -v bun >/dev/null 2>&1 || { echo "ERROR: 配置转换需要 Bun；请安装或运行完整 setup，现有配置未改动" >&2; return 1; }
  bun "$(npath "$oc_stage/migrate-config.mjs")" "$@" "$(npath "$CFG/opencode.json")" "$(npath "$CFG/opencode.jsonc")"
}

# ---- 配置迁移依赖：完整安装补齐 Bun；精简模式只检查 ----
if [ "$PLAN_BUN" = 1 ]; then
  curl -fsSL --connect-timeout 8 -m 60 https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

# deprecated: mcphub-web-rename；用户确认退役后删除此段及 migrate-web-mcp.py。
web_mcp_ready=1
if grep -qs '"mcphub-web"[[:space:]]*:' "$CFG/opencode.json" "$CFG/opencode.jsonc"; then
  web_args=()
  [ "$CHECK_ONLY" = 1 ] || [ "$PLAN_WRITE_CFG" != 1 ] || web_args+=(--apply)
  if [ ! -f "$SOURCE_ROOT/migrate-web-mcp.py" ]; then
    web_mcp_ready=0
    echo "ERROR: 源码树缺 migrate-web-mcp.py($SOURCE_ROOT);web MCP 改名未完成" >&2
  elif ! python3 "$(npath "$SOURCE_ROOT/migrate-web-mcp.py")" opencode "$(npath "$CFG/opencode.json")" "$(npath "$CFG/opencode.jsonc")" "${web_args[@]}"; then
    web_mcp_ready=0
    echo "WARN: web MCP 改名未完成，保留冲突条目" >&2
  fi
fi
# deprecated: mcphub-web-rename 结束。

if [ "$CHECK_ONLY" = 1 ]; then
  migrate_opencode_config || exit 1
  exit 0
fi

# deprecated: config-v2-native；迁移期结束后删除旧格式转换，保留原生 V2 模板合并。
if [ "$PLAN_WRITE_CFG" = 1 ]; then
  migrate_opencode_config --apply || exit 1
fi

# ---- 第三方 npm 插件：按计划刷新；不启动宿主、不修改共享数据库 ----
plugin_args=()
if [ "$PLAN_PONYTAIL" = 1 ]; then
  plugin_args+=(--refresh-ponytail)
else
  echo "跳过 Ponytail 更新，保留缓存和登记。"
fi
echo "Magic Context 旧缓存路径会迁回官方 @latest，保留已装缓存；自定义路径与钉版不动。"
if [ "$PLAN_MC_REFRESH" = 1 ]; then
  plugin_args+=(--refresh-magic-context)
else
  echo "跳过 Magic Context 刷新：保留缓存，仅迁移可安全复用的旧缓存路径登记；如有 WARN，启动前仍需处理。"
fi

if [ "$PLUGINS_ONLY" != 1 ]; then
# ---- 1.1 依赖: npx(fnm + Node)----
if ! command -v npx >/dev/null 2>&1 && command -v fnm >/dev/null 2>&1; then
  # Git Bash 不加载 PowerShell 的 fnm 初始化；复用已有 default Node，避免重复安装。
  eval "$(fnm env --shell bash)"
  fnm use default || true
fi
if [ "$PLAN_NODE" = 1 ]; then
  echo "未检测到 npx(claude-mem 官方安装器与 skills 安装需要 Node)。"
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
elif ! command -v npx >/dev/null 2>&1; then
  echo "跳过 Node(claude-mem 安装与 skills 安装将不可用)"
fi

fi

if [ "$PLUGINS_ONLY" != 1 ] && [ "$PLAN_WRITE_CFG" = 1 ]; then
# ---- 3. 部署 settings.json(字段级合并 本仓模板;下载失败用内嵌模板兜底)----
# 凭据已在计划阶段收集
ensure_image_gen
mkdir -p "$HOME/.claude-mem"
mc_rc=0; merge_cfg "$RAW/opencode/claude-mem.settings.json" "$SETTINGS" || mc_rc=$?
if [ "$mc_rc" = 1 ] && [ ! -f "$SETTINGS" ]; then   # 只在模板下载失败时用内嵌兜底
  cat > "$SETTINGS" <<'EOF'
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
  echo "wrote: $SETTINGS(含占位符)"
fi
ensure_mem_worker_keys "$SETTINGS" 2>/dev/null || true
echo "claude-mem worker: http://$(mem_worker_url "$SETTINGS")(健康检查: curl -s http://$(mem_worker_url "$SETTINGS")/api/health)"

# ---- 3.1 magic-context 配置文件(字段级合并 本仓模板;historian.model 必填,否则插件报错)----
mcc_rc=0; merge_cfg "$RAW/opencode/magic-context.jsonc" "$MC_CFG" || mcc_rc=$?
if [ "$mcc_rc" = 1 ] && [ ! -f "$MC_CFG" ]; then   # 只在模板下载失败时用内嵌兜底
  mkdir -p "$HOME/.config/cortexkit"
  cat > "$MC_CFG" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/cortexkit/magic-context/master/assets/magic-context.schema.json",
  "language": "zh",
  "todowrite": { "enabled": true, "overlay": false },
  "historian": {
    "opencode": {
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
    }
  }
}
EOF
  echo "wrote: $MC_CFG(含占位符;historian/dreamer 的 model 用 <provider>/<model-id>)"
fi

# ---- 4. opencode.json(来自本仓 templates/:providers/agents/mcp/插件条目/compaction)----
# 已转换为 V2；四个 newapi provider 与自有 MCP 的非敏感结构随模板刷新，敏感值与本地额外条目保留。
# 老 opencode.jsonc 的值自动并入 opencode.json 后退役为 .migrated.bak
# 自动更新默认关闭；已有 notify/disable 保留，auto 问一次。
oc_tpl="$(mktemp "$oc_stage/template.XXXXXX")"; oc_cand="$(mktemp "$oc_stage/merged.XXXXXX")"
if [ "$web_mcp_ready" != 1 ] || ! curl -fsSL --connect-timeout 8 -m 30 -o "$oc_tpl" "$RAW/opencode/opencode.json"; then
  echo "ERROR: opencode.json 模板不可用或 web MCP 迁移未完成，未应用模板" >&2
  exit 1
fi
bun "$(npath "$oc_stage/migrate-config.mjs")" --apply "$(npath "$oc_tpl")" || exit 1
fill_template_placeholders "$oc_tpl"
oc_link="$CFG/opencode.json"
oc_target="$(rpath "$oc_link")"
oc_force_manual="$PLAN_FORCE_MANUAL"
# 上次跳过的 key 这次补上:先填本地文件里的占位符(改前存 .bak),再走正常合并(live 优先)
if [ -f "$CFG/opencode.json" ] && [ -n "$GW_BASE$K_CLAUDE$K_CODEX$K_ANTHROPIC$K_GEMINI$K_EMBED$K_MEM$MCPHUB_HOST" ] \
   && grep -q '<YOUR_' "$CFG/opencode.json" 2>/dev/null; then
  cp -p "$CFG/opencode.json" "$CFG/opencode.json.bak-$(date +%Y%m%d%H%M%S)"
  fill_template_placeholders "$CFG/opencode.json"
  echo "filled placeholders: $CFG/opencode.json"
fi
oc_out="$(python3 - "$CFG/opencode.json" "$CFG/opencode.jsonc" "$oc_tpl" "$oc_cand" "$OC_MAJOR" "$oc_force_manual" "$PLAN_COMPACTION" <<'PYEOF'
import json, re, os, sys

target_p, jsonc_p, tpl_p = sys.argv[1:4]

def strip_jsonc(t):  # 注释感知的 JSONC 剥离(字符串内的 // 不动),顺带去掉尾逗号
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
    return re.sub(r'("(?:\\.|[^"\\])*")|,(\s*[}\]])', lambda m: m[1] or m[2], ''.join(out))

def load(p):
    try:
        return json.loads(strip_jsonc(open(p, encoding='utf-8').read()))
    except FileNotFoundError:
        return {}
    except (json.JSONDecodeError, UnicodeError) as error:
        raise SystemExit(f'ERROR: {p} 解析失败，保留原文件：{error}')

def deep_merge(base, over, layered=False):  # layered：合并本机两个配置文件的有序规则。
    if isinstance(base, dict) and isinstance(over, dict):
        out = dict(base)
        for k, v in over.items():
            if layered and k in ('permissions', 'policies') and isinstance(base.get(k), list) and isinstance(v, list):
                out[k] = base[k] + v
            elif k in ('plugin', 'plugins') and isinstance(base.get(k), list) and isinstance(v, list):
                out[k] = base[k] + [entry for entry in v if entry not in base[k]]
            else:
                out[k] = deep_merge(base.get(k), v, layered) if k in base else v
        return out
    return over

sensitive = re.compile(r'(api[_-]?key|secret|token|password|passwd|credential|bearer|auth|cookie|ingest|webhook|base[_-]?url|url|endpoint|host|(^|[._-])key$)', re.I)
MANAGED_PROVIDERS = {'claude-newapi', 'codex-newapi', 'anthropic-newapi', 'gemini-newapi'}
MANAGED_MCP = {'web', 'codegraph'}

def managed_value(local, template):
    if isinstance(template, list):
        if not isinstance(local, list):
            return template
        unused = [x for x in local if isinstance(x, dict) and x.get('id') is not None]
        out = []
        for item in template:
            match = None
            if isinstance(item, dict) and item.get('id') is not None:
                match = next((x for x in unused if x.get('id') == item.get('id')), None)
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
        if k == 'maxTokens' and isinstance(v, (int, float)) and not isinstance(v, bool):
            continue  # 数值预算随模板，不因 token 字样误作凭据。
        if sensitive.search(k) and v is not None and v != '':
            out[k] = v
        elif isinstance(v, (dict, list)):
            nested = managed_value(v, out.get(k, {} if isinstance(v, dict) else []))
            if nested or k in out:
                out[k] = nested
    return out

tpl = json.load(open(tpl_p, encoding='utf-8'))

live_json, live_jsonc = load(target_p), load(jsonc_p)
live = deep_merge(live_json, live_jsonc, layered=True)
# 用户拒绝或已有顶层 compaction 时都不让模板覆盖；已有 prune 等设置原样保留。
if sys.argv[7] != '1' or 'compaction' in live:
    tpl.pop('compaction', None)
tpl.pop('plugins', None)  # 插件登记由 deploy.py 管理。

merged = deep_merge(tpl, live)
for role in ('consolidation-reviewer', 'verification-reviewer'):
    reviewer = (tpl.get('agents') or {}).get(role, {})
    if 'model' in reviewer:
        merged['agents'][role]['model'] = reviewer['model']
# deprecated: 仅迁移 general/explore 的旧套件默认；本机自选模型优先。
legacy_models = ('anthropic-newapi/deepseek-flash', {'providerID': 'anthropic-newapi', 'model': 'deepseek-flash'})
for role in ('general', 'explore'):
    default = (tpl.get('agents') or {}).get(role, {}).get('model')
    agent = (merged.get('agents') or {}).get(role, {})
    if default and agent.get('model') in legacy_models:
        agent['model'] = default
# 已有更新策略保留，只有用户确认后才关闭 auto。
major, force_manual = sys.argv[5], sys.argv[6] == '1'
if major != '2':
    raise SystemExit('ERROR: 配置模板仅支持 OpenCode V2')
if force_manual or 'update' not in merged:
    merged['update'] = 'disable'
tpl_prov = tpl.get('providers') or {}
live_prov = live.get('providers') or {}
mp = merged.setdefault('providers', {}) if tpl_prov else {}
for name, p in tpl_prov.items():
    if name in MANAGED_PROVIDERS:
        # 套件接管结构，递归保留 provider/模型列表里的敏感叶子。
        mp[name] = managed_value(live_prov.get(name), p)
    elif name in live_prov:
        # 其它 provider 维持原语义：只换 models。
        mp[name] = {**live_prov[name], 'models': p.get('models', {})}
    elif name not in mp:
        mp[name] = p

tpl_mcp = tpl.get('mcp') or {}
tpl_servers = tpl_mcp.get('servers') or {}
live_servers = (live.get('mcp') or {}).get('servers') or {}
if tpl_servers:
    ms = merged.setdefault('mcp', {}).setdefault('servers', {})
    for name, server in tpl_servers.items():
        if name in MANAGED_MCP:
            ms[name] = managed_value(live_servers.get(name), server)

out = json.dumps(merged, indent=2, ensure_ascii=False) + '\n'
same = load(target_p) == merged   # 按 JSON 语义比较:只有格式化/键序不同不算变更(避免每轮重写)
msgs = []
if not same:
    with open(sys.argv[4], 'w', encoding='utf-8') as f:
        f.write(out)
    msgs.append('受管 newapi provider/MCP 非敏感结构按模板刷新；敏感值、本地额外条目和其它 provider 配置保留' if live else '首次写入(含占位符)')
if os.path.exists(jsonc_p):
    msgs.append('退役 opencode.jsonc(值已并入)')
print(';'.join(msgs) if msgs else 'unchanged')
PYEOF
)"
case "$oc_out" in
  unchanged) echo "unchanged: $CFG/opencode.json" ;;
  *)         if [ -s "$oc_cand" ]; then
               if [ -f "$CFG/opencode.json" ]; then
                 cp -p "$CFG/opencode.json" "$CFG/opencode.json.bak-$(date +%Y%m%d%H%M%S)"
               fi
               mv "$oc_cand" "$oc_target"
             fi
             echo "updated: $CFG/opencode.json($oc_out)"
             if [ -f "$CFG/opencode.jsonc" ]; then
               mv "$CFG/opencode.jsonc" "$CFG/opencode.jsonc.migrated-$(date +%Y%m%d%H%M%S).bak"
               echo "retired: opencode.jsonc(值已并入 opencode.json)"
             fi ;;
esac
rm -f "$oc_tpl" "$oc_cand"

fi # 完整安装的环境／配置步骤

# ---- 5. context-mode 独立产物：由 V2 适配包调用原生 setup(ctx) ----
# skills 装到 $CFG/skill/<name>/。
CM_ASSET="opencode-context-mode-vendor.tar.gz"
CM_URL="https://github.com/brilliantrough/agent-skills/releases/latest/download/$CM_ASSET"
CM_DIR="$PLUGINS/context-mode"
[ "$OC_MAJOR" = 2 ] && CM_DIR="$CFG/vendor/context-mode"
CM_ENTRY="$PLUGINS/context-mode.js"
cm_target="$(rpath "$CM_DIR")"
cm_tmp="$(mktemp -d)"; cm_ok=0
if mkdir -p "$cm_tmp/pkg" && curl -fsSL --connect-timeout 8 -m 120 -o "$cm_tmp/a.tgz" "$CM_URL" 2>/dev/null \
   && tar -xzf "$cm_tmp/a.tgz" -C "$cm_tmp/pkg"; then
  cm_ver="$(python3 -c "import json;print(json.load(open('$cm_tmp/pkg/VENDORED.json'))['upstream']['version'])" 2>/dev/null || echo '?')"
  mkdir -p "$PLUGINS"
  if [ -d "$CM_DIR" ] && diff -rq "$cm_tmp/pkg" "$CM_DIR" >/dev/null 2>&1; then
    echo "unchanged: $CM_DIR($cm_ver)"
  else
    if [ -e "$CM_DIR" ]; then
      cm_backup="$CFG/.agent-skills-backups/$(date +%Y%m%d%H%M%S)-context-mode/${CM_DIR#"$CFG/"}"
      mkdir -p "$(dirname "$cm_backup")"; mv "$cm_target" "$cm_backup"
      echo "backup: $CM_DIR -> $cm_backup"
    fi
    mkdir -p "$(dirname "$cm_target")"; mv "$cm_tmp/pkg" "$cm_target"; echo "deployed: $CM_DIR($cm_ver)"
  fi
  if [ "$OC_MAJOR" = 1 ] && ! cmp -s "$CM_DIR/entry.js" "$CM_ENTRY"; then
    [ ! -f "$CM_ENTRY" ] || cp -p "$CM_ENTRY" "$CM_ENTRY.bak-$(date +%Y%m%d%H%M%S)"
    cp -f "$CM_DIR/entry.js" "$CM_ENTRY"
  fi
  cm_n=0
  for d in "$CM_DIR"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    n="$(basename "$d")"; dest="$(rpath "$CFG/skill/$n")"
    if [ -d "$dest" ] && diff -rq "$d" "$dest" >/dev/null 2>&1; then continue; fi
    mkdir -p "$(dirname "$dest")"; rm -rf "$dest"; cp -r "$d" "$dest"
    echo "deployed: skill/$n"; cm_n=$((cm_n+1))
  done
  for stale in ctx-index ctx-search ctx-upgrade ctx-purge ctx-insight; do
    stale_dir="$(rpath "$CFG/skill/$stale")"
    if [ -d "$stale_dir" ]; then rm -rf "$stale_dir"; echo "retired: skill/$stale"; fi
  done
  echo "       context-mode: skill 更新 $cm_n 个(重启 opencode 生效)"
  cm_ok=1
else
  echo "WARN: context-mode 插件下载/解包失败($CM_URL,检查代理)" >&2
fi
rm -rf "$cm_tmp"

if [ "$cm_ok" != 1 ]; then
  echo "ERROR: context-mode 未就绪，未切换插件登记；修复网络后重跑" >&2; exit 1
fi

# ---- 5. 按客户端主版本部署；配置只替换本套件管理的条目 ----
# 未写入配置时仍部署插件资产，但显式跳过插件登记/主配置写入/JSONC 退役，避免旧 provider 配新 plugins。
deploy_args=()
[ "$PLAN_WRITE_CFG" = 1 ] || deploy_args+=(--no-config-write)
if [ "$PLAN_WRITE_CFG" != 1 ] && ! grep -q -- '--no-config-write' "$oc_stage/deploy.py"; then
  echo "WARN: 已下载 release 尚不支持无配置写入部署；为保护现有配置，本次跳过 v2 插件部署与全部插件登记（context-mode 资产已单独同步）。更新 release 后重跑。"
else
  python3 "$oc_stage/deploy.py" "$oc_stage" "$(npath "$CFG")" "$OC_MAJOR" "${plugin_args[@]}" "${deploy_args[@]}"
  if [ "$PLAN_WRITE_CFG" = 1 ]; then
    echo "Ponytail 已登记官方包；已确认更新的包将在下次启动重新下载，其余沿用缓存。setup 不启动宿主。"
    if [[ " ${plugin_args[*]} " == *" --refresh-magic-context "* ]]; then
      echo "Magic Context 已安排刷新；下次启动下载最新版并由插件处理迁移（本脚本未运行迁移）。"
    fi
  else
    echo "插件资产已部署；未登记 Ponytail／自维护包，也未刷新 Ponytail／Magic Context 缓存。"
  fi
fi
# ---- claude-mem：配置合并后由官方安装器更新 runtime、插件与 MCP ----
if [ "$PLAN_CLAUDE_MEM" = 1 ]; then
  mem_was_alive=0; mem_worker_alive "$SETTINGS" && mem_was_alive=1
  (
    backup="$CFG/.agent-skills-backups/$(date +%Y%m%d%H%M%S)-claude-mem"
    mkdir -p "$backup" || exit 1
    chmod 700 "$backup" || exit 1
    cp -p "$CFG/opencode.json" "$backup/opencode.json" || exit 1
    had_plugin=0
    if [ -f "$CLAUDE_PLUGIN" ]; then
      cp -p "$CLAUDE_PLUGIN" "$backup/claude-mem.js" || exit 1
      had_plugin=1
    fi
    had_settings=0
    if [ -f "$SETTINGS" ]; then
      cp -p "$SETTINGS" "$backup/settings.json" || exit 1
      had_settings=1
    fi
    completed=0
    restore_mem_settings() {
      if [ "$had_settings" = 1 ]; then
        cp -p "$backup/settings.json" "$SETTINGS" || { echo "ERROR: 请从 $backup 恢复共享 settings" >&2; exit 1; }
      else
        rm -f "$SETTINGS"
      fi
      if [ "$completed" != 1 ]; then
        cp -p "$backup/opencode.json" "$CFG/opencode.json" || exit 1
        if [ "$had_plugin" = 1 ]; then cp -p "$backup/claude-mem.js" "$CLAUDE_PLUGIN" || exit 1
        else rm -f "$CLAUDE_PLUGIN"; fi
        echo "restored: OpenCode 配置与插件；runtime 的更新不回滚，备份在 $backup"
      fi
    }
    trap restore_mem_settings EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # 官方安装器会重写同名 MCP；先保留用户自定义或禁用的登记。
    python3 - "$(npath "$CFG/opencode.json")" "$(npath "$HOME")" <<'PY_MEM_MIGRATE' || exit $?
import json, re, sys
from pathlib import Path
path, home = Path(sys.argv[1]), sys.argv[2].replace('\\', '/').rstrip('/')
config = json.loads(path.read_text(encoding='utf-8'))
mcp = config.get('mcp', {})
for servers in (mcp, mcp.get('servers', {})):
    entry = servers.get('claude-mem')
    if entry is None:
        continue
    command = entry.get('command', []) if isinstance(entry, dict) else []
    if not isinstance(command, list):
        print('WARN: claude-mem MCP 命令不是官方格式，保留原值并跳过安装器', file=sys.stderr)
        sys.exit(3)
    script = str(command[1]).replace('\\', '/') if len(command) == 2 else ''
    managed_script = script == home + '/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs'
    managed_script |= bool(re.fullmatch(re.escape(home) + r'/\.claude/plugins/cache/thedotmack/claude-mem/[^/]+/(?:plugin/)?scripts/mcp-server\.cjs', script))
    if (not isinstance(command, list) or len(command) != 2
            or str(command[0]).replace('\\', '/').split('/')[-1] not in ('bun', 'bun.exe', 'node', 'node.exe')
            or not managed_script or entry.get('type', 'local') != 'local'
            or set(entry) - {'type', 'command', 'enabled', 'disabled'}
            or entry.get('enabled') is False or entry.get('disabled') is True):
        print('WARN: claude-mem MCP 有自定义或禁用配置，保留原值；跳过官方安装器，需单独处理', file=sys.stderr)
        sys.exit(3)
# 官方安装器仍写旧形状；先移除受管同名项，安装后统一归一化。
if 'claude-mem' in mcp.get('servers', {}):
    del mcp['servers']['claude-mem']
    path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('prepared: claude-mem MCP 交官方安装器刷新')
PY_MEM_MIGRATE
    OPENCODE_CONFIG_DIR="$(npath "$CFG")" npx -y claude-mem@latest install --ide opencode --provider claude --no-auto-start < /dev/null || exit 1
    migrate_opencode_config --apply || exit 1
    completed=1
    echo "claude-mem 官方安装器已结束；共享 settings 原样恢复，备份在 $backup"
  ) || {
    if [ "$?" = 3 ]; then mem_install_skipped=1
    else echo "WARN: claude-mem 未完成更新，请检查上方官方安装输出；其他插件已部署" >&2; fi
  }
elif ! command -v npx >/dev/null 2>&1; then
  echo "WARN: 未检测到 npx，跳过 claude-mem 更新" >&2
fi
if [ "$PLAN_WRITE_CFG" = 1 ]; then ensure_mem_provider "$SETTINGS"; fi
mem_worker_restore "$SETTINGS" "${mem_was_alive:-0}" || true

if [ "$PLAN_WRITE_CFG" = 1 ] && [ "${mem_install_skipped:-0}" = 0 ] && { [ "$PLAN_CLAUDE_MEM" = 1 ] || [ -f "$CLAUDE_PLUGIN" ]; }; then
  [ -f "$CLAUDE_PLUGIN" ] || { echo "ERROR: OpenCode claude-mem 插件未就绪，不能启用 mem-search" >&2; exit 1; }
  [ -n "${SOURCE_ROOT:-}" ] || acquire_source
  mem_js=node; command -v node >/dev/null 2>&1 || mem_js=bun
  "$mem_js" "$(npath "$SOURCE_ROOT/scripts/link-mem-search.mjs")" "$(npath "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")" "$(npath "$HOME/.agents/skills")"
fi

if [ "$PLUGINS_ONLY" = 1 ]; then
  echo "插件部署完成；Magic Context 未就绪的 WARN 仍需处理。宿主与共享数据库未由 setup 升级。"
  exit 0
fi

# ---- 5.1 compaction 关闭(manual setup 要求:magic-context 接管压缩;完整 jsonc 已含则跳过)----
if [ "$PLAN_COMPACTION" = 1 ] && [ "$PLAN_WRITE_CFG" = 1 ]; then
python3 - "$CFG/opencode.json" "$CFG/opencode.jsonc" <<'PYEOF'
import json, re, sys
path, jsonc_path = sys.argv[1:3]
def load(p):
    try:
        text = open(p, encoding="utf-8").read()
    except FileNotFoundError:
        return {}
    out, i, n, instr = [], 0, len(text), False
    while i < n:
        c = text[i]
        if instr:
            out.append(c)
            if c == "\\": out.append(text[i + 1]); i += 2; continue
            if c == '"': instr = False
            i += 1; continue
        if c == '"': instr = True; out.append(c); i += 1; continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n": i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"): i += 1
            i += 2; continue
        out.append(c); i += 1
    cleaned = re.sub(r'("(?:\\.|[^"\\])*")|,(\s*[}\]])', lambda m: m[1] or m[2], "".join(out))
    return json.loads(cleaned) if cleaned.strip() else {}
cfg = load(path)
if "compaction" not in cfg and "compaction" not in load(jsonc_path):
    cfg["compaction"] = {"auto": False}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"added: compaction auto=false -> {path}")
PYEOF
fi

# TUI 插件登记由 deploy.py 统一处理；这里仅设置用户按键。
TUI_CFG="$CFG/tui.json"
if [ "$OC_MAJOR" = 2 ] && [ -f "$CFG/cli.json" ]; then TUI_CFG="$CFG/cli.json"; fi

# ---- 5.4 TUI 按键(Enter 发送、Shift+Enter 换行;不绑定 Ctrl+Enter)----
# 先 fetch 式检查差异,有变化才展示并询问;无变化只报 unchanged。
tui_keys_py() {  # $1 = check(只报差异不写) | apply(备份后写入)
python3 - "$TUI_CFG" "$1" <<'PYEOF'
import json, os, re, shutil, sys
path, mode = sys.argv[1], sys.argv[2]
def load(p):  # JSONC 感知:去注释与尾逗号(字符串内的 // 不动)
    try:
        t = open(p, encoding='utf-8').read()
    except FileNotFoundError:
        return {}
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
want = {"input_submit": "return", "input_newline": "shift+return", "prompt_submit": "none"}
if path.endswith("/cli.json") or path.endswith("\\cli.json"):
    want = {k.replace("_", "."): v for k,v in want.items()}
cfg = load(path)
kb = cfg.get("keybinds", {})
if not isinstance(kb, dict):
    sys.exit(f"ERROR: {path} 的 keybinds 不是对象,未修改")
changed = {k: v for k, v in want.items() if kb.get(k) != v}
if not changed:
    print(f"unchanged: {path}(按键已一致)")
else:
    if mode == "check":
        for k, v in changed.items():
            print(f"keybinds.{k}: {kb.get(k)!r} -> {v!r}")
        sys.exit(3)
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak")
    kb.update(changed)
    cfg["keybinds"] = kb
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"updated: keybinds {', '.join(changed)} -> {path}")
PYEOF
}
kb_rc=0; kb_out="$(tui_keys_py check)" || kb_rc=$?
if [ "$kb_rc" -eq 3 ] && [ "$PLAN_TUI_KEYS" = 1 ] && [ "$PLAN_WRITE_CFG" = 1 ]; then
  printf '%s\n' "$kb_out"
  tui_keys_py apply
else
  printf '%s\n' "$kb_out"
  if [ "$kb_rc" -eq 3 ]; then echo "保留原按键: $TUI_CFG"; fi
fi

# 含密钥的配置统一 600(与 pi/codex 两侧一致;含本机路径的脚本文件不下调)
if [ "$PLAN_WRITE_CFG" = 1 ]; then chmod 600 "$SETTINGS" "$MC_CFG" "$CFG/opencode.json" 2>/dev/null || true; fi

# ---- 6. notify 插件(brilliantrough/opencode-notify-hub,GitHub Release 预构建包)----
# 每次拉最新 release 的 zip,与已装文件比对:一致就不动,不同才备份 .bak-时间戳 再替换。
NOTIFY_TARGET="$PLUGINS/session-notify.js"
if [ "$OC_MAJOR" = 1 ] && command -v curl >/dev/null 2>&1; then
  if [ -f "$NOTIFY_TARGET" ]; then
    _new="$NOTIFY_TARGET.new"
    notify_ver="$(python3 - "$_new" <<'PYEOF' || true
import json, sys, urllib.request, zipfile
api = "https://api.github.com/repos/brilliantrough/opencode-notify-hub/releases"
req = urllib.request.Request(api, headers={"User-Agent": "opencode-setup"})
rels = json.load(urllib.request.urlopen(req, timeout=30))
url = next((a["browser_download_url"] for r in rels if not r.get("draft")
            for a in r.get("assets", [])
            if a["name"].startswith("opencode-notify-plugin-") and a["name"].endswith(".zip")), None)
if not url:
    raise SystemExit("release 中没有 opencode-notify-plugin-*.zip 资产")
tmp, _ = urllib.request.urlretrieve(url)
with zipfile.ZipFile(tmp) as z:
    name = next(n for n in z.namelist() if n.endswith("session-notify.js"))
    with z.open(name) as src, open(sys.argv[1], "wb") as dst:
        dst.write(src.read())
print(url.rsplit("/", 1)[-1])
PYEOF
)"
    if [ -z "$notify_ver" ] || [ ! -s "$_new" ]; then
      rm -f "$_new"; echo "WARN: notify 插件下载失败(检查代理)" >&2
    elif [ -f "$NOTIFY_TARGET" ] && cmp -s "$_new" "$NOTIFY_TARGET"; then
      rm -f "$_new"; echo "unchanged: plugins/session-notify.js($notify_ver)"
    else
      _action=installed
      if [ -f "$NOTIFY_TARGET" ]; then
        cp -p "$NOTIFY_TARGET" "$NOTIFY_TARGET.bak-$(date +%Y%m%d%H%M%S)"; _action=updated
      fi
      mv "$_new" "$(rpath "$NOTIFY_TARGET")"; echo "$_action: plugins/session-notify.js($notify_ver)"
    fi
  fi
fi

# ---- 7. skills 本体 ----
# 分组 = 仓库 skills/{base,research,accel,kb,ppt}/ 目录,策略由 skills-sync.sh 执行:
# base/research 每次刷新且漂移先备份;accel 缺才装(本机特化不覆盖);kb 每次刷新。
# 客户端实体直落 ~/.agents/skills/<名>(装了 Claude Code 时同步 ~/.claude/skills/<名>)。
# 同步器随后用 npx skills 补装外部设计依赖、更新已登记第三方。
if [ "${AGENT_SKILLS_HOST_ONLY:-0}" = 1 ]; then
  # 公共 Skill 已由统一入口分发;OpenCode 专用模式只写自己的用户级规则块。
  if [ "$PLAN_AGENTS_TAIL" = 1 ]; then
    _mt="$SOURCE_ROOT/scripts/migrate-agents-tail.py"
    if [ -f "$_mt" ]; then
      OPENCODE_CONFIG_DIR="$CFG" python3 "$_mt" --sync-host opencode \
        || { echo "ERROR: OpenCode 用户级规则块写入失败，项目与全局 AGENTS 均未改动" >&2; tail_sync_failed=1; }
    else
      echo "ERROR: 源码树缺 scripts/migrate-agents-tail.py，无法写入用户级规则块；项目与全局 AGENTS 均未改动" >&2
      tail_sync_failed=1
    fi
  fi
else
  _ss="$SOURCE_ROOT/skills-sync.sh"
  if [ -f "$_ss" ]; then
    # 旧缓存里的 skills-sync 仍写当前项目;源码树缺用户级同步实现时不委派规则块,项目与全局都不动。
    if [ "$PLAN_AGENTS_TAIL" = 1 ] && ! grep -q 'migrate-agents-tail.py' "$_ss"; then
      echo "ERROR: 源码树 skills-sync.sh 不是用户级规则版本(缺 scripts/migrate-agents-tail.py);本次不改项目/全局 AGENTS,请更新源码树后重跑" >&2
      PLAN_AGENTS_TAIL=0; tail_sync_failed=1
    fi
    SKILLS_EXTERNAL="$PLAN_SKILLS_EXTERNAL" AGENTS_TAIL="$PLAN_AGENTS_TAIL" \
      AGENTS_TAIL_HOST=opencode OPENCODE_CONFIG_DIR="$CFG" ASSUME_YES=1 \
      AGENT_SKILLS_SOURCE="$SOURCE_ROOT" \
      bash "$_ss" "${SKILL_GROUPS[@]}" || echo "WARN: skills 同步未完全成功" >&2
  else
    echo "WARN: 源码树缺 skills-sync.sh,跳过 skills 同步" >&2
    [ "$PLAN_AGENTS_TAIL" = 1 ] && { echo "ERROR: 无法写入记忆系统规则块,项目与全局 AGENTS 均未改动" >&2; tail_sync_failed=1; }
  fi
fi

# ---- 8. uv(可选;strictdoc 由 modules/strictdoc 安装)----
UVP="$HOME/.local/bin/uv$BIN_EXT"
if [ "$PLAN_UV_INSTALL" = 1 ]; then
  uv_sh="$(mktemp)"
  if curl -fsSL --connect-timeout 8 -m 60 -o "$uv_sh" https://astral.sh/uv/install.sh; then
    UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$uv_sh" \
      || echo "WARN: uv 安装脚本退出码非 0,请看上方输出" >&2
  else
    echo "WARN: uv 安装脚本下载失败(检查代理)" >&2
  fi
  rm -f "$uv_sh"
fi
UV_BIN="$(command -v uv 2>/dev/null || echo "$UVP")"
if [ -x "$UV_BIN" ]; then
  export PATH="$HOME/.local/bin:$PATH"
  uv_cur="$("$UV_BIN" --version 2>/dev/null | awk '{print $2}' || true)"
  uv_latest="$(curl -fsSL --connect-timeout 5 -m 8 https://api.github.com/repos/astral-sh/uv/releases/latest 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
  if [ -z "$uv_latest" ]; then
    echo "跳过 uv 自升级:查不到最新版本(检查网络/代理)"
  elif [ "$uv_latest" != "$uv_cur" ]; then
    if [ "$IS_WIN" = 1 ] && [[ "$UV_BIN" == */Python*/Scripts/uv* ]]; then
      echo "uv 由 Python 环境安装(${uv_cur:-未知}),请用原安装方式升级;跳过 uv self update"
    elif [ "$PLAN_UV_UPGRADE" = 1 ]; then
      "$UV_BIN" self update || echo "WARN: uv 自升级失败(系统包管理器装的请用系统方式升级)" >&2
    fi
  else
    echo "uv 已是最新(${uv_cur:-未知})"
  fi
  UVCFG="$HOME/.config/uv/uv.toml"
  # uv 在 Windows 读 %APPDATA%\uv\uv.toml,不是 ~/.config
  if [ "$IS_WIN" = 1 ] && [ -n "${APPDATA:-}" ]; then UVCFG="$(cygpath -u "$APPDATA")/uv/uv.toml"; fi
  if grep -q 'pypi.tuna' "$UVCFG" 2>/dev/null; then
    echo "uv PyPI 镜像已配置(清华),跳过"
  elif [ -f "$UVCFG" ]; then
    echo "跳过 uv 镜像:$UVCFG 已存在(非本脚本写入),不覆盖"
  elif [ "$PLAN_UV_MIRROR" = 1 ]; then
    mkdir -p "$(dirname "$UVCFG")"
    printf '%s\n' 'index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"' > "$UVCFG"
    echo "wrote: $UVCFG"
  fi
else
  echo "提示: 未检测到 uv;strictdoc 模块会跳过安装(.sdoc 校验依赖),装好 uv 后重跑本脚本即可"
fi

# ---- 可选模块:按计划阶段选好的名单执行(新增模块只加 modules/<名>/,本脚本不用改)----
if [ -n "$MODULE_RUN" ] && [ -n "$MODULE_SELECTION" ]; then
  # 不写配置时模块仍可装 CLI 等资产，但让需登记 MCP 的模块跳过写 opencode.json。
  AGENT_SKILLS_NO_CONFIG_WRITE="$([ "$PLAN_WRITE_CFG" = 1 ] && echo 0 || echo 1)" \
  bash "$MODULE_RUN" --host opencode --repo "${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}" \
    --ref "${AGENT_SKILLS_REF:-main}" --selected "$MODULE_SELECTION" || { echo 'ERROR: OpenCode 所选模块未完成' >&2; exit 1; }
elif [ -z "$MODULE_RUN" ]; then
  echo "提示: 本次取不到 modules/run.sh,可选模块未执行"
else
  echo "模块: 本次没有选中任何模块"
fi
# ---- 完成:占位符清单 + 收尾动作 ----
echo ""
echo "== done. 需要你手工完成的 =="
n=1
if [ "$PLAN_WRITE_CFG" = 1 ]; then
  echo "$n. 网关/凭据:已按有效配置免问或按需收集并合并；剩余缺项见下(可用环境变量预填、非交互跑:PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY / MCPHUB_HOST)"
else
  echo "$n. 网关/凭据:本次未写配置，未收集或合并凭据；现有值保留"
fi
n=$((n+1))
echo "   当时跳过了才会剩下占位符(<YOUR_*>):"
_ph=0
for _f in "$SETTINGS" "$MC_CFG" "$CFG/opencode.json"; do
  if [ -f "$_f" ] && grep -q '<YOUR_' "$_f" 2>/dev/null; then
    echo "   - $_f:$(grep -o '<YOUR_[A-Z_]*>' "$_f" | sort -u | tr '\n' ' ')"; _ph=1
  fi
done
if [ "$_ph" = 0 ]; then
  _grc=0; needs_gateway_fill || _grc=$?
  _mrc=0; needs_mcphub_fill || _mrc=$?
  if [ "$_grc" = 1 ] && [ "$_mrc" = 1 ]; then
    echo "   (无,已按有效配置核对网关、凭据与 MCP)"
  elif [ "$_grc" = 2 ] || [ "$_mrc" = 2 ]; then
    echo "   WARN: 配置无法解析，不能确认凭据是否齐全"
  else
    echo "   WARN: 仍有空缺的网关、凭据或 MCP 槽位；不能用“无占位符”代替核对"
  fi
fi
echo "   提示:claude-mem 走 openrouter(OpenAI 协议),它的 key 与 magic-context embedding 的各自独立"
echo "$n. claude-mem worker:安装前在运行的话会自动恢复;本次没在跑就手工启动:"; n=$((n+1))
echo "      npx -y claude-mem@latest restart && curl -s http://$(mem_worker_url "$SETTINGS")/api/health   # 端口取自 $SETTINGS(见下方提示)"
echo "$n. 记忆系统规则:已按计划写入 OpenCode 用户级 $CFG/AGENTS.md(或跳过);项目自身的 AGENTS.md 保持原样,项目规则仍写在仓库里"; n=$((n+1))
if command -v codegraph >/dev/null 2>&1 || [ -x "$HOME/.local/bin/codegraph" ]; then
  echo "$n. 代码知识图谱(按项目):cd <项目> && codegraph init(建 .codegraph/ 索引,之后自动增量同步;不 init 则 MCP 无内容可查)"; n=$((n+1))
fi
if [ -f "$NOTIFY_TARGET" ]; then
  echo "$n. notify 插件环境变量 —— 在启动 opencode 的 shell 配置(~/.zshrc 或 ~/.bashrc)里 export:"; n=$((n+1))
  echo "      NOTIFY_GATEWAY_URL=<你的网关地址>    NOTIFY_INGEST_KEY=<你的 ingest key>"
  echo "      可选: NOTIFY_MACHINE=<机器名>(多机区分)"
fi
echo "$n. 退出旧 TUI 和后台服务后重启 OpenCode；官方 npm 缺包由宿主安装，会话库迁移也由宿主处理"
[ "${tail_sync_failed:-0}" = 0 ] || { echo "ERROR: 记忆系统规则块未写入(源码树缺用户级同步实现),项目与全局 AGENTS 均未改动" >&2; exit 1; }
