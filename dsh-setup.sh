#!/usr/bin/env bash
# DeepSeek Harness 套件安装：独立 Node/运行目录，保留已有 profile、凭据与会话。
# 计划：所有人工确认（Node、skills 组、外部设计、AGENTS.tail、订阅密钥、模块）与凭据输入
#      都在任何 mkdir/下载/部署之前一次问完；执行阶段只按 PLAN_* 执行，不再提问。
# 已有 Pi models.json/auth.json 的非空实值直接复用且不询问；占位符或非法网关地址在前置阶段
# 报错退出，不进入安装。
set -euo pipefail
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
YES=0
CHOOSE=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=1 ;;
    --choose) CHOOSE=1 ;;
    *) printf '用法：bash dsh-setup.sh [-y|--yes] [--choose]\n' >&2; exit 2 ;;
  esac
done
have_tty() { { : </dev/tty; } 2>/dev/null; }  # 实际打开设备；-c 测试会误判并让 read 报错
ask_builtin() {
  local answer
  if [[ "$YES" == 1 ]]; then [[ "$2" == Y ]]; return; fi
  have_tty || { [[ "$2" == Y ]]; return; }
  read -r -p "$1 [$2] " answer </dev/tty || answer=
  [[ "${answer:-$2}" =~ ^[Yy]$ ]]
}

# 本机安装偏好：只保存经过校验的是非选择与模块名单，不保存凭据，也不执行文件内容。
PREF_FILE=""; PREF_SESSION=""; PREF_ORIGINAL=""; PREF_REUSE=0; PREF_WRITE=1; PREF_COUNT=0
PREF_KNOWN_KEYS="SHARED_PROXY SHARED_PYTHON_UV SHARED_NODE SHARED_BUN SHARED_UV_INSTALL SHARED_UV_UPGRADE SHARED_UV_MIRROR SHARED_RESEARCH SHARED_ACCEL SHARED_KB SHARED_PPT SHARED_EXTERNAL SHARED_AGENTS_TAIL \
PI_AGENTS_TAIL PI_GIT_BASH PI_INSTALL PI_UPDATE PI_PKGS PI_OC_CACHE_CLEAN PI_MC_UPGRADE PI_MC_FORCE PI_CM_GROUP PI_MCP_MIGRATE PI_WRITE_CFG PI_MEM_RUNTIME PI_LEGACY_CLEAN PI_MODULES PI_MODULES_KNOWN \
OC_AGENTS_TAIL OC_UPGRADE OC_PONYTAIL OC_MC_REFRESH OC_CLAUDE_MEM OC_WRITE_CFG OC_FORCE_MANUAL OC_COMPACTION OC_TUI_KEYS OC_MODULES OC_MODULES_KNOWN \
CODEX_AGENTS_TAIL CODEX_WRITE_CFG CODEX_MEM_INSTALLER CODEX_PLUGINS CODEX_HOOKS CODEX_REVIEWER CODEX_MODULES CODEX_MODULES_KNOWN \
DSH_AGENTS_TAIL DSH_NODE DSH_SKILLS DSH_MODULES DSH_MODULES_KNOWN"
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
  case "$key" in *_MODULES|*_MODULES_KNOWN) [[ "$value" =~ ^[a-z0-9_,-]*$ ]] || return 1 ;;
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
resolve_python3() { # $1=最低 Python 3 小版本，默认 3.6；只接受能实际运行且版本足够的解释器
  local candidate minor="${1:-6}"
  for candidate in python3 python py; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    if [ "$candidate" = py ]; then
      py -3 -c "import sys; sys.exit(sys.version_info < (3, $minor))" >/dev/null 2>&1 || continue
      python3() { py -3 "$@"; }; export -f python3; return 0
    fi
    "$candidate" -c "import sys; sys.exit(sys.version_info < (3, $minor))" >/dev/null 2>&1 || continue
    if [ "$candidate" = python ]; then python3() { python "$@"; }; export -f python3; fi
    return 0
  done
  return 1
}
for cmd in curl tar; do command -v "$cmd" >/dev/null || { printf '缺少依赖：%s\n' "$cmd" >&2; exit 1; }; done
ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/dsh"
DSH_HOME_DIR="${DSH_HOME:-$ROOT/home}"
NODE=""
for candidate in "$(command -v node 2>/dev/null || true)" "$ROOT/node/bin/node" "$HOME/.local/share/pi-node/current/bin/node" "$HOME"/.local/share/fnm/node-versions/*/installation/bin/node; do
  if [[ -x "$candidate" ]] && "$candidate" -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>24||a===24&&b>=15?0:1)' 2>/dev/null; then
    NODE="$candidate"; break
  fi
done

JSON_NODE="$(command -v node 2>/dev/null || true)"
[[ -n "$JSON_NODE" ]] || JSON_NODE="$NODE"
# 旧 Pi Node 不能跑 DSH，但足以只读解析已有 JSON 凭据。
if [[ -z "$JSON_NODE" && -x "$HOME/.local/share/pi-node/current/bin/node" ]]; then
  JSON_NODE="$HOME/.local/share/pi-node/current/bin/node"
fi

# ---- 复用 Pi 已有的 provider 值：只取非空字符串，占位符留给前置校验拒绝 ----
pi_value() { # $1=route $2=BASE_URL|API_KEY → 输出 models.json 里的非空值
  local route="$1" field="$2" js
  js='
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
const [route, field] = process.argv.slice(1);
try {
  const v = JSON.parse(readFileSync(homedir() + "/.pi/agent/models.json", "utf8")).providers?.[route]?.[field === "API_KEY" ? "apiKey" : "baseUrl"];
  if (typeof v === "string" && v.length > 0) process.stdout.write(v);
} catch {}
'
  if [[ -n "$JSON_NODE" ]]; then "$JSON_NODE" --input-type=module -e "$js" "$route" "$field" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$route" "$field" <<'PY' 2>/dev/null || true
import json, os, sys
route, field = sys.argv[1], sys.argv[2]
try:
    v = json.load(open(os.path.expanduser('~/.pi/agent/models.json'), encoding='utf-8'))['providers'][route]['apiKey' if field == 'API_KEY' else 'baseUrl']
    if isinstance(v, str) and v:
        sys.stdout.write(v)
except Exception:
    pass
PY
  fi
}
pi_auth_key() { # $1=route → 输出 auth.json 里的非空 api_key
  local route="$1" js
  js='
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
try {
  const auth = JSON.parse(readFileSync(homedir() + "/.pi/agent/auth.json", "utf8"))[process.argv[1]];
  if (auth?.type === "api_key" && typeof auth.key === "string" && auth.key.length > 0) process.stdout.write(auth.key);
} catch {}
'
  if [[ -n "$JSON_NODE" ]]; then "$JSON_NODE" --input-type=module -e "$js" "$route" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$route" <<'PY' 2>/dev/null || true
import json, os, sys
try:
    auth = json.load(open(os.path.expanduser('~/.pi/agent/auth.json'), encoding='utf-8'))[sys.argv[1]]
    if auth.get('type') == 'api_key' and isinstance(auth.get('key'), str) and auth['key']:
        sys.stdout.write(auth['key'])
except Exception:
    pass
PY
  fi
}

# ---- 计划：所有提问与凭据输入都在写动作之前 ----
PLAN_NODE=0
PLAN_SKILLS=""
PLAN_AGENTS_TAIL=1
PLAN_EXTERNAL_DESIGN=1
PLAN_MODULES=""; PLAN_MOD_PATH=""

config_value_usable() {
  local value="${1-}" placeholder_re='^<[^>]+>$'
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [[ -n "$value" && ! "$value" =~ $placeholder_re ]]
}

validate_gateway_url() { # 与部署共用 Node URL 语义；2=当前尚无 Node
  [[ -n "$JSON_NODE" ]] || return 2
  "$JSON_NODE" --input-type=module -e '
    const value = process.argv[1];
    try {
      if (!value || /\s/.test(value)) process.exit(1);
      const url = new URL(value);
      if (!["http:", "https:"].includes(url.protocol) || !url.hostname) process.exit(1);
    } catch { process.exit(1); }
  ' "$1" 2>/dev/null
}

validate_collected_gateway_urls() {
  [[ "${DSH_PROVIDER_VALIDATION_DEFERRED:-0}" != 1 ]] || return 0
  local route variable rc defer
  for route in CLAUDE_NEWAPI CODEX_NEWAPI ANTHROPIC_NEWAPI GEMINI_NEWAPI; do
    defer="DEFER_${route}_BASE_URL"
    [[ -z "${!defer:-}" ]] || continue
    variable="${route}_BASE_URL"
    rc=0; validate_gateway_url "${!variable}" || rc=$?
    if [[ "$rc" != 0 ]]; then
      printf '%s 不是有效的 http(s) 地址；尚未写入 DSH 配置。\n' "$variable" >&2
      exit 1
    fi
  done
}

dsh_saved_query() { # 0=有值，1=缺，2=不可读，3=坏引用，4=表达式留待部署求值
  local kind="$1" route="$2" field="${3:-}" patch_path="$DSH_HOME_DIR/profiles/headless/cordis.patch.yml" credential_path="$DSH_HOME_DIR/.credentials.yaml"
  # home 层在 headless 之后合成，可能整条覆盖 provider；静态前置不能抢在最终值之前拒绝。
  if [[ "$kind" = provider || "$kind" = state ]] && [[ -f "$DSH_HOME_DIR/cordis.patch.yml" ]]; then return 4; fi
  if [[ ( "$kind" = provider || "$kind" = state ) && ! -f "$patch_path" ]] || [[ "$kind" = ref && ! -f "$credential_path" ]]; then return 1; fi
  if [[ -n "$NODE" && -f "$ROOT/runtime/node_modules/@deepseek-ai/cordis-plugin-include/lib/index.js" ]]; then
    "$NODE" --input-type=module -e '
      import { readFileSync } from "node:fs";
      import { createRequire } from "node:module";
      const [kind, route, field, patchPath, credentialPath, runtime] = process.argv.slice(1);
      try {
        const require = createRequire(runtime + "/package.json");
        const yaml = require("js-yaml");
        const { entryListSchema } = require("@deepseek-ai/cordis-plugin-include");
        const load = path => yaml.load(readFileSync(path, "utf8"), { schema: entryListSchema });
        if (kind === "state") {
          const doc = load(patchPath) ?? [];
          const row = Array.isArray(doc) ? doc.filter(item => item?.id === "llm-pi-ai").at(-1) : undefined;
          const value = row?.disabled;
          if (value && typeof value === "object" && typeof value.__jsExpr === "string") process.stdout.write("defer");
          else process.stdout.write(value ? "disabled" : "enabled");
          process.exit(0);
        }
        if (kind === "provider") {
          const doc = load(patchPath) ?? [];
          const config = (Array.isArray(doc) ? doc.filter(row => row?.id === "llm-pi-ai").at(-1) : null)?.config;
          if (config && typeof config === "object" && typeof config.__jsExpr === "string") process.exit(4);
          const providers = config?.providers ?? {};
          if (providers && typeof providers === "object" && typeof providers.__jsExpr === "string") process.exit(4);
          let saved;
          if (route === "gemini-newapi") {
            if (providers.google != null && providers["gemini-newapi"] != null) process.exit(2);
            saved = providers.google ?? providers["gemini-newapi"];
          } else saved = providers[route];
          if (saved && typeof saved === "object" && typeof saved.__jsExpr === "string") process.exit(4);
          const value = saved?.[field];
          if (value == null || (field === "apiKeyEnv" && !value)) process.exit(1);
          if (typeof value === "object" && typeof value.__jsExpr === "string") process.exit(4);
          if (typeof value !== "string") process.exit(2);
          process.stdout.write(value);
        } else {
          const value = load(credentialPath)?.refs?.[route];
          if (value == null) process.exit(1);
          if (typeof value === "object" && typeof value.__jsExpr === "string") process.exit(4);
          if (typeof value !== "string" || !value.trim() || /^<[^>]+>$/.test(value.trim())) process.exit(3);
          process.stdout.write("valid");
        }
      } catch { process.exit(2); }
    ' "$kind" "$route" "$field" "$patch_path" "$credential_path" "$ROOT/runtime" 2>/dev/null
    return
  fi
  command -v python3 >/dev/null 2>&1 || return 2
  python3 - "$kind" "$route" "$field" "$patch_path" "$credential_path" <<'PY' 2>/dev/null
import math, re, sys
try:
    import yaml
except ImportError:
    raise SystemExit(2)
class EntryLoader(yaml.SafeLoader):
    pass
def js_expr(loader, node):
    return {'__jsExpr': loader.construct_scalar(node)}
EntryLoader.add_constructor('tag:yaml.org,2002:js', js_expr)
kind, route, field, patch_path, credential_path = sys.argv[1:6]
def load(path):
    with open(path, encoding='utf-8') as f:
        return yaml.load(f, Loader=EntryLoader)
def is_expr(value):
    return isinstance(value, dict) and isinstance(value.get('__jsExpr'), str)
def js_truthy(value):
    if value is None or value is False:
        return False
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value != 0 and not math.isnan(value)
    if isinstance(value, str):
        return bool(value)
    return True
try:
    if kind == 'state':
        doc = load(patch_path) or []
        row = next((r for r in reversed(doc) if isinstance(r, dict) and r.get('id') == 'llm-pi-ai'), None) if isinstance(doc, list) else None
        value = (row or {}).get('disabled')
        sys.stdout.write('defer' if is_expr(value) else 'disabled' if js_truthy(value) else 'enabled')
        raise SystemExit(0)
    if kind == 'provider':
        doc = load(patch_path) or []
        row = next((r for r in reversed(doc) if isinstance(r, dict) and r.get('id') == 'llm-pi-ai'), None) if isinstance(doc, list) else None
        config = (row or {}).get('config')
        if is_expr(config):
            raise SystemExit(4)
        providers = config.get('providers', {}) if isinstance(config, dict) else {}
        if is_expr(providers):
            raise SystemExit(4)
        if route == 'gemini-newapi':
            if providers.get('google') is not None and providers.get('gemini-newapi') is not None:
                raise SystemExit(2)
            saved = providers.get('google') if providers.get('google') is not None else providers.get('gemini-newapi')
        else:
            saved = providers.get(route)
        if is_expr(saved):
            raise SystemExit(4)
        value = saved.get(field) if isinstance(saved, dict) else None
        if value is None or (field == 'apiKeyEnv' and not value):
            raise SystemExit(1)
        if is_expr(value):
            raise SystemExit(4)
        if not isinstance(value, str):
            raise SystemExit(2)
        sys.stdout.write(value)
    else:
        value = (load(credential_path) or {}).get('refs', {}).get(route)
        if value is None:
            raise SystemExit(1)
        if is_expr(value):
            raise SystemExit(4)
        if not isinstance(value, str) or not value.strip() or re.fullmatch(r'<[^>]+>', value.strip()):
            raise SystemExit(3)
        sys.stdout.write('valid')
except SystemExit:
    raise
except Exception:
    raise SystemExit(2)
PY
}

collect_credentials() {
  local route prefix variable value saved_url saved_env rc key_env provider_state
  DSH_PROVIDER_VALIDATION_DEFERRED=0
  [[ ! -f "$DSH_HOME_DIR/profiles/headless/cordis.patch.yml" ]] || printf '保留 DSH 已有 provider 配置；按真实 YAML 检查最终启用条目\n'
  rc=0; provider_state="$(dsh_saved_query state "")" || rc=$?
  if [[ "$rc" = 1 ]]; then provider_state=enabled; fi
  [[ "$rc" != 2 ]] || { printf '已有 DSH provider 配置无法按宿主 YAML 语义解析；尚未写入任何内容。\n' >&2; exit 1; }
  if [[ "$rc" = 4 || "$provider_state" != enabled ]]; then
    DSH_PROVIDER_VALIDATION_DEFERRED=1
  else
  for route in claude-newapi codex-newapi anthropic-newapi gemini-newapi; do
    prefix=$(printf '%s' "$route" | tr 'a-z-' 'A-Z_')
    variable="${prefix}_BASE_URL"
    rc=0; saved_url="$(dsh_saved_query provider "$route" baseURL)" || rc=$?
    if [[ "$rc" = 2 ]]; then
      printf '已有 DSH provider 配置无法按宿主 YAML 语义解析或含双 Gemini 键；尚未写入任何内容。\n' >&2
      exit 1
    elif [[ "$rc" = 4 ]]; then
      printf -v "DEFER_${prefix}_BASE_URL" '1'
    else
      value=""
      if [[ "$rc" = 0 ]] && config_value_usable "$saved_url"; then
        value="$saved_url"
      elif config_value_usable "${!variable:-}"; then
        value="${!variable}"
      else
        value="$(pi_value "$route" BASE_URL)"
      fi
      if ! config_value_usable "$value"; then
        printf '缺少有效 %s（空白或占位符无效）；可用环境变量提供后重跑（尚未写入任何内容）。\n' "$variable" >&2
        exit 1
      fi
      if [[ "$value" == *"<"*">"* ]]; then
        printf '%s 仍含占位符，需先填实值；尚未写入任何内容。\n' "$variable" >&2
        exit 1
      fi
      if [[ -n "$JSON_NODE" ]]; then
        rc=0; validate_gateway_url "$value" || rc=$?
        if [[ "$rc" != 0 ]]; then
          printf '%s 不是有效的 http(s) 地址；尚未写入 DSH 配置。\n' "$variable" >&2
          exit 1
        fi
      fi
      export "$variable=$value"
    fi

    rc=0; saved_env="$(dsh_saved_query provider "$route" apiKeyEnv)" || rc=$?
    [[ "$rc" != 2 ]] || { printf '已有 DSH 凭据引用无法解析；尚未写入任何内容。\n' >&2; exit 1; }
    [[ "$rc" != 4 ]] || continue
    if [[ "$rc" = 0 ]]; then key_env="$saved_env"; else key_env="${prefix}_API_KEY"; fi
    # 不回显误填的值：apiKeyEnv 槽位常被误填成真实密钥，只能报位置。
    [[ "$key_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { printf '现有配置里的凭据引用名（apiKeyEnv）不是合法的环境变量名；值已隐藏。请修正后重跑，尚未写入任何内容。\n' >&2; exit 1; }
    rc=0; dsh_saved_query ref "$key_env" >/dev/null || rc=$?
    case "$rc" in
      0|4) continue ;;
      3) printf 'provider %s 在现有凭据库中的引用不是非空字符串或仍为占位，需先修复；尚未写入任何内容。\n' "$route" >&2; exit 1 ;;
      2) printf '现有凭据库无法按 YAML 解析；尚未写入任何内容。\n' >&2; exit 1 ;;
    esac
    value="${!key_env:-}"
    config_value_usable "$value" || value="$(pi_value "$route" API_KEY)"
    config_value_usable "$value" || value="$(pi_auth_key "$route")"
    if ! config_value_usable "$value"; then
      # 引用名可能被误填成真实密钥（合法变量名形态无法与密钥区分），一律只报 provider 与字段位置。
      printf 'provider %s 的 apiKeyEnv 没有可用的凭据（空白或占位符无效）；可用对应的环境变量、现有凭据引用或 Pi 配置提供后重跑（尚未写入任何内容）。\n' "$route" >&2
      exit 1
    fi
    export "$key_env=$value"
  done
  fi
  [[ -f "$DSH_HOME_DIR/.credentials.yaml" ]] && return 0
  for route in zai-coding-cn kimi-coding; do
    variable="$(printf '%s' "$route" | tr 'a-z-' 'A-Z_')_API_KEY"
    [[ -n "${!variable:-}" ]] || {
      value="$(pi_auth_key "$route")"
      [[ -z "$value" ]] || export "$variable=$value"
    }
    [[ -n "${!variable:-}" ]] && continue
    if ask "填写 $route 的订阅密钥（也可稍后配置 $variable）？" N; then
      read -r -s -p "$route API Key（不回显）：" value </dev/tty
      printf '\n'
      [[ -z "$value" ]] || export "$variable=$value"
    fi
  done
}

collect_setup_plan() {
  local msel="" python_min=6
  # 先建立只读解释器，再读取 Pi 凭据；此处不安装 Python。
  resolve_python3 || true
  # 凭据先于一切：占位符/非法网关在此报错，早于任何下载、mkdir 与部署。
  collect_credentials
  if [[ -z "$NODE" ]]; then
    ask '为 dsh 安装独立 Node 24（不更改系统 Node）？' Y DSH_NODE || exit 1
    PLAN_NODE=1
  fi
  # 源码基准是部署与 skills 的共同输入:凭据校验通过后才可能 clone、mkdir
  validate_collected_gateway_urls
  acquire_source || exit 1
  # 每次都问，不因已有 profile 而跳过：重跑仍默认 base、可选组、外部依赖、AGENTS 尾块与模块
  if ask '同步基础 skills（base；复用 ~/.agents/skills）？' Y DSH_SKILLS; then
    PLAN_SKILLS=" base"
    ask '安装/更新 research 组（算法研究、实验、PyTorch 性能与 kernel；每次刷新·漂移自动备份）？' N SHARED_RESEARCH && PLAN_SKILLS+=" research"
    ask '安装/更新 accel 组（算力平台模板；缺才装·本机特化不覆盖）？' N SHARED_ACCEL && PLAN_SKILLS+=" accel"
    ask '安装/更新 kb 组（公共算力知识；每次刷新）？' N SHARED_KB && PLAN_SKILLS+=" kb"
    ask '安装/更新 ppt 组（南大 HTML/PPTX、Dashi、ppt-master 与独立依赖；需 Node 20+、Python 3.10+）？' N SHARED_PPT && PLAN_SKILLS+=" ppt"
    case "${SKILLS_EXTERNAL:-}" in
      skip) PLAN_EXTERNAL_DESIGN=0 ;;
      install) ;;
      *) ask '安装/更新外部设计依赖（ui-ux-pro-max、huashu-design、design-taste-frontend）？' Y SHARED_EXTERNAL || PLAN_EXTERNAL_DESIGN=0 ;;
    esac
    case "${AGENTS_TAIL:-}" in
      0) PLAN_AGENTS_TAIL=0 ;;
      1) ;;
      *) # 旧键 SHARED_AGENTS_TAIL 只代表项目级同意：拒绝继续生效，同意不升级为全局同意。
         if [ "${PREF_REUSE:-0}" = 1 ] && [ "$(preference_get SHARED_AGENTS_TAIL || true)" = 0 ] \
            && ! preference_get DSH_AGENTS_TAIL >/dev/null; then PLAN_AGENTS_TAIL=0
         elif ask "把记忆系统规范块写进 DSH 用户级 $DSH_HOME_DIR/AGENTS.md(所有项目共用)?" Y DSH_AGENTS_TAIL; then PLAN_AGENTS_TAIL=1
         else PLAN_AGENTS_TAIL=0; fi ;;
    esac
    # skills-sync 只有 AGENTS 尾块写入与 ppt 组用 python3；先确认再取模块名单，
    # 失败时不下载任何东西。可用时 export -f python3 让子 Bash 复用同一解释器。
    if [[ "$PLAN_AGENTS_TAIL" = 1 || "$PLAN_SKILLS" == *" ppt"* ]]; then
      [[ "$PLAN_SKILLS" == *" ppt"* ]] && python_min=10
      resolve_python3 "$python_min" || {
        printf '当前选择需要 Python 3.%s+（python3／python／py -3）；请先安装后重跑，尚未下载或写入。\n' "$python_min" >&2
        exit 1
      }
    fi
    # 模块名单一次问完；执行阶段用 --selected 只跑已选项
    PLAN_MOD_PATH="$SOURCE_ROOT/modules/run.sh"
    [[ -f "$PLAN_MOD_PATH" ]] || PLAN_MOD_PATH=""
    if [[ -n "$PLAN_MOD_PATH" ]]; then
      local saved_modules="" known_modules="" mod_env=("PATH=$PATH")
      [[ "$YES" != 1 ]] || msel="--yes"
      if [ "${PREF_REUSE:-0}" = 1 ]; then
        saved_modules="$(preference_get DSH_MODULES || true)"
        known_modules="$(preference_get DSH_MODULES_KNOWN || true)"
        mod_env=("AGENT_SKILLS_MODULE_SELECTION=$saved_modules" "AGENT_SKILLS_MODULE_KNOWN=$known_modules")
      fi
      if PLAN_MODULES="$(env "${mod_env[@]}" bash "$PLAN_MOD_PATH" --host dsh $msel --select)"; then
        preference_put DSH_MODULES "${PLAN_MODULES//$'\n'/,}"
        if known_modules="$(bash "$PLAN_MOD_PATH" --host dsh --list)"; then
          known_modules="$(printf '%s\n' "$known_modules" | awk '{print $1}' | paste -sd, -)"
          preference_put DSH_MODULES_KNOWN "$known_modules"
        fi
      else
        PLAN_MODULES=""
      fi
    fi
  fi
}
preferences_init
collect_setup_plan
preferences_commit

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
if [[ "$PLAN_NODE" = 1 ]]; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) platform=linux-x64;; Linux-aarch64) platform=linux-arm64;;
    Darwin-x86_64) platform=darwin-x64;; Darwin-arm64) platform=darwin-arm64;;
    *) printf '请先安装 Node >=24.15，再运行本脚本。\n' >&2; exit 1;;
  esac
  node_tar="$STAGE/node.tar.gz"
  curl -fsSL --connect-timeout 8 -m 180 "https://nodejs.org/dist/v24.21.0/node-v24.21.0-$platform.tar.gz" -o "$node_tar"
  mkdir -p "$STAGE/node"
  tar -xzf "$node_tar" -C "$STAGE/node" --strip-components=1
  NODE="$STAGE/node/bin/node"
fi
NODE=$("$NODE" -p 'process.execPath')
JSON_NODE="$NODE"
validate_collected_gateway_urls
mkdir -p "$ROOT"
if [[ "$PLAN_NODE" = 1 ]]; then
  if [[ -e "$ROOT/node" || -L "$ROOT/node" ]]; then mv "$ROOT/node" "$ROOT/node.bak-$(date +%Y%m%d%H%M%S)"; fi
  mv "$STAGE/node" "$ROOT/node"
  NODE="$ROOT/node/bin/node"
  JSON_NODE="$NODE"
fi
_node_dir="$(dirname "$NODE")"
export PATH="$_node_dir:$PATH"
claude_bundle="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/thedotmack/dsh"
SOURCE="$SOURCE_ROOT"
curl -fsSL --connect-timeout 8 -m 60 "$RAW/dsh/cordis.patch.json" -o "$STAGE/template.json"
curl -fsSL --connect-timeout 8 -m 120 https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz -o "$STAGE/context-mode.tar.gz"
mkdir -p "$STAGE/context-mode"
tar -xzf "$STAGE/context-mode.tar.gz" -C "$STAGE/context-mode"
curl -fsSL --connect-timeout 8 -m 120 https://github.com/wk544863858/dsh-plugin-magic-context/archive/bb581b4d99fda7608063596d69adb936b706d961.tar.gz -o "$STAGE/magic-context.tar.gz"
mkdir -p "$STAGE/magic-context"
tar -xzf "$STAGE/magic-context.tar.gz" -C "$STAGE/magic-context" --strip-components=1
args=(--root "$ROOT" --source "$SOURCE" --template "$STAGE/template.json" --contextMode "$STAGE/context-mode" --magicContext "$STAGE/magic-context")
if [[ -f "$claude_bundle/lib/index.js" ]]; then
  args+=(--claudeMem "$claude_bundle")
else
  printf '尚无官方 claude-mem 运行目录；先完成 dsh 安装，随后可用官方安装器接入。\n'
fi
[[ "$YES" != 1 ]] || args+=(--yes)
"$NODE" "$SOURCE/dsh/deploy.mjs" "${args[@]}"
"$ROOT/dsh" --version
mkdir -p "$HOME/.local/bin"
command_path="$HOME/.local/bin/dsh"
if [[ -L "$command_path" && "$(readlink "$command_path")" == "$ROOT/dsh" ]]; then
  :
elif [[ -e "$command_path" || -L "$command_path" ]]; then
  printf '已有自定义入口，未覆盖：%s；套件入口为 %s/dsh\n' "$command_path" "$ROOT" >&2
else
  ln -s "$ROOT/dsh" "$command_path"
fi
previous=$(command -v dsh || true)
if [[ -n "$previous" && -L "$previous" ]]; then
  case "$(readlink "$previous")" in
    *'@deepseek-ai/dsh/'*)
      alpha="$(dirname "$previous")/dsh-alpha"
      [[ ! -e "$alpha" && ! -L "$alpha" ]] || alpha="$previous.bak-$(date +%Y%m%d%H%M%S)"
      mv "$previous" "$alpha"
      ln -s "$ROOT/dsh" "$previous"
      printf '旧 alpha 入口保留为 %s\n' "$alpha"
      ;;
  esac
fi
if [[ -n "$PLAN_SKILLS" ]]; then
  _dsh_ss="$SOURCE_ROOT/skills-sync.sh"
  # 旧缓存里的 skills-sync 仍写当前项目;缺脚本或不走用户级 helper 时不委派规则块,项目与全局都不动。
  if [[ "$PLAN_AGENTS_TAIL" = 1 ]] && { [[ ! -f "$_dsh_ss" ]] || ! grep -q 'migrate-agents-tail.py' "$_dsh_ss"; }; then
    printf 'ERROR: 源码树 skills-sync.sh 缺失或不走用户级规则 helper;本次不改项目/全局 AGENTS,请更新源码树后重跑\n' >&2
    PLAN_AGENTS_TAIL=0; tail_sync_failed=1
  fi
  AGENTS_TAIL="$PLAN_AGENTS_TAIL" AGENTS_TAIL_HOST=dsh DSH_HOME="$DSH_HOME_DIR" \
    SKILLS_EXTERNAL="$([[ "$PLAN_EXTERNAL_DESIGN" = 1 ]] && echo install || echo skip)" \
    ASSUME_YES="$YES" AGENT_SKILLS_SOURCE="$SOURCE_ROOT" \
    bash "$_dsh_ss" $PLAN_SKILLS || printf 'WARN: skills 同步未完全成功\n' >&2
fi

# ---- 可选模块:统一分发(新增模块只加 modules/<名>/,本脚本不用改)----
# 名单在计划阶段用 --select 一次问完，这里只执行已选项。
if [[ -n "$PLAN_SKILLS" && -f "$PLAN_MOD_PATH" ]]; then
  bash "$PLAN_MOD_PATH" --host dsh --repo "${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}" \
    --ref "${AGENT_SKILLS_REF:-main}" --selected "$PLAN_MODULES" || printf 'WARN: 模块安装未完全成功\n' >&2
elif [[ -n "$PLAN_SKILLS" ]]; then
  printf 'WARN: 取不到 modules/run.sh,跳过可选模块\n' >&2
fi
printf '\n安装完成。新终端运行 dsh tui；批处理运行 dsh --profile headless "任务"。\n'
[ "${tail_sync_failed:-0}" = 0 ] || { printf 'ERROR: 记忆系统规则块未写入(源码树缺用户级同步实现),项目与全局 AGENTS 均未改动\n' >&2; exit 1; }
if [[ ! -f "$claude_bundle/lib/index.js" ]]; then
  printf 'claude-mem 官方安装命令：DSH_HOME=%q npx -y claude-mem@latest install --ide dsh --dsh-profile tui --no-auto-start\n' "$DSH_HOME_DIR"
fi
