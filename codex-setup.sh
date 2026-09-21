#!/usr/bin/env bash
# codex-setup.sh — Codex 插件配置(best effort;本仓库仍以 OpenCode 为主)
# 0. 检查 Codex >=0.128.0 及插件命令、Python 3.11+、网络;不安装/升级 Codex 本体
# 1. 缺失时询问安装 Node LTS、Bun、uv;可选安装 strictdoc==0.28.1
# 2. claude-mem:优先复用本机 runtime;缺失时运行官方 codex-cli 安装器
#    安装器会修改共享配置并停止 worker;恢复 settings.json/原 Codex 配置,再原生注册;
#    settings.json 用 dot_file 模板做字段级合并(与 pi/opencode 两侧同一份,敏感值保留)
# 3. 原生安装 Ponytail;注册 CodeGraph MCP;安装缺失的本仓库 skills(不修改内容)
# 4. 提示 /hooks 信任和 /mcp 检查;Magic Context、notify 不安装,原生压缩不变
# 已配置项不重写、不自动升级;冲突/显式禁用项保留;修改前备份,不碰模型/认证配置
# (例外:~/.claude-mem/settings.json 走 dot_file 模板字段级合并,api key/base url 等敏感值仍保留)
# 用法:bash codex-setup.sh [-y|--yes];支持 CODEX_HOME(首次 claude-mem 官方安装仅支持默认路径)
set -euo pipefail

# -y/--yes(或环境变量 ASSUME_YES=1):自动回答「默认就是 Y」的确认项;默认 N 的项(如共享 runtime 升级)仍人工确认
ASSUME_YES="${ASSUME_YES:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) echo "用法: bash <本脚本> [-y|--yes]   # -y 跳过默认 Y 的确认项,默认 N 的仍人工确认"; exit 0 ;;
    *) echo "未知参数: $1(仅支持 -y|--yes / -h|--help)" >&2; exit 2 ;;
  esac
  shift
done

CFG="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CFG/config.toml"
MEM_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/thedotmack"
SETTINGS="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json"
RAW="https://raw.githubusercontent.com/brilliantrough/dot_file/master"
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
errors=0

ask() {
  local a="" def="${2:-N}" hint="y/N"
  [ "$def" = Y ] && hint="Y/n"
  # -y:只对默认 Y 的项自动通过;默认 N 的照样问,避免不知情的覆盖/升级
  if [ -n "$ASSUME_YES" ] && [ "$def" = Y ]; then echo "$1 [$hint] → 是 (-y)"; return 0; fi
  if { true < /dev/tty; } 2>/dev/null && read -r -p "$1 [$hint] " a < /dev/tty; then
    if [ -z "$a" ]; then [ "$def" = Y ]; else [[ "$a" =~ ^[Yy]$ ]]; fi
  else
    echo "$1 [$hint] (非交互,默认 $def)"
    [ "$def" = Y ]
  fi
}
warn() { echo "WARN: $*" >&2; errors=$((errors + 1)); }

# 把 worker 地址显式写进 settings(claude-mem 自身的默认是 37700 + uid%100,
# 目的就是同一台服务器上不同用户互不冲突;写出来是为了可见、可查,不改变取值)。
# 已存在的键一律保留(自定义端口/主机不被覆盖)。改前存 .bak。
ensure_mem_worker_keys() {
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
want = {'CLAUDE_MEM_WORKER_HOST': '127.0.0.1', 'CLAUDE_MEM_WORKER_PORT': str(37700 + os.getuid() % 100)}
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
  python3 - "$SETTINGS" <<'PYEOF'
import json, os, sys
try:
    s = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    s = {}
host = os.environ.get('CLAUDE_MEM_WORKER_HOST') or s.get('CLAUDE_MEM_WORKER_HOST') or '127.0.0.1'
port = os.environ.get('CLAUDE_MEM_WORKER_PORT') or s.get('CLAUDE_MEM_WORKER_PORT') or str(37700 + os.getuid() % 100)
print(f'{host}:{port}')
PYEOF
}

# ---- 网关占位符预填：新机器只需填 base url + api key ----
# 环境变量优先(便于无人值守):PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY
GW_BASE="${PI_GATEWAY_BASE_URL:-}"; GW_KEY="${PI_GATEWAY_API_KEY:-}"
# codex 侧不配 mcphub;此变量仅为与 pi/opencode 的 merge_cfg 保持逐字节一致
MCPHUB_HOST="${MCPHUB_HOST:-}"

ask_value() { # $1=提示 $2=输出变量 $3=非空则不回显(用于 key)
  local a=""
  # -y 下不阻塞:等同回车跳过,占位符保留
  if [ -n "$ASSUME_YES" ]; then echo "$1: (跳过,-y)"; return 0; fi
  if { exec 9</dev/tty; } 2>/dev/null; then
    if [ -n "${3:-}" ]; then read -r -s -u 9 -p "$1: " a || a=""; echo
    else read -r -u 9 -p "$1: " a || a=""; fi
    exec 9<&-
    printf -v "$2" '%s' "$a"
  fi
}

needs_gateway_fill() {
  [ -f "$SETTINGS" ] || return 0
  grep -q '<YOUR_' "$SETTINGS" 2>/dev/null && return 0
  return 1
}

collect_gateway_values() {
  [ -n "$GW_BASE" ] && [ -n "$GW_KEY" ] && return 0
  needs_gateway_fill || return 0
  [ -z "$GW_BASE" ] && ask_value "OpenAI 兼容网关完整地址(如 https://gw.example.com/v1;回车跳过)" GW_BASE
  if [ -z "$GW_BASE" ]; then
    echo "未提供网关地址:占位符保留,装完手工填"
    return 0
  fi
  [ -z "$GW_KEY" ] && ask_value "该网关 API key(回车跳过)" GW_KEY 1
  return 0
}

# 把已提供的值填进文件(python 负责 JSON 转义);未提供则原样保留占位符。
fill_template_placeholders() {
  [ -z "$GW_BASE$GW_KEY" ] && return 0
  [ -f "$1" ] || return 0
  python3 - "$1" "$GW_BASE" "$GW_KEY" <<'PYEOF'
import json, re, sys
p, base, key = sys.argv[1], sys.argv[2].rstrip('/'), sys.argv[3]
def esc(v): return json.dumps(v)[1:-1]
t = open(p, encoding='utf-8').read()
if base:
    # <YOUR_GATEWAY_HOST>/v1 这类槽位填完整 base(含路径);单独的 <YOUR_GATEWAY_HOST> 填主机名,
    # 因为 pi 的 anthropic-messages provider 要根域(/v1 会 404),模板自己在后面接 /v1。
    host = re.match(r'^(https?://[^/]+)', base)
    host = host.group(1) if host else base
    t = t.replace('https://<YOUR_GATEWAY_HOST>/v1', esc(base))
    t = t.replace('<YOUR_GATEWAY_HOST>/v1', esc(base))
    t = t.replace('<YOUR_GATEWAY_HOST>', esc(re.sub(r'^https?://', '', host)))
    t = t.replace('<YOUR_NEWAPI_BASE_URL>', esc(base))
if key:
    t = t.replace('<YOUR_NEWAPI_API_KEY>', esc(key)).replace('<YOUR_API_KEY>', esc(key))
open(p, 'w', encoding='utf-8').write(t)
PYEOF
  return 0
}
merge_cfg() {
  local url="$1" dest="$2" tmp cand out
  if [ -L "$dest" ]; then
    echo "跳过: $dest 是符号链接(指向 $(readlink "$dest")),不覆盖以免破坏链接目标"
    return 1
  fi
  # 操作员在提示里给了网关/密钥:先把本地文件里的占位符补上(改前存 .bak),再走正常合并
  # (补进去的是敏感键,合并会原样保留)。目标文件不存在时由模板侧的 fill_template_placeholders 负责。
  if [ -f "$dest" ] && [ -n "$GW_BASE$GW_KEY$MCPHUB_HOST" ] && grep -q '<YOUR_' "$dest" 2>/dev/null; then
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
    if ask "写入 $dest(来自 dot_file 模板,含占位符)?" Y; then
      mkdir -p "$(dirname "$dest")"; cp "$tmp" "$dest"; echo "wrote: $dest(含占位符)"
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
    return json.loads(re.sub(r',(\s*[}\]])', r'\1', ''.join(out)))

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
        if k in cur and k.startswith('CLAUDE_MEM_') and (k.endswith('_MODEL') or k.endswith('_BASE_URL') or k.endswith('_API_KEY')\
                or k.endswith('_PORT') or k.endswith('_HOST')):
            continue  # 已有模型/接口/凭据保留，包括占位值
        if k in cur and SENSITIVE.search(k):                       # 敏感键:本地值优先
            continue
        if k in cur and isinstance(v, str) and PLACEHOLDER.search(v):  # 占位值不覆盖已填内容
            continue
        if k in UNION_KEYS and isinstance(v, list) and isinstance(cur.get(k), list):
            out[k] = cur[k] + [x for x in v if x not in cur[k]]        # 并集:本地顺序 + 模板新增
            continue
        out[k] = merge(cur.get(k), v) if isinstance(v, dict) else v
    return out

merged = merge(cur, new)
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
  local bak="$dest.bak-$(date +%Y%m%d%H%M%S)"
  case "$out" in
    unchanged) echo "unchanged: $dest(已与模板一致,无需改动)"; rm -f "$cand" ;;
    "")        echo "WARN: $dest 合并失败,保留原文件" >&2; rm -f "$cand"; return 1 ;;
    *)         if ask "更新 $dest($out;api key 等敏感值保留,原文件存 $bak)?" Y; then
                 cp "$dest" "$bak"; mv "$cand" "$dest"; echo "updated: $dest"
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
  if ask "安装 $id?" Y; then
    backup "$CONFIG" || return 1
    codex plugin marketplace add "$source" || return 1
    codex plugin add "$id" || return 1
  fi
}

echo "== Codex 插件配置(best effort) =="
for cmd in curl git python3 codex; do
  command -v "$cmd" >/dev/null || { echo "ERROR: 缺少 $cmd,请先安装后重跑" >&2; exit 1; }
done
python3 -c 'import tomllib' 2>/dev/null || { echo 'ERROR: 需要 Python 3.11+(tomllib);请在合适的环境中重跑,脚本不会升级系统 Python' >&2; exit 1; }
codex plugin marketplace add --help >/dev/null
codex features enable --help >/dev/null
version="$(codex --version)"
python3 - "$version" <<'PY'
import re, sys
m = re.search(r'(\d+)\.(\d+)\.(\d+)', sys.argv[1])
if not m or tuple(map(int, m.groups())) < (0, 128, 0):
    sys.exit('ERROR: 需要 Codex >=0.128.0,请手工升级后重跑')
PY
echo "$version;配置目录: $CFG"
if [ -L "$CFG" ] || [ -L "$CONFIG" ]; then
  echo "ERROR: $CFG 或 config.toml 是符号链接,不穿透修改" >&2; exit 1
fi
value >/dev/null  # 解析失败立即退出,绝不将损坏配置当成空文件
mkdir -p "$CFG"
export CODEX_HOME="$CFG"

proxy="${http_proxy:-${https_proxy:-${all_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-${ALL_PROXY:-}}}}}}"
if [ -n "$proxy" ]; then
  echo '已检测到代理环境变量'
elif curl -fsSI --connect-timeout 5 -m 8 -o /dev/null https://github.com; then
  echo '未设代理,但 github.com 可直连,继续'
else
  ask '未设代理且 github.com 不可达,仍继续?' || exit 1
fi

# ---- 1. runtime 依赖 ----
if ! command -v npx >/dev/null || ! command -v node >/dev/null; then
  if ask '安装 fnm + Node LTS?' Y; then
    if download_run https://fnm.vercel.app/install; then
      export PATH="$HOME/.local/share/fnm:$PATH"
      eval "$(fnm env)"
      fnm install --lts
      fnm default lts-latest
      eval "$(fnm env)"
    else warn 'Node 安装失败'; fi
  fi
fi
if command -v node >/dev/null; then
  node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 20 ? 1 : 0)' || {
    echo 'ERROR: claude-mem 需要 Node >=20,请切换 Node 后重跑' >&2; exit 1;
  }
fi
if ! command -v bun >/dev/null && ask '安装 Bun(claude-mem runtime)?' Y; then
  download_run https://bun.sh/install || warn 'Bun 安装失败'
fi
if ! command -v uv >/dev/null && ask '安装 uv(claude-mem/StrictDoc 依赖)?' Y; then
  UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 download_run https://astral.sh/uv/install.sh || warn 'uv 安装失败'
fi
if command -v uv >/dev/null && ! command -v strictdoc >/dev/null; then
  if ask '用 uv 全局安装 strictdoc==0.28.1?' Y; then
    uv tool install strictdoc==0.28.1 || warn 'StrictDoc 安装失败'
  fi
fi

# ---- 2. claude-mem:复用资产可避免改动共享 worker/provider ----
mem_ready() {
  [ -f "$MEM_ROOT/.agents/plugins/marketplace.json" ] &&
  [ -f "$MEM_ROOT/plugin/.codex-plugin/plugin.json" ] &&
  [ -f "$MEM_ROOT/plugin/hooks/codex-hooks.json" ] &&
  [ -f "$MEM_ROOT/plugin/.mcp.json" ] &&
  [ -f "$MEM_ROOT/plugin/scripts/worker-service.cjs" ] &&
  [ -f "$MEM_ROOT/plugin/scripts/mcp-server.cjs" ]
}
# 记忆后端必须走 OpenAI 兼容的 openrouter provider;安装器或旧配置写成 claude 时纠正。
# 只改这一个键,模型/接口/凭据原样保留。
ensure_mem_provider() {
  local f="$1" tmp
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
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
    mv "$tmp" "$f"; echo "updated: $f (CLAUDE_MEM_PROVIDER=openrouter)"
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
  for target in "$SETTINGS" "$(dirname "$SETTINGS")" "$HOME/.codex/AGENTS.md" \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" "$MEM_ROOT" \
    "${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/transcript-watch.json"; do
    if [ -L "$target" ]; then
      echo "ERROR: $target 是符号链接,请手工安装 claude-mem" >&2; return 1
    fi
  done
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
if [ "$(value plugins 'claude-mem@claude-mem-local' enabled)" = false ]; then
  echo '保留: claude-mem 已被显式禁用'
elif [ "$(value plugins 'claude-mem@thedotmack')" != null ] || [[ "$(value mcp_servers)" == *claude-mem* ]]; then
  warn '发现已有 claude-mem 旧插件或独立 MCP 配置,保留原配置;请手工处理后再接入原生插件,避免重复加载'
elif ! command -v npx >/dev/null || ! command -v bun >/dev/null || ! command -v uv >/dev/null; then
  warn '缺少 npx/Bun/uv,跳过 claude-mem'
elif [ -L "$SETTINGS" ] || [ -L "$(dirname "$SETTINGS")" ]; then
  warn 'claude-mem settings 路径是符号链接,跳过自动配置'
else
  mem_ok=1
  collect_gateway_values
  # 已存在但仍含占位符时按提示补上(改前存 .bak);不存在则由下面的内嵌模板写入后再补
  if [ -f "$SETTINGS" ] && [ -n "$GW_BASE$GW_KEY" ] && grep -q '<YOUR_' "$SETTINGS" 2>/dev/null; then
    backup "$SETTINGS" >/dev/null || true
    fill_template_placeholders "$SETTINGS"
    echo "filled placeholders: $SETTINGS"
  fi
  [ -f "$SETTINGS" ] && ensure_mem_worker_keys "$SETTINGS" 2>/dev/null || true
  if [ ! -e "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
    if ask "新建 $SETTINGS(记忆后端占位符,不涉及 Codex 模型)?" Y; then
      mkdir -p "$(dirname "$SETTINGS")"
      (umask 077; cat > "$SETTINGS" <<'JSON'
{
  "CLAUDE_MEM_RUNTIME": "worker",
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "<YOUR_NEWAPI_BASE_URL>",
  "CLAUDE_MEM_OPENROUTER_MODEL": "<YOUR_MODEL_NAME>",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>",
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "20",
  "CLAUDE_MEM_LLM_TIMEOUT_MS": "120000"
}
JSON
      )
      echo "wrote: $SETTINGS;使用前请填写占位符"
      fill_template_placeholders "$SETTINGS"
    else mem_ok=0; fi
  fi
  if [ "$mem_ok" = 1 ]; then
    # 与 pi/opencode-setup.sh 用同一份 dot_file 模板做字段级合并,避免三脚本的 claude-mem 配置漂移
    merge_cfg "$RAW/opencode/claude-mem.settings.json" "$SETTINGS" || true
  fi
  if [ "$mem_ok" = 1 ] && ! mem_ready; then
    echo 'claude-mem runtime 缺失或过旧;官方安装器会更新共享资产、Claude 插件注册并停止 worker。'
    echo '已有 settings.json 将原样恢复;安装后需重新启动 worker。'
    def=Y
    [ ! -d "$MEM_ROOT" ] || def=N
    if ask '运行官方 claude-mem 安装器?' "$def"; then
      install_mem_runtime || { warn 'claude-mem runtime 安装失败'; mem_ok=0; }
    else mem_ok=0; fi
  fi
  if [ "$mem_ok" = 1 ]; then
    if mem_ready; then
      install_plugin 'claude-mem@claude-mem-local' "$MEM_ROOT" || warn 'claude-mem 插件注册失败'
    else warn 'claude-mem 资产不完整,请检查官方安装器输出'; fi
  fi
  ensure_mem_provider "$SETTINGS"
fi

# ---- 3. Ponytail + hooks ----
if command -v node >/dev/null; then
  install_plugin 'ponytail@ponytail' 'DietrichGebert/ponytail' || warn 'Ponytail 安装失败'
else warn '缺少 Node,跳过 Ponytail'; fi
hooks="$(value features hooks)"
if [ "$hooks" = false ] || [ "$(value features codex_hooks)" = false ]; then
  echo '保留: hooks 已显式禁用;claude-mem/Ponytail 自动注入不会运行'
elif [ "$hooks" = null ] && ask '添加 features.hooks=true(仍需在 /hooks 信任具体 hooks)?' Y; then
  backup "$CONFIG"
  codex features enable hooks || warn '启用 hooks 失败'
fi

# ---- 4. CodeGraph:本地已有 MCP 条目一律保留(含自定义路径/禁用状态)----
if [ "$(value mcp_servers codegraph)" != null ]; then
  echo 'unchanged: mcp_servers.codegraph 已存在,保留本地配置'
else
  if ! command -v codegraph >/dev/null && ask '安装 CodeGraph CLI?' Y; then
    download_run https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh || warn 'CodeGraph 安装失败'
  fi
  if command -v codegraph >/dev/null; then
    cg="$(command -v codegraph)"
    if ask "添加 MCP codegraph: $cg serve --mcp?" Y; then
      backup "$CONFIG"
      codex mcp add codegraph -- "$cg" serve --mcp || warn 'CodeGraph MCP 注册失败'
    fi
  else warn '缺少 CodeGraph,跳过 MCP 注册'; fi
fi

# ---- 5. skills:仅安装缺失项,已共享给 OpenCode 的内容不覆盖 ----
missing=()
for s in grilling domain-modeling tdd diagnosing-bugs code-review load-mem save-mem migrate-mem plan-brief steady-do quick-do personal-ui-taste exp-discuss exp-campaign exp-batch exp-probe; do
  if [ ! -f "$HOME/.agents/skills/$s/SKILL.md" ] && [ ! -f "$CFG/skills/$s/SKILL.md" ]; then
    missing+=("$s")
  fi
done
if [ "${#missing[@]}" = 0 ]; then
  echo 'unchanged: skills 已存在,复用原内容'
elif command -v npx >/dev/null; then
  if ask "安装缺失 skills: ${missing[*]}?" Y; then
    npx -y skills@latest add brilliantrough/agent-skills --skill "${missing[@]}" --agent codex -g -y || warn 'skills 安装失败'
  fi
else warn '缺少 npx,跳过 skills'; fi

echo '== 配置步骤结束 =='
echo '1. 在 Codex /hooks 审阅并信任插件 hooks,然后重开会话;更新 hooks 后可能需要重新信任。'
echo '2. 用 /mcp 检查连接,实际调用 claude-mem 查询和 CodeGraph 工具。'
echo "3. claude-mem worker 地址 http://$(mem_worker_url)(端口取自 $SETTINGS,默认 37700)。后端配置: $SETTINGS（本脚本启动时已问过网关地址 + API key 并填入;若当时跳过,手工填 <YOUR_*> 占位符;环境变量预填方式:PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY)。如刚运行安装器,填好配置后执行 npx claude-mem@latest start。"
echo '4. 新项目执行 codegraph init;已有项目索引可复用。'
echo '5. skills 原样复用;缺少 Magic Context 的 ctx_* 工具时仅 best effort,以 OpenCode 为主。'
echo '6. 本脚本不升级已有插件/skills;更新方法见 README 的 Codex 一节。'
if [ "$errors" != 0 ]; then
  echo "WARN: $errors 项未完成,请检查上方输出后重跑" >&2
  exit 1
fi
