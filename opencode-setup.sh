#!/usr/bin/env bash
# opencode-setup.sh — 个人 opencode 一键配置(claude-mem + magic-context + ponytail + notify + skills 本体)
# 仓库: brilliantrough/agent-skills
#
# 用法：bash opencode-setup.sh [-y|--yes] [--plugins-only|--check]；先安装 OpenCode，按主版本拉取对应预构建包。
# 不升级宿主、不迁移数据库、不自动升级共享 Magic Context。
# 配置：本地私密值保留；provider.models 随模板刷新；v2 原生 providers 不改写。
# -y 采用各项默认选择（默认 N 仍跳过）；凭据可交互输入或通过环境变量填写。
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
nbin() { # 可执行文件的宿主路径:MSYS 的 command -v 会去掉 .exe,宿主 spawn 前显式补回
  if [ "$IS_WIN" = 1 ] && [ -f "$1.exe" ]; then npath "$1.exe"; else npath "$1"; fi
}
BIN_EXT=""; [ "$IS_WIN" = 1 ] && BIN_EXT=".exe"   # 手写兜底路径要带 .exe(PATH 查找不用)
resolve_python3() { # python3 就绪返回 0;否则 python → py → uv 自管理 3.12(缺 uv 征得同意后装)。ask 在后面定义,调用时才解析
  # 候选一律先 -c pass 试跑:Windows 商店的 python.exe 占位 stub 能 command -v 到,一跑就报错
  if command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1; then return 0; fi
  if command -v python >/dev/null 2>&1 && python -c pass >/dev/null 2>&1; then python3() { python "$@"; }; return 0; fi
  if command -v py >/dev/null 2>&1 && py -3 -c pass >/dev/null 2>&1; then python3() { py -3 "$@"; }; return 0; fi
  command -v uv >/dev/null 2>&1 || [ -x "$HOME/.local/bin/uv$BIN_EXT" ] || {
    ask "没有可用的 Python 3;用 uv 装一个自管理的 Python 3.12(会先装 uv 本体)?" Y || return 1
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
  UV_PY="$p"; python3() { "$UV_PY" "$@"; }
}

# -y/--yes(或环境变量 ASSUME_YES=1)「默认安装」:不再逐项确认,一律取默认值 —— 默认 Y 的照做
# (装缺件、字段级合并写配置、刷新 skills),默认 N 的跳过(notify 插件、覆盖插件缓存、无代理继续、AGENTS.md 注入)。
# 唯一还会问的是凭据(网关 + 5 个 api key);没有终端时静默跳过、占位符保留(无人值守用环境变量预填)。
ASSUME_YES="${ASSUME_YES:-}"
PLUGINS_ONLY=0; CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --plugins-only) PLUGINS_ONLY=1 ;;
    --check) CHECK_ONLY=1; PLUGINS_ONLY=1 ;;
    -h|--help) echo "用法: bash <本脚本> [-y|--yes] [--plugins-only|--check]  # --plugins-only 仅同步插件；--check 只下载并检查，不写配置"; exit 0 ;;
    *) echo "未知参数: $1(支持 -y|--yes / --plugins-only / --check / -h|--help)" >&2; exit 2 ;;
  esac
  shift
done

# 只读取版本；不安装/升级宿主，也不触发首次运行的数据库迁移。
command -v opencode >/dev/null 2>&1 || { echo "ERROR: 请先安装 OpenCode v1 或 v2，再运行本脚本" >&2; exit 1; }
OC_VERSION="$(opencode --version)"
if [[ "$OC_VERSION" =~ (^|[[:space:]])v?([12])\.[0-9]+\.[0-9]+ ]]; then OC_MAJOR="${BASH_REMATCH[2]}"
else echo "ERROR: 无法识别或暂不支持的 OpenCode 版本: $OC_VERSION" >&2; exit 1; fi
echo "客户端: $OC_VERSION → v$OC_MAJOR 插件包；不升级宿主/不迁移数据库"
OC_RELEASE="opencode-plugins-1.0.5"
CFG="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
PLUGINS="$CFG/plugins"
LIB="$CFG/lib"
BUNDLED="$LIB/claude-mem.js"
MCP_CJS="$HOME/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"
SETTINGS="$HOME/.claude-mem/settings.json"
MC_CFG="$HOME/.config/cortexkit/magic-context.jsonc"

ask() { # $1=提示 $2=默认(Y/N,缺省 N)
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

RAW="https://raw.githubusercontent.com/brilliantrough/dot_file/master"
# 本仓自产的插件源文件(claude-mem wrapper、later server/TUI 插件)从自己仓库下载
SELF_RAW="https://raw.githubusercontent.com/brilliantrough/agent-skills/main"
# merge_cfg <url> <dest> — 拉 dot_file 模板后做「字段级」合并,而非整文件覆盖:
#   模板中的非敏感字段值优先 → 新默认值能下发到服务器;
#   隐私内容永不覆盖:敏感键(api key / secret / token / password / credential / bearer / auth /
#     cookie / ingest / webhook / base_url / url / endpoint / host / 以 key 结尾)保留机器上已有值。
#     回归检查:tests/merge-private-preservation.py
#   模板里含 <占位符> 的值不覆盖本地已填内容;本地独有的键保留。
#   列表键 packages/enabledModels 走并集(本地顺序 + 模板新增);其余键模板优先,数组整体替换。
#   合并结果与本地一致时不写文件(幂等);有改动先存时间戳 .bak。
#   dest 不存在则直接落模板。符号链接跳过(不穿透)。
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
  python3 - "$SETTINGS" <<'PYEOF'
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

# 只在「首次部署」(目标文件缺失或仍是 <YOUR_*> 占位符)时问,重跑不打扰
needs_gateway_fill() {
  local f
  for f in "$CFG/opencode.json" "$SETTINGS" "$MC_CFG"; do
    [ -f "$f" ] || return 0
    grep -q '<YOUR_' "$f" 2>/dev/null && return 0
  done
  return 1
}

collect_gateway_values() {
  needs_gateway_fill || return 0
  [ -z "$GW_BASE" ] && ask_value "统一网关完整地址" GW_BASE 0 "$DEFAULT_GW"
  if [ -z "$GW_BASE" ]; then
    echo "未提供网关地址:模板里的 <YOUR_*> 占位符保留,装完手工填(见文末清单)"
    return 0
  fi
  [ -z "$K_CLAUDE" ]    && ask_value "claude-newapi 的 API key(anthropic 协议 · claude 模型 · 网关 claude code 分组)" K_CLAUDE 1
  [ -z "$K_CODEX" ]     && ask_value "codex-newapi 的 API key(openai responses 协议 · gpt 模型 · 网关 codex 分组)" K_CODEX 1
  [ -z "$K_ANTHROPIC" ] && ask_value "anthropic-newapi 的 API key(anthropic 协议 · 国产模型 · 网关 coding anthropic 分组)" K_ANTHROPIC 1
  [ -z "$K_EMBED" ]     && ask_value "magic-context embedding 的 API key(openai 协议 · 嵌入模型 · 任意分组)" K_EMBED 1
  [ -z "$K_MEM" ]       && ask_value "claude-mem 的 API key(openai chat completions 协议 · 任意模型 · 建议 coding openai 分组)" K_MEM 1
  [ -z "$MCPHUB_HOST" ] && ask_value "mcphub MCP host(如 mcp.example.com)" MCPHUB_HOST
  local m=""
  for kv in "claude:$K_CLAUDE" "codex:$K_CODEX" "anthropic:$K_ANTHROPIC" "embedding:$K_EMBED" "claude-mem:$K_MEM"; do
    [ -n "${kv#*:}" ] || m="$m ${kv%%:*}"
  done
  echo "凭据:网关 $GW_BASE;留空(占位符保留)的 key:${m:-无}"
  return 0
}

# 把已提供的值填进模板(python 负责 JSON 转义);未提供则原样保留占位符。
# <YOUR_GATEWAY_HOST> 填到主机名:pi 的 anthropic-messages provider 要根域(/v1 会 404),
# 而模板里的 <YOUR_GATEWAY_HOST>/v1 正好给 opencode/embedding/claude-mem 这类要 /v1 的。
# 三个 <YOUR_NEWAPI_API_KEY> 在同一份模板里对应不同 key,只能按 provider 块就近替换
# (不能全局 replace);embedding(magic-context 的 "api_key")与 claude-mem 按各自键名替,同样不全局换。
fill_template_placeholders() {
  [ -z "$GW_BASE$K_CLAUDE$K_CODEX$K_ANTHROPIC$K_EMBED$K_MEM$MCPHUB_HOST" ] && return 0
  python3 - "$1" "$GW_BASE" "$K_CLAUDE" "$K_CODEX" "$K_ANTHROPIC" "$K_EMBED" "$K_MEM" "$MCPHUB_HOST" <<'PYEOF'
import json, re, sys
p, base, k_claude, k_codex, k_anth, k_embed, k_mem, mcphub = sys.argv[1:9]
base = base.rstrip('/')
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
slot = '"apiKey": "<YOUR_NEWAPI_API_KEY>"'
names = {'claude-newapi': k_claude, 'codex-newapi': k_codex, 'anthropic-newapi': k_anth}
# 按 provider 名切块(到下一个 provider 名之前):只填该 provider 自己那处 apiKey,
# 已填过的块里没有槽位,不会把隔壁 provider 的 key 抢过来填。
blocks = [(m.start(), m.group(1)) for m in re.finditer(r'"(claude-newapi|codex-newapi|anthropic-newapi)"\s*:', t)]
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
  local url="$1" dest="$2" tmp cand out
  if [ -L "$dest" ]; then
    echo "跳过: $dest 是符号链接(指向 $(readlink "$dest")),不覆盖以免破坏链接目标"
    return 1
  fi
  # 操作员在提示里给了网关/密钥:先把本地文件里的占位符补上(改前存 .bak),再走正常合并
  # (补进去的是敏感键,合并会原样保留)。目标文件不存在时由模板侧的 fill_template_placeholders 负责。
  if [ -f "$dest" ] && [ -n "$GW_BASE$K_CLAUDE$K_CODEX$K_ANTHROPIC$K_EMBED$K_MEM$MCPHUB_HOST" ] && grep -q '<YOUR_' "$dest" 2>/dev/null; then
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
        if k in cur and k.startswith('CLAUDE_MEM_') and (k.endswith('_BASE_URL') or k.endswith('_API_KEY')\
                or k.endswith('_PORT') or k.endswith('_HOST')):
            continue  # 已有接口/凭据保留，包括占位值
        # CLAUDE_MEM_*_MODEL 不保留:模型名跟模板走 —— 默认安装(-y)直接覆盖,交互跑由下面的确认拦截
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
    rm -f "$tmp"; echo "WARN: $f 解析失败,未改 provider;请手工设为 openrouter" >&2
  fi
}

echo "== opencode 一键配置 =="

# ---- 0. 代理环境提醒 ----
# 大小写都查;无代理环境变量时再探测直连(排除路由器层透明代理的情况)
proxy="${http_proxy:-${https_proxy:-${all_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-${ALL_PROXY:-}}}}}}"
net_ok() { curl -fsSI --connect-timeout 5 -m 8 -o /dev/null https://github.com; }
if [ -n "$proxy" ]; then
  echo "代理: $proxy"
elif net_ok 2>/dev/null; then
  echo "未设代理环境变量,但直连 github.com 可达(可能是透明代理),继续"
else
  echo "提醒: 未检测到代理环境变量(大小写的 http(s)_proxy / all_proxy 都查了),且直连 github.com 不通。"
  echo "      建议先 export http_proxy/https_proxy 再继续;有透明代理则可忽略。"
  ask "仍要继续吗？" || exit 1
fi

# ---- 1. 依赖: python3(必需;缺失时用 uv 自管理 3.12 兜底,Git for Windows 不带 python) ----
if [ "$PLUGINS_ONLY" = 1 ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1; then :
  elif command -v python >/dev/null 2>&1 && python -c pass >/dev/null 2>&1; then python3() { python "$@"; }
  elif command -v py >/dev/null 2>&1 && py -3 -c pass >/dev/null 2>&1; then python3() { py -3 "$@"; }
  else echo "ERROR: 插件检查／同步需要现成的 Python 3；请先安装或运行完整 setup" >&2; exit 1; fi
else
resolve_python3 || { echo "ERROR: 没有可用的 Python 3(配置写入依赖它)。可手工装(winget install Python.Python.3.12 / apt install python3)或允许脚本用 uv 装后重跑。" >&2; exit 1; }

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
    archive.extractall(root)
PYEOF
python3 "$oc_stage/deploy.py" "$oc_stage" "$(npath "$CFG")" "$OC_MAJOR" --check

if [ "$CHECK_ONLY" = 1 ]; then exit 0; fi

if [ "$PLUGINS_ONLY" != 1 ]; then
# ---- 1.1 依赖: npx(fnm + Node)----
if ! command -v npx >/dev/null 2>&1 && command -v fnm >/dev/null 2>&1; then
  # Git Bash 不加载 PowerShell 的 fnm 初始化；复用已有 default Node，避免重复安装。
  eval "$(fnm env --shell bash)"
  fnm use default || true
fi
if ! command -v npx >/dev/null 2>&1; then
  echo "未检测到 npx(claude-mem 官方安装器与 skills 安装需要 Node)。"
  if ask "是否安装 fnm + Node LTS？" Y; then
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
    echo "跳过 Node(claude-mem 安装与 skills 安装将不可用)"
  fi
fi

# ---- 1.2 依赖: bun ----
if ! command -v bun >/dev/null 2>&1; then
  echo "未检测到 bun(claude-mem 的 MCP server 依赖 bun:sqlite,node 运行会崩)。"
  if ask "是否安装 bun？" Y; then
    curl -fsSL --connect-timeout 8 -m 60 https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
  else
    echo "跳过 bun(claude-mem MCP 工具将无法运行)"
  fi
fi
# 只写真实存在的绝对路径;都没有时退化为裸命令名(交给运行时 PATH),别把猜测路径写进 MCP 配置
BUN_BIN="$(command -v bun 2>/dev/null || true)"; [ -n "$BUN_BIN" ] || BUN_BIN="$HOME/.bun/bin/bun$BIN_EXT"
[ -x "$BUN_BIN" ] || BUN_BIN=bun

# ---- 2. claude-mem:安装(只为拿 bundle / MCP 资产)+ 修复 ----
if [ ! -f "$BUNDLED" ] && [ ! -f "$PLUGINS/claude-mem.js" ]; then
  if command -v npx >/dev/null 2>&1 && ask "未找到 claude-mem,运行官方安装器 npx claude-mem install --ide opencode?" Y; then
    # 安装阶段仅拿资产；原样恢复已有共享配置，避免 provider 被安装器改成 claude。
    (
      [ ! -L "$SETTINGS" ] || { echo "ERROR: settings 是符号链接，跳过安装" >&2; exit 1; }
      saved="$(mktemp)"; chmod 600 "$saved"
      mem_stage="$(mktemp -d)"
      had_settings=0
      if [ -f "$SETTINGS" ]; then cp -p "$SETTINGS" "$saved" || exit 1; had_settings=1; fi
      restore_mem_settings() {
        if [ "$had_settings" = 1 ]; then
          cp -p "$saved" "$SETTINGS" || { echo "ERROR: 请从 $saved 恢复 $SETTINGS" >&2; exit 1; }
        else
          rm -f "$SETTINGS"
        fi
        rm -f "$saved"; rm -rf "$mem_stage"
      }
      trap restore_mem_settings EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      OPENCODE_CONFIG_DIR="$(npath "$mem_stage")" npx -y claude-mem install --ide opencode --provider claude --no-auto-start < /dev/null
      if [ -f "$mem_stage/plugins/claude-mem.js" ]; then
        mkdir -p "$LIB"; cp "$mem_stage/plugins/claude-mem.js" "$BUNDLED"
      fi
    ) || echo "WARN: claude-mem 安装失败；请检查上方恢复提示" >&2
  fi
fi
ensure_mem_provider "$SETTINGS"

if [ ! -f "$BUNDLED" ] && [ ! -f "$PLUGINS/claude-mem.js" ]; then
  echo "WARN: 没有 claude-mem bundle,跳过 claude-mem 相关配置" >&2
fi

# ---- 3. 部署 settings.json(字段级合并 dot_file 模板;下载失败用内嵌模板兜底)----
# 凭据先问:下面步骤 3(claude-mem settings)、3.1(magic-context)、4(opencode.json)都要用它填占位符
collect_gateway_values
mkdir -p "$HOME/.claude-mem"
mc_rc=0; merge_cfg "$RAW/opencode/claude-mem.settings.json" "$SETTINGS" || mc_rc=$?
if [ "$mc_rc" = 1 ] && [ ! -f "$SETTINGS" ]; then   # 只在模板下载失败时用内嵌兜底
  if ask "写入 $SETTINGS(内嵌兜底模板,含占位符)?" Y; then
  cat > "$SETTINGS" <<'EOF'
{
  "CLAUDE_MEM_RUNTIME": "worker",
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "<YOUR_NEWAPI_BASE_URL>",
  "CLAUDE_MEM_OPENROUTER_MODEL": "<YOUR_MODEL_NAME>",
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "20",
  "CLAUDE_MEM_LLM_TIMEOUT_MS": "120000",
  "CLAUDE_MEM_SKIP_TOOLS": "ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion,todowrite,skill,question,ask_user_question,list,ls,LS,list_mcp_resources,list_mcp_resource_templates,read,Read,bash,Bash,BashOutput,grep,Grep,glob,Glob,find,Find,ctx_*,mcphub-web_*,codegraph_*,claude-mem_*,claude_mem_*,mcp,mcp__*",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>"
}
EOF
  echo "wrote: $SETTINGS(含占位符)"
  else
    echo "跳过: $SETTINGS 未创建"
  fi
fi
ensure_mem_worker_keys "$SETTINGS" 2>/dev/null || true
echo "claude-mem worker: http://$(mem_worker_url)(健康检查: curl -s http://$(mem_worker_url)/api/health)"

# ---- 3.1 magic-context 配置文件(字段级合并 dot_file 模板;historian.model 必填,否则插件报错)----
mcc_rc=0; merge_cfg "$RAW/opencode/magic-context.jsonc" "$MC_CFG" || mcc_rc=$?
if [ "$mcc_rc" = 1 ] && [ ! -f "$MC_CFG" ]; then   # 只在模板下载失败时用内嵌兜底
  if ask "写入 $MC_CFG(内嵌兜底模板,含占位符)?" Y; then
  mkdir -p "$HOME/.config/cortexkit"
  cat > "$MC_CFG" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/cortexkit/magic-context/master/assets/magic-context.schema.json",
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
  else
    echo "跳过: $MC_CFG 未创建"
  fi
fi

# ---- 4. opencode.json(来自 dot_file 仓库:providers/agents/mcp/插件条目/compaction)----
# 已存在则只覆盖各 provider 的 models(新模型自动下发),options(apiKey/网关)等本地字段保留;
# 老 opencode.jsonc 的值自动并入 opencode.json 后退役为 .migrated.bak
oc_tpl="$(mktemp)"; oc_cand="$(mktemp)"
# 上次跳过的 key 这次补上:先填本地文件里的占位符(改前存 .bak),再走正常合并(live 优先)
if [ -f "$CFG/opencode.json" ] && [ -n "$GW_BASE$K_CLAUDE$K_CODEX$K_ANTHROPIC$K_EMBED$K_MEM$MCPHUB_HOST" ] \
   && grep -q '<YOUR_' "$CFG/opencode.json" 2>/dev/null; then
  cp -p "$CFG/opencode.json" "$CFG/opencode.json.bak-$(date +%Y%m%d%H%M%S)"
  fill_template_placeholders "$CFG/opencode.json"
  echo "filled placeholders: $CFG/opencode.json"
fi
if curl -fsSL --connect-timeout 8 -m 30 -o "$oc_tpl" "$RAW/opencode/opencode.json"; then
  fill_template_placeholders "$oc_tpl"
  oc_out="$(python3 - "$CFG/opencode.json" "$CFG/opencode.jsonc" "$oc_tpl" "$oc_cand" <<'PYEOF'
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
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))

def load(p):
    try:
        return json.loads(strip_jsonc(open(p, encoding='utf-8').read()))
    except FileNotFoundError:
        return {}
    except (json.JSONDecodeError, UnicodeError) as error:
        raise SystemExit(f'ERROR: {p} 解析失败，保留原文件：{error}')

def deep_merge(base, over):  # over 优先(本地值优先),dict 递归
    if isinstance(base, dict) and isinstance(over, dict):
        out = dict(base)
        for k, v in over.items():
            if k in ('plugin', 'plugins') and isinstance(base.get(k), list) and isinstance(v, list):
                out[k] = base[k] + [entry for entry in v if entry not in base[k]]
            else:
                out[k] = deep_merge(base.get(k), v) if k in base else v
        return out
    return over

tpl = json.load(open(tpl_p, encoding='utf-8'))

live_json, live_jsonc = load(target_p), load(jsonc_p)
live = deep_merge(live_json, live_jsonc)
# v2 原生字段已有本地配置时不再注入对应旧字段；模型模板只更新 v1 provider 形状。
tpl.pop('plugin', None)
for old, native in [('provider', 'providers'), ('permission', 'permissions'), ('agent', 'agents'),
                    ('autoupdate', 'update'), ('snapshot', 'snapshots')]:
    if native in live:
        tpl.pop(old, None)
if 'providers' in live:
    print('INFO: 保留本机 v2 providers；通用 provider 模型模板不改写原生结构', file=sys.stderr)
if isinstance(live.get('mcp'), dict) and 'servers' in live['mcp']:
    tpl['mcp'] = {'servers': {k: {**{a:b for a,b in v.items() if a != 'enabled'}, 'disabled': not v.get('enabled', True)} for k,v in tpl.get('mcp', {}).items()}}

merged = deep_merge(tpl, live)
tpl_prov = tpl.get('provider') or {}
live_prov = live.get('provider') or {}
mp = merged.setdefault('provider', {}) if tpl_prov else {}
for name, p in tpl_prov.items():
    if name in live_prov:
        # 已存在的 provider:本地节点原样保留(options/apiKey 一个字节都不动),只换 models
        mp[name] = {**live_prov[name], 'models': p.get('models', {})}
    elif name not in mp:
        mp[name] = p  # 模板新增的 provider:整块加入(含占位符 options,待首次填写)

out = json.dumps(merged, indent=2, ensure_ascii=False) + '\n'
same = load(target_p) == merged   # 按 JSON 语义比较:只有格式化/键序不同不算变更(避免每轮重写)
msgs = []
if not same:
    with open(sys.argv[4], 'w', encoding='utf-8') as f:
        f.write(out)
    msgs.append(('%d 个 provider 的 models 按模板覆盖,本地字段保留' % len(tpl_prov)) if live else '首次写入(含占位符)')
if os.path.exists(jsonc_p):
    msgs.append('退役 opencode.jsonc(值已并入)')
print(';'.join(msgs) if msgs else 'unchanged')
PYEOF
)"
  case "$oc_out" in
    unchanged) echo "unchanged: $CFG/opencode.json" ;;
    "")        echo "WARN: opencode.json 合并失败,现有配置未改动" >&2 ;;
    *)         if ask "更新 $CFG/opencode.json($oc_out)?" Y; then
                 if [ -s "$oc_cand" ]; then
                   if [ -f "$CFG/opencode.json" ]; then
                     cp -p "$CFG/opencode.json" "$CFG/opencode.json.bak-$(date +%Y%m%d%H%M%S)"
                   fi
                   mv "$oc_cand" "$CFG/opencode.json"
                 fi
                 echo "updated: $CFG/opencode.json"
                 if [ -f "$CFG/opencode.jsonc" ]; then
                   mv "$CFG/opencode.jsonc" "$CFG/opencode.jsonc.migrated-$(date +%Y%m%d%H%M%S).bak"
                   echo "retired: opencode.jsonc(值已并入 opencode.json)"
                 fi
               else
                 echo "保留原文件: $CFG/opencode.json"
               fi ;;
  esac
else
  echo "跳过: opencode.json 模板下载失败(检查代理),现有配置未改动"
fi
rm -f "$oc_tpl" "$oc_cand"

# ---- 4.1 MCP 查询工具 → opencode.json ----
if [ -f "$BUNDLED" ] && [ -f "$MCP_CJS" ]; then
  configured=0
  for name in opencode.jsonc opencode.json; do
    f="$CFG/$name"
    if [ -f "$f" ] && grep -qs 'mcp-server.cjs' "$f"; then configured=1; break; fi
  done
  if [ "$configured" -eq 0 ] && ask "在 $CFG/opencode.json 添加 claude-mem MCP 条目?" Y; then
    python3 - "$CFG/opencode.json" "$(nbin "$BUN_BIN")" "$(npath "$MCP_CJS")" <<'PYEOF'
import json, sys
path, bun, cjs = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {"$schema": "https://opencode.ai/config.json"}
except FileNotFoundError:
    cfg = {"$schema": "https://opencode.ai/config.json"}
cfg.setdefault("mcp", {})
servers = cfg["mcp"].get("servers", cfg["mcp"])
if "claude-mem" in servers:
    sys.exit(0)
servers["claude-mem"] = {"type": "local", "command": [bun, cjs], **({"disabled": False} if "servers" in cfg["mcp"] else {"enabled": True})}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"added: mcp.claude-mem -> {path}")
PYEOF
  fi
elif [ -f "$BUNDLED" ]; then
  echo "WARN: 未找到 claude-mem 的 mcp-server.cjs,跳过 MCP 配置" >&2
fi

# ---- 4.2 codegraph MCP(预索引代码知识图谱;CLI 提供 graph,MCP 只是入口)----
if ! command -v codegraph >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/codegraph" ] && [ ! -x "$HOME/.local/bin/codegraph.exe" ]; then
  echo "未检测到 codegraph(代码知识图谱,MCP 需要 CLI 提供 graph)。"
  if [ "$IS_WIN" = 1 ]; then
    # codegraph 官方 install.sh 明确不支持 Windows(只认 Darwin/Linux),README 给的 Windows 路径是 npm
    if ! command -v npm >/dev/null 2>&1; then
      echo "跳过 codegraph:未检测到 npm"
    elif ask "是否安装 codegraph CLI(npm i -g @colbymchenry/codegraph@latest)?" Y; then
      npm install -g @colbymchenry/codegraph@latest || echo "WARN: codegraph 安装失败,请看上方输出" >&2
    fi
  elif ask "是否安装 codegraph CLI(curl 官方 install.sh)?" Y; then
    cg_sh="$(mktemp)"
    if curl -fsSL --connect-timeout 8 -m 60 -o "$cg_sh" https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh; then
      sh "$cg_sh" || echo "WARN: codegraph 安装脚本退出码非 0,请看上方输出" >&2
    else
      echo "WARN: codegraph 安装脚本下载失败(检查代理)" >&2
    fi
    rm -f "$cg_sh"
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi
CG_BIN="$(command -v codegraph 2>/dev/null || true)"; [ -n "$CG_BIN" ] || CG_BIN="$HOME/.local/bin/codegraph$BIN_EXT"
[ -x "$CG_BIN" ] || CG_BIN=codegraph
if [ -x "$CG_BIN" ]; then
  if ! grep -qs '"codegraph"' "$CFG/opencode.json" "$CFG/opencode.jsonc" 2>/dev/null && \
     ask "在 $CFG/opencode.json 添加 codegraph MCP 条目?" Y; then
    CG_NODE=""; CG_JS=""
    if [ "$IS_WIN" = 1 ] && command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
      _cg_js="$(npm root -g 2>/dev/null)/@colbymchenry/codegraph/npm-shim.js"
      if [ -f "$_cg_js" ]; then
        CG_NODE="$(nbin "$(realpath "$(command -v node)")")"
        CG_JS="$(npath "$(realpath "$_cg_js")")"
      fi
    fi
    python3 - "$CFG/opencode.json" "$(nbin "$CG_BIN")" "$CG_NODE" "$CG_JS" <<'PYEOF'
import json, sys
path, bin_, node, shim = sys.argv[1:5]
try:
    with open(path) as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {"$schema": "https://opencode.ai/config.json"}
except FileNotFoundError:
    cfg = {"$schema": "https://opencode.ai/config.json"}
cfg.setdefault("mcp", {})
servers = cfg["mcp"].get("servers", cfg["mcp"])
if "codegraph" in servers:
    sys.exit(0)
cmd = [node, shim] if node and shim else [bin_]
servers["codegraph"] = {"type": "local", "command": cmd + ["serve", "--mcp"], **({"disabled": False} if "servers" in cfg["mcp"] else {"enabled": True})}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"added: mcp.codegraph -> {path}")
PYEOF
  fi
fi

fi # 完整安装的环境／配置步骤

# ---- 5. context-mode 独立产物：v1 自动入口；v2 由版本适配包加载 ----
# skills 装到 $CFG/skill/<name>/。
CM_ASSET="opencode-context-mode-vendor.tar.gz"
CM_URL="https://github.com/brilliantrough/agent-skills/releases/latest/download/$CM_ASSET"
CM_DIR="$PLUGINS/context-mode"
[ "$OC_MAJOR" = 2 ] && CM_DIR="$CFG/vendor/context-mode"
CM_ENTRY="$PLUGINS/context-mode.js"
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
      mkdir -p "$(dirname "$cm_backup")"; mv "$CM_DIR" "$cm_backup"
      echo "backup: $CM_DIR -> $cm_backup"
    fi
    mkdir -p "$(dirname "$CM_DIR")"; mv "$cm_tmp/pkg" "$CM_DIR"; echo "deployed: $CM_DIR($cm_ver)"
  fi
  if [ "$OC_MAJOR" = 1 ] && ! cmp -s "$CM_DIR/entry.js" "$CM_ENTRY"; then
    [ ! -f "$CM_ENTRY" ] || cp -p "$CM_ENTRY" "$CM_ENTRY.bak-$(date +%Y%m%d%H%M%S)"
    cp -f "$CM_DIR/entry.js" "$CM_ENTRY"
  fi
  cm_n=0
  for d in "$CM_DIR"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    n="$(basename "$d")"; dest="$CFG/skill/$n"
    if [ -d "$dest" ] && diff -rq "$d" "$dest" >/dev/null 2>&1; then continue; fi
    mkdir -p "$CFG/skill"; rm -rf "$dest"; cp -r "$d" "$dest"
    echo "deployed: skill/$n"; cm_n=$((cm_n+1))
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
python3 "$oc_stage/deploy.py" "$oc_stage" "$(npath "$CFG")" "$OC_MAJOR"
echo "Ponytail 已登记官方包；缺失包由下次启动 OpenCode 下载，setup 不清缓存、不启动宿主。"
if [ "$PLUGINS_ONLY" = 1 ]; then
  echo "插件同步完成；重启 OpenCode 生效。宿主／数据库／共享 Magic Context 未升级。"
  exit 0
fi

# ---- 5.1 compaction 关闭(manual setup 要求:magic-context 接管压缩;完整 jsonc 已含则跳过)----
if ! grep -qs '"compaction"' "$CFG/opencode.jsonc" "$CFG/opencode.json" 2>/dev/null && \
   ask "在 $CFG/opencode.json 写入 compaction auto=false(让 magic-context 接管压缩)?" Y; then
python3 - "$CFG/opencode.json" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        text = f.read()
    if text.strip():
        cfg = json.loads(text)
if "compaction" not in cfg:
    cfg["compaction"] = {"auto": False, "prune": False}
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"added: compaction auto=false prune=false -> {path}")
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
    return json.loads(re.sub(r',(\s*[}\]])', r'\1', ''.join(out)))
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
if [ "$kb_rc" -eq 3 ]; then
  printf '%s\n' "$kb_out"
  if ask "统一为 Enter 发送、Shift+Enter 换行,取消旧 Ctrl+Enter/Ctrl+J 发送绑定(仅更新 $TUI_CFG 的三个相关按键)?" Y; then
    tui_keys_py apply
  else
    echo "保留原按键: $TUI_CFG"
  fi
else
  printf '%s\n' "$kb_out"
fi

# 含密钥的配置统一 600(与 pi/codex 两侧一致;含本机路径的脚本文件不下调)
chmod 600 "$SETTINGS" "$MC_CFG" "$CFG/opencode.json" 2>/dev/null || true

# ---- 6. notify 插件(brilliantrough/opencode-notify-hub,GitHub Release 预构建包)----
# 每次拉最新 release 的 zip,与已装文件比对:一致就不动,不同才备份 .bak-时间戳 再替换。
NOTIFY_TARGET="$PLUGINS/session-notify.js"
if [ "$OC_MAJOR" = 1 ] && command -v curl >/dev/null 2>&1; then
  if [ -f "$NOTIFY_TARGET" ] || ask "未找到 notify 插件,从 GitHub Release 下载最新 opencode-notify-plugin?" N; then
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
      mv "$_new" "$NOTIFY_TARGET"; echo "$_action: plugins/session-notify.js($notify_ver)"
    fi
  fi
fi

# ---- 7. skills 本体 ----
# 分组 = 仓库 skills/{base,accel,kb}/ 目录,策略由 skills-sync.sh 执行:base/kb 每次随仓库刷新
# (base 本地有未回流改动先备份到 ~/.local/share/agent-skills/.backups);accel 缺才装(本机特化不覆盖)。
# 客户端实体直落 ~/.agents/skills/<名>(装了 Claude Code 时同步 ~/.claude/skills/<名>)。
# 同步器随后用 npx skills 补装外部设计依赖、更新已登记第三方。
_ss="$(mktemp --suffix=.sh 2>/dev/null || mktemp)"
if curl -fsSL --connect-timeout 8 -m 60 -o "$_ss" "$SELF_RAW/skills-sync.sh"; then
  if ask "安装/更新 skills(base+accel+kb 三组;base 每次刷新·漂移自动备份,accel 缺才装;选 N 只装 base 组,个人工作站选这个)" N; then
    bash "$_ss" all || echo "WARN: skills 同步未完全成功" >&2
  else
    bash "$_ss" base || echo "WARN: skills 同步未完全成功" >&2
  fi
else
  echo "WARN: skills-sync.sh 下载失败,跳过(检查代理)" >&2
fi
rm -f "$_ss"

# ---- 8. uv(可选)+ strictdoc(.sdoc 校验依赖)----
UVP="$HOME/.local/bin/uv$BIN_EXT"
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$UVP" ]; then
  if ask "未检测到 uv,安装 uv(astral.sh 官方脚本,装到 ~/.local/bin)?" Y; then
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
  uv_cur="$("$UV_BIN" --version 2>/dev/null | awk '{print $2}' || true)"
  uv_latest="$(curl -fsSL --connect-timeout 5 -m 8 https://api.github.com/repos/astral-sh/uv/releases/latest 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
  if [ -z "$uv_latest" ]; then
    echo "跳过 uv 自升级:查不到最新版本(检查网络/代理)"
  elif [ "$uv_latest" != "$uv_cur" ]; then
    if [ "$IS_WIN" = 1 ] && [[ "$UV_BIN" == */Python*/Scripts/uv* ]]; then
      echo "uv 由 Python 环境安装(${uv_cur:-未知}),请用原安装方式升级;跳过 uv self update"
    elif ask "uv ${uv_cur:-未知} → $uv_latest,升级(uv self update)?" Y; then
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
  elif ask "配置 uv 用清华 PyPI 镜像($UVCFG)?" Y; then
    mkdir -p "$(dirname "$UVCFG")"
    printf '%s\n' 'index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"' > "$UVCFG"
    echo "wrote: $UVCFG"
  fi
  if command -v strictdoc >/dev/null 2>&1; then
    echo "strictdoc 已存在,跳过(升级: uv tool upgrade strictdoc)"
  elif ask "用 uv 全局安装 strictdoc==0.28.1(.sdoc 校验依赖)?" Y; then
    "$UV_BIN" tool install strictdoc==0.28.1 || echo "WARN: strictdoc 安装失败(可稍后重试)" >&2
  fi
else
  echo "提示: 未检测到 uv,跳过 strictdoc 安装(.sdoc 校验依赖);装好 uv 后重跑本脚本即可"
fi

# ---- 完成:占位符清单 + 收尾动作 ----
echo ""
echo "== done. 需要你手工完成的 =="
n=1
echo "$n. 网关/凭据:脚本启动时已问过「统一网关 + 5 个 api key」并填进各配置(可用环境变量预填、非交互跑:PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY / MCPHUB_HOST)"; n=$((n+1))
echo "   当时跳过了才会剩下占位符(<YOUR_*>):"
_ph=0
for _f in "$SETTINGS" "$MC_CFG" "$CFG/opencode.json"; do
  if [ -f "$_f" ] && grep -q '<YOUR_' "$_f" 2>/dev/null; then
    echo "   - $_f:$(grep -o '<YOUR_[A-Z_]*>' "$_f" | sort -u | tr '\n' ' ')"; _ph=1
  fi
done
[ "$_ph" = 0 ] && echo "   (无,凭据已齐)"
echo "   提示:claude-mem 走 openrouter(OpenAI 协议),它的 key 与 magic-context embedding 的各自独立"
echo "$n. 重启 claude-mem worker 并验证:"; n=$((n+1))
echo "      cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart"
echo "      curl -s http://$(mem_worker_url)/api/health   # 端口取自 $SETTINGS(见下方提示)"
# ---- 项目接入记忆系统(可选,默认不写):把 memory-system 块写到当前目录的 AGENTS.md 最尾部 ----
PROJ_AGENTS="$PWD/AGENTS.md"
AGENTS_SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/AGENTS.tail.md"
AGENTS_URL="https://raw.githubusercontent.com/brilliantrough/agent-skills/main/AGENTS.tail.md"
if ask "把记忆系统规范块写进 $PROJ_AGENTS 的最尾部(项目自身内容在前)?" N; then
  _tmp="$(mktemp)"; _ok=0
  # 本地 AGENTS.tail.md 只有在确实含规范块、且不是目标文件本身时才算源;否则一律下载
  if [ -f "$AGENTS_SRC" ] && [ "$AGENTS_SRC" != "$PROJ_AGENTS" ] && grep -q '<!-- memory-system:start -->' "$AGENTS_SRC"; then
    cp "$AGENTS_SRC" "$_tmp" && _ok=1
  elif curl -fsSL --connect-timeout 8 -m 60 -o "$_tmp" "$AGENTS_URL" 2>/dev/null \
    && grep -q '<!-- memory-system:start -->' "$_tmp"; then _ok=1
  fi
  if [ "$_ok" = 1 ]; then
    python3 - "$_tmp" "$PROJ_AGENTS" <<'PYEOF'
import re, sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf8")
m = re.search(r"<!-- memory-system:start -->.*?<!-- memory-system:end -->", src, re.S)
if not m:
    sys.exit("取到的源文件里找不到 memory-system 块")
block = m.group(0)
p = pathlib.Path(sys.argv[2])
old = p.read_text(encoding="utf8") if p.exists() else ""
cur = re.search(r"<!-- memory-system:start -->.*?<!-- memory-system:end -->", old, re.S)
if cur and cur.group(0) == block:
    print("已是最新: " + str(p)); raise SystemExit(0)
new = (old[:cur.start()] + block + old[cur.end():]) if cur else (old.rstrip("\n") + "\n\n" + block + "\n" if old else block + "\n")
pathlib.Path(sys.argv[2]).write_text(new, encoding="utf8")
print(("已更新: " if cur else "已追加: ") + str(p))
PYEOF
  else
    echo "WARN: 取不到规范块(不在仓库目录且下载失败),跳过" >&2
  fi
  rm -f "$_tmp"
fi
echo "$n. 项目接入记忆系统(可选):上一步若跳过,可手动把本仓库 AGENTS.tail.md 的 memory-system 块粘到项目 AGENTS.md 的最尾部"; n=$((n+1))
if [ -x "$CG_BIN" ]; then
  echo "$n. 代码知识图谱(按项目):cd <项目> && codegraph init(建 .codegraph/ 索引,之后自动增量同步;不 init 则 MCP 无内容可查)"; n=$((n+1))
fi
if [ -f "$NOTIFY_TARGET" ]; then
  echo "$n. notify 插件环境变量 —— 在启动 opencode 的 shell 配置(~/.zshrc 或 ~/.bashrc)里 export:"; n=$((n+1))
  echo "      NOTIFY_GATEWAY_URL=<你的网关地址>    NOTIFY_INGEST_KEY=<你的 ingest key>"
  echo "      可选: NOTIFY_MACHINE=<机器名>(多机区分)"
fi
echo "$n. 重启 opencode 生效"
