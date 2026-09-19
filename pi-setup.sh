#!/usr/bin/env bash
# pi-setup.sh — 个人 Pi(pi coding agent)一键配置(mcp-adapter + magic-context + ponytail + subagent + claude-mem 桥 + skills 本体)
# 仓库: brilliantrough/agent-skills
#
# 干什么(交互确认 + 幂等,重复跑安全):
#   询问默认:装缺的软件/包、写入条目 → [Y/n](回车即装);覆盖已有配置、无代理下继续 → [y/N];
#            非交互环境按各自默认执行
#   0. 代理环境提醒(大小写都查;未设则探测直连,透明代理不拦;都不通才要求确认)
#   1. 依赖检查(全部前置):curl/git/python3(缺失即退出)、npx(缺 → 征得同意装 fnm + Node LTS)、
#      bun(缺 → 征得同意装,claude-mem MCP server 依赖 bun:sqlite)、uv(可选,.sdoc 校验用)
#   2. pi 本体:未装 → 官方 install.sh(下载到文件再执行);已装 → 征得同意 pi update --all
#   3. pi 包(pi install,幂等):pi-mcp-adapter / @dietrichgebert/ponytail / pi-subagents-j0k3r /
#      pi-lens / @juicesharp/rpiv-ask-user-question / pi-autoname@0.6.8 / @cortexkit/pi-magic-context /
#      git:github.com/brilliantrough/agent-skills(本仓库自身;含个性化 UI、later、任务耗时扩展、
#      claude-mem 桥扩展、one-dark 主题——旧版散装部署文件会自动清理);
#      启用 magic-context 前检查与 opencode 共享 context.db 的
#      版本守卫(opencode 插件缓存版本 < Pi 扩展版本时先提示,不清理就不启用)
#   4. 部署(字段级合并 dot_file 模板,api key/网关等本地敏感值保留;settings/auth/claude-mem/magic-context 下载失败用内嵌兜底,models.json/mcp.json 必须联网或手工维护):
#      ~/.pi/agent/settings.json(含按模型 thinking、4/8/16 秒重试)、pi-autoname.json(低频命名)、
#      ~/.pi/agent/models.json、~/.pi/agent/auth.json(占位符初始化,
#      coding plan 等内置 provider 凭据)、~/.agents/mcp.json(三平台共享)
#      以及共用配置 ~/.claude-mem/settings.json、~/.config/cortexkit/magic-context.jsonc(含 historian.pi/dreamer.pi)
#   5. claude-mem 资产(缺失则官方安装器,只为拿 worker/MCP 资产)——先装 runtime,再合并它的配置,
#      这样安装器写的 settings 会被我们的模板覆盖(api key/网关等本地敏感值保留)
#   6. subagent 定义 ~/.pi/agent/agents/{explore,general}.md(对应 opencode 的两个 agent)
#   7. skills 本体:npx skills update -g / add(pi 原生读 ~/.agents/skills)
#   8. uv(缺则装;含自升级与清华 PyPI 镜像)+ strictdoc(用 uv tool 全局安装,.sdoc 校验依赖)
#
# 用法:bash pi-setup.sh   (遵循 PI_CODING_AGENT_DIR,与 pi 一致)

set -euo pipefail

AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
MODELS="$AGENT_DIR/models.json"
SETTINGS="$AGENT_DIR/settings.json"
SHARED_MCP="$HOME/.agents/mcp.json"
MC_SETTINGS="$HOME/.claude-mem/settings.json"
# 本仓库自己作为 Pi 包时的 git checkout(pi install git:... 的落地位置)
REPO_PI_PKG="$AGENT_DIR/git/github.com/brilliantrough/agent-skills"
MC_CFG="$HOME/.config/cortexkit/magic-context.jsonc"
AUTH="$AGENT_DIR/auth.json"
MCP_CJS="$HOME/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"
OC_MC_CACHE="$HOME/.cache/opencode/packages/@cortexkit/opencode-magic-context@latest"

ask() { # $1=提示 $2=默认(Y/N,缺省 N)
  local a="" def="${2:-N}" hint="y/N"
  [ "$def" = Y ] && hint="Y/n"
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
  python3 - "$MC_SETTINGS" <<'PYEOF'
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
# 环境变量优先(便于无人值守):PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY / MCPHUB_HOST
GW_BASE="${PI_GATEWAY_BASE_URL:-}"; GW_KEY="${PI_GATEWAY_API_KEY:-}"; MCPHUB_HOST="${MCPHUB_HOST:-}"

ask_value() { # $1=提示 $2=输出变量 $3=非空则不回显(用于 key)
  local a=""
  if { exec 9</dev/tty; } 2>/dev/null; then
    if [ -n "${3:-}" ]; then read -r -s -u 9 -p "$1: " a || a=""; echo
    else read -r -u 9 -p "$1: " a || a=""; fi
    exec 9<&-
    printf -v "$2" '%s' "$a"
  fi
}

# 只在「首次部署」(目标文件缺失或仍是 <YOUR_*> 占位符)时问,重跑不打扰
needs_gateway_fill() {
  local f
  for f in "$MODELS" "$SETTINGS" "$MC_SETTINGS" "$SHARED_MCP"; do
    [ -f "$f" ] || return 0
    grep -q '<YOUR_' "$f" 2>/dev/null && return 0
  done
  return 1
}

collect_gateway_values() {
  [ -n "$GW_BASE" ] && [ -n "$GW_KEY" ] && return 0
  needs_gateway_fill || return 0
  [ -z "$GW_BASE" ] && ask_value "OpenAI 兼容网关完整地址(如 https://gw.example.com/v1;回车跳过)" GW_BASE
  if [ -z "$GW_BASE" ]; then
    echo "未提供网关地址:模板里的 <YOUR_*> 占位符保留,装完手工填(见文末清单)"
    return 0
  fi
  [ -z "$GW_KEY" ] && ask_value "该网关 API key(回车跳过)" GW_KEY 1
  [ -z "$MCPHUB_HOST" ] && ask_value "mcphub MCP host(如 mcp.example.com;回车跳过)" MCPHUB_HOST
  return 0
}

# 把已提供的值填进模板(python 负责 JSON 转义);未提供则原样保留占位符。
# <YOUR_GATEWAY_HOST> 填到主机名:pi 的 anthropic-messages provider 要根域(/v1 会 404),
# 而模板里的 <YOUR_GATEWAY_HOST>/v1 正好给 opencode/embedding/claude-mem 这类要 /v1 的。
fill_template_placeholders() {
  [ -z "$GW_BASE$GW_KEY$MCPHUB_HOST" ] && return 0
  python3 - "$1" "$GW_BASE" "$GW_KEY" "$MCPHUB_HOST" <<'PYEOF'
import json, re, sys
p, base, key, mcphub = sys.argv[1], sys.argv[2].rstrip('/'), sys.argv[3], sys.argv[4]
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
if mcphub:
    t = t.replace('<YOUR_MCPHUB_HOST>', esc(mcphub))
open(p, 'w', encoding='utf-8').write(t)
PYEOF
  return 0
}

RAW="https://raw.githubusercontent.com/brilliantrough/dot_file/master"
# merge_cfg <url> <dest> [mcp] — 拉 dot_file 模板后做「字段级」合并,而非整文件覆盖:
#   模板中的非敏感字段值优先 → 新默认值能下发到服务器;
#   隐私内容永不覆盖:敏感键(api key / secret / token / password / credential / bearer / auth /
#     cookie / ingest / webhook / base_url / url / endpoint / host / 以 key 结尾)保留机器上已有值。
#     回归检查:tests/merge-private-preservation.py
#   模板里含 <占位符> 的值不覆盖本地已填内容;本地独有的键保留。
#   列表键 packages/enabledModels 走并集(本地顺序 + 模板新增);其余键模板优先,数组整体替换。
#   合并结果与本地一致时不写文件(幂等);有改动先存时间戳 .bak。
#   mcp 模式额外替换 <HOME>/<BUN_BIN>/<CODEGRAPH_BIN>/<MCP_CJS> 为本机路径。
#   dest 不存在则直接落模板。符号链接跳过(不穿透)。
merge_cfg() {
  local url="$1" dest="$2" mode="${3:-}" tmp cand out
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
  if [ "$mode" = mcp ]; then
    python3 - "$tmp" "$HOME" "$BUN_BIN" "$CG_BIN" "$MCP_CJS" <<'PYEOF'
import sys
p, home, bun, cg, cjs = sys.argv[1:6]
t = open(p, encoding='utf-8').read()
t = (t.replace('<HOME>', home).replace('<BUN_BIN>', bun)
      .replace('<CODEGRAPH_BIN>', cg).replace('<MCP_CJS>', cjs))
open(p, 'w', encoding='utf-8').write(t)
PYEOF
  fi
  if [ ! -f "$dest" ]; then
    if ask "写入 $dest(来自 dot_file 模板)$([ "$mode" = mcp ] && echo ',含本机路径')?" Y; then
      mkdir -p "$(dirname "$dest")"; cp "$tmp" "$dest"; echo "wrote: $dest"
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

# 旧 UI 包(已被本仓库 UI 取代)留在 packages 里会双份加载,直接摘掉。
prune_legacy_ui_packages() {
  python3 - "$SETTINGS" <<'PY'
import json,sys,shutil,time
p=sys.argv[1]
legacy=("pi-zentui","pi-atelier","atelier-bridge")
try: d=json.load(open(p,encoding='utf-8'))
except Exception as e:
    print(f"WARN: 读取 {p} 失败({e}),跳过旧 UI 包清理",file=sys.stderr); sys.exit(0)
pkgs=d.get("packages") or []
kept=[x for x in pkgs if not any(s in x for s in legacy)]
if kept==pkgs: sys.exit(0)
shutil.copy2(p,f"{p}.bak-ui-prune-{time.strftime('%Y%m%d%H%M%S')}")
d["packages"]=kept
json.dump(d,open(p,'w',encoding='utf-8'),indent=2,ensure_ascii=False); open(p,'a').write("\n")
print("removed legacy UI packages: "+", ".join(sorted(set(pkgs)-set(kept))))
PY
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

# deploy_file <url> <dest> <label> — 整文件部署(用于 agents/*.md、extensions/*.ts):
#   内容一致则不写;有差异存 .bak 后覆盖
deploy_file() {
  local url="$1" dest="$2" label="$3" tmp
  if [ -L "$dest" ]; then
    echo "跳过: $dest 是符号链接,不覆盖"; return 0
  fi
  tmp="$(mktemp)"
  if ! curl -fsSL --connect-timeout 8 -m 30 -o "$tmp" "$url"; then
    rm -f "$tmp"; echo "WARN: $label 下载失败,保留现有 $dest" >&2; return 1
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    echo "unchanged: $dest"; rm -f "$tmp"; return 0
  fi
  local bak=""
  [ -f "$dest" ] && bak="$dest.bak-$(date +%Y%m%d%H%M%S)"
  if ask "写入 $dest($label)?" Y; then
    [ -n "$bak" ] && cp "$dest" "$bak"
    mv "$tmp" "$dest"; echo "wrote: $dest"
  else
    rm -f "$tmp"; echo "保留原文件: $dest"
  fi
}

echo "== Pi 一键配置 =="

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

# ---- 1. 依赖(必需): curl / git / python3 ----
for tool in curl git python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: 未检测到 $tool(下载模板/装依赖/写配置都要用它)。请先安装(如 apt install $tool)后重跑。" >&2
    exit 1
  }
done

# ---- 1.1 依赖: npx(fnm + Node)----
if ! command -v npx >/dev/null 2>&1; then
  echo "未检测到 npx(claude-mem 官方安装器、npm 包安装与 skills 安装需要 Node)。"
  if ask "是否安装 fnm + Node LTS？" Y; then
    curl -fsSL --connect-timeout 8 -m 60 https://fnm.vercel.app/install | bash
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env)"
    fnm install --lts
    fnm default lts-latest
    eval "$(fnm env)"
    command -v npx >/dev/null 2>&1 || { echo "ERROR: 安装后 npx 仍不可用,请重开终端后重跑本脚本" >&2; exit 1; }
    echo "Node $(node --version) 就绪"
  else
    echo "跳过 Node(claude-mem 安装、pi 包与 skills 安装将不可用)"
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
BUN_BIN="$(command -v bun 2>/dev/null || true)"; [ -n "$BUN_BIN" ] || BUN_BIN="$HOME/.bun/bin/bun"
[ -x "$BUN_BIN" ] || BUN_BIN=bun

# ---- 1.3 依赖: uv(可选;strictdoc / .sdoc 校验用)----
UVP="$HOME/.local/bin/uv"
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
    if ask "uv ${uv_cur:-未知} → $uv_latest,升级(uv self update)?" Y; then
      "$UV_BIN" self update || echo "WARN: uv 自升级失败(系统包管理器装的请用系统方式升级)" >&2
    fi
  else
    echo "uv 已是最新(${uv_cur:-未知})"
  fi
  UVCFG="$HOME/.config/uv/uv.toml"
  if grep -q 'pypi.tuna' "$UVCFG" 2>/dev/null; then
    echo "uv PyPI 镜像已配置(清华),跳过"
  elif [ -f "$UVCFG" ]; then
    echo "跳过 uv 镜像:$UVCFG 已存在(非本脚本写入),不覆盖"
  elif ask "配置 uv 用清华 PyPI 镜像($UVCFG)?" Y; then
    mkdir -p "$(dirname "$UVCFG")"
    printf '%s\n' 'index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"' > "$UVCFG"
    echo "wrote: $UVCFG"
  fi
else
  echo "提示: 未检测到 uv,跳过 strictdoc 安装(.sdoc 校验依赖);装好 uv 后重跑本脚本即可"
fi

# ---- 2. pi 本体 ----
PI_BIN="$(command -v pi 2>/dev/null || true)"
if [ -z "$PI_BIN" ] && [ -x "$HOME/.local/share/pi-node/current/bin/pi" ]; then
  PI_BIN="$HOME/.local/share/pi-node/current/bin/pi"
  export PATH="$HOME/.local/share/pi-node/current/bin:$PATH"
fi
if [ -z "$PI_BIN" ]; then
  echo "未检测到 pi。"
  if ask "是否安装 Pi(官方 install.sh,装到 ~/.local/share/pi-node)?" Y; then
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
# 记录本仓库 Pi 插件的版本,便于本次运行结束时明确报出"是否更新了"
repo_head_before="$(git -C "$REPO_PI_PKG" rev-parse --short HEAD 2>/dev/null || true)"
report_repo_pi_pkg() {
  local now subject
  now="$(git -C "$REPO_PI_PKG" rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$now" ] || return 0
  subject="$(git -C "$REPO_PI_PKG" log -1 --format=%s 2>/dev/null || true)"
  if [ -z "$repo_head_before" ]; then
    echo "本仓库 Pi 插件: $now(本次安装);最新提交: $subject"
  elif [ "$repo_head_before" = "$now" ]; then
    echo "本仓库 Pi 插件: $now(本次无更新)"
  else
    echo "本仓库 Pi 插件已更新: $repo_head_before -> $now($(git -C "$REPO_PI_PKG" rev-list --count "$repo_head_before..$now" 2>/dev/null || echo '?') 个提交)"
    echo "  最新提交: $subject"
  fi
}
if [ -x "$PI_BIN" ]; then
  echo "pi 就绪: $("$PI_BIN" --version 2>/dev/null || echo 未知版本) ($PI_BIN)"
  PI_OK=1
  if ask "更新 pi 本体与已装包(pi update --all --no-approve)?" Y; then
    "$PI_BIN" update --all --no-approve < /dev/null || echo "WARN: pi update 失败(可稍后手动重试)" >&2
    report_repo_pi_pkg
  fi
else
  echo "WARN: 未找到 pi,跳过所有 Pi 相关配置(装好后重跑本脚本即可)" >&2
fi

# ---- 3. pi 包(pi install 幂等;写 ~/.pi/agent/settings.json 的 packages 数组)----
if [ "$PI_OK" -eq 1 ]; then
  pkg_installed() { # $1=完整 spec,如 npm:pi-mcp-adapter
    python3 - "$SETTINGS" "$1" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in (d.get("packages") or []) else 1)
PYEOF
  }
  pi_install() { # $1=spec
    if pkg_installed "$1"; then
      echo "已有: $1"
    elif ask "安装 pi 包 $1?" Y; then
      "$PI_BIN" install "$1" < /dev/null || echo "WARN: $1 安装失败(检查网络/代理)" >&2
    else
      echo "跳过: $1"
    fi
  }
  pi_install npm:pi-mcp-adapter
  pi_install npm:@dietrichgebert/ponytail
  pi_install npm:pi-subagents-j0k3r
  pi_install npm:pi-lens
  pi_install npm:@juicesharp/rpiv-ask-user-question
  # 0.6.8 上游将配置路径硬编码到 ~/.pi/agent,自定义 agent dir 暂不部署此插件。
  if [ "$AGENT_DIR" = "$HOME/.pi/agent" ]; then
    pi_install npm:pi-autoname@0.6.8
  else
    echo "WARN: pi-autoname 0.6.8 不遵循 PI_CODING_AGENT_DIR,跳过自动命名"
  fi
  # 本仓库自身作为 Pi 包:UI + claude-mem + later + message-timing + one-dark
  pi_install git:github.com/brilliantrough/agent-skills
  report_repo_pi_pkg

  # ---- 3.1 magic-context:共享 context.db 的版本守卫 ----
  # OpenCode 插件与 Pi 扩展共用 ~/.local/share/cortexkit/magic-context/context.db。
  # 版本不一致时,新宿主(fail-closed)会拒绝主回合,直到另一个宿主以新版重启并完成 DB 迁移。
  # opencode 的插件缓存把版本钉死在下载时(不随重启自动升级),所以这里先比版本再决定是否启用。
  mc_blocked=0
  oc_pinned=""
  if [ -f "$OC_MC_CACHE/package.json" ]; then
    oc_pinned="$(python3 -c "import json;print(json.load(open('$OC_MC_CACHE/package.json')).get('dependencies',{}).get('@cortexkit/opencode-magic-context',''))" 2>/dev/null || true)"
  fi
  if [ -n "$oc_pinned" ]; then
    pi_latest="$(timeout 15 npm view @cortexkit/pi-magic-context version 2>/dev/null || true)"
    if [ -n "$pi_latest" ] && [ "$oc_pinned" != "$pi_latest" ]; then
      mc_blocked=1
      echo ""
      echo "注意: magic-context 版本不一致 —— opencode 插件缓存 $oc_pinned,Pi 扩展最新 $pi_latest"
      echo "      两者共享 context.db,版本不一致时 Pi 主回合会被 fail-closed 拒绝。"
      echo "      处理: 清掉 opencode 插件缓存目录后重启 opencode(启动时会拉新版并迁移 DB):"
      echo "        rm -rf \"$OC_MC_CACHE\" && 重启 opencode"
      if ask "现在清理 opencode 插件缓存目录?" N; then
        rm -rf "$OC_MC_CACHE"
        echo "removed: $OC_MC_CACHE(重启 opencode 后自动重新下载)"
      fi
      echo ""
    fi
  fi
  if pkg_installed npm:@cortexkit/pi-magic-context; then
    echo "已有: npm:@cortexkit/pi-magic-context(magic-context)"
    [ "$mc_blocked" -eq 1 ] && echo "  WARN: 仍存在版本不一致,重启 opencode 前 Pi 记忆功能不可用"
  elif [ "$mc_blocked" -eq 1 ]; then
    if ask "仍要现在启用 Pi 版 magic-context(重启 opencode 前 Pi 主回合会被拒绝)?" N; then
      "$PI_BIN" install npm:@cortexkit/pi-magic-context < /dev/null || echo "WARN: magic-context 安装失败" >&2
    else
      echo "跳过: 暂不启用 Pi 版 magic-context(清理 opencode 插件缓存并重启后,重跑本脚本即可)"
    fi
  else
    pi_install npm:@cortexkit/pi-magic-context
  fi
fi

# ---- 4. 部署 Pi 配置(字段级合并 dot_file 模板)----
if [ "$PI_OK" -eq 1 ]; then
  collect_gateway_values
  merge_cfg "$RAW/pi/settings.json" "$SETTINGS" || true
  if [ "$AGENT_DIR" = "$HOME/.pi/agent" ]; then
    merge_cfg "$RAW/pi/pi-autoname.json" "$AGENT_DIR/pi-autoname.json" || true
  fi
  merge_cfg "$RAW/pi/models.json" "$MODELS" || true
  CG_BIN="$(command -v codegraph 2>/dev/null || true)"; [ -n "$CG_BIN" ] || CG_BIN="$HOME/.local/bin/codegraph"
  [ -x "$CG_BIN" ] || CG_BIN=codegraph
  merge_cfg "$RAW/pi/mcp.json" "$SHARED_MCP" mcp || true

  # ---- 4.05 凭据(auth.json,coding plan 等内置 provider)----
  # 只初始化缺失文件(占位符);已有条目的 key 是敏感值,合并时保留本地,不覆盖。
  auth_rc=0; merge_cfg "$RAW/pi/auth.json" "$AUTH" || auth_rc=$?
  if [ "$auth_rc" = 1 ] && [ ! -f "$AUTH" ]; then
    if ask "写入 $AUTH(内嵌兜底模板,含占位符)?" Y; then
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
  [ -f "$AUTH" ] && chmod 600 "$AUTH"

  # ---- 4.1 codegraph MCP 需要的 CLI(可选)----
  if [ ! -x "$CG_BIN" ]; then
    echo "未检测到 codegraph(代码知识图谱,MCP 需要 CLI 提供 graph)。"
    if ask "是否安装 codegraph CLI(curl 官方 install.sh)?" Y; then
      cg_sh="$(mktemp)"
      if curl -fsSL --connect-timeout 8 -m 60 -o "$cg_sh" https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh; then
        sh "$cg_sh" || echo "WARN: codegraph 安装脚本退出码非 0,请看上方输出" >&2
      else
        echo "WARN: codegraph 安装脚本下载失败(检查代理)" >&2
      fi
      rm -f "$cg_sh"
    fi
  fi
fi

# ---- 5. claude-mem 资产(缺失则官方安装器,只为拿 worker/MCP 资产)
#      先装 runtime 再写配置:安装器会自己写一份 settings,之后我们的模板合并覆盖它(凭据保留)
mkdir -p "$HOME/.claude-mem"
if [ ! -f "$MCP_CJS" ]; then
  if command -v npx >/dev/null 2>&1 && ask "未找到 claude-mem 资产,运行官方安装器 npx claude-mem install --ide opencode?" Y; then
    # 安装器会写 provider；只拿资产，退出时原样恢复共享 settings，不启动错误后端。
    (
      [ ! -L "$MC_SETTINGS" ] || { echo "ERROR: settings 是符号链接，跳过安装" >&2; exit 1; }
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
      npx -y claude-mem install --ide opencode --provider claude --no-auto-start < /dev/null
    ) || echo "WARN: claude-mem 安装失败；请检查上方恢复提示" >&2
    ensure_mem_provider "$MC_SETTINGS"
  fi
fi

# ---- 6. 共用配置:claude-mem settings + magic-context.jsonc(与 opencode-setup.sh 同一套;下载失败用内嵌兜底)----
mkdir -p "$HOME/.claude-mem"
mc_rc=0; merge_cfg "$RAW/opencode/claude-mem.settings.json" "$MC_SETTINGS" || mc_rc=$?
# 含密钥/本机路径的配置统一 600(对齐 codex-setup.sh 的 umask 077);文件可能还不存在
chmod 600 "$MODELS" "$AUTH" "$MC_SETTINGS" "$MC_CFG" 2>/dev/null || true
ensure_mem_worker_keys "$MC_SETTINGS" 2>/dev/null || true
echo "claude-mem worker: http://$(mem_worker_url)(健康检查: curl -s http://$(mem_worker_url)/api/health)"
if [ "$mc_rc" = 1 ] && [ ! -f "$MC_SETTINGS" ]; then
  if ask "写入 $MC_SETTINGS(内嵌兜底模板,含占位符)?" Y; then
  cat > "$MC_SETTINGS" <<'EOF'
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
  echo "wrote: $MC_SETTINGS(含占位符)"
  else
    echo "跳过: $MC_SETTINGS 未创建"
  fi
fi

mcc_rc=0; merge_cfg "$RAW/opencode/magic-context.jsonc" "$MC_CFG" || mcc_rc=$?
if [ "$mcc_rc" = 1 ] && [ ! -f "$MC_CFG" ]; then
  if ask "写入 $MC_CFG(内嵌兜底模板,含占位符)?" Y; then
  mkdir -p "$HOME/.config/cortexkit"
  cat > "$MC_CFG" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/cortexkit/magic-context/master/assets/magic-context.schema.json",
  "historian": {
    "opencode": {
      "model": "anthropic-newapi/deepseek-flash"
    },
    "pi": {
      "model": "anthropic-newapi/deepseek-flash",
      "thinking_level": "medium"
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

# ---- 6.1 Pi 桥扩展/主题已迁入 git:github.com/brilliantrough/agent-skills(见步骤 3);
#      旧版由本脚本部署到 ~/.pi/agent/{extensions, themes} 的文件与包内扩展会双注册冲突,清理之 ----
if [ "$PI_OK" -eq 1 ]; then
  if pkg_installed "git:github.com/brilliantrough/agent-skills"; then
    for legacy in "$AGENT_DIR/extensions/claude-mem.ts" "$AGENT_DIR/themes/onedark.json"; do
      if [ -f "$legacy" ] && [ ! -L "$legacy" ]; then
        if ask "删除旧版部署文件 $legacy(已由 Pi 包提供,重复注册会冲突)?" Y; then
          rm -f "$legacy"; echo "removed: $legacy"
        fi
      fi
    done
  fi
  # ---- 6. subagent 定义 + 个性化 UI 配置(仓库模板整文件覆盖;有差异先存 .bak)----
  # 不做一次性迁移:仓库模板就是当前已验证的配置,直接覆盖。
  # 想保留本机在 /ui 里的改动,就把它同步回模板,否则下次 setup 会覆盖回去。
  prune_legacy_ui_packages
  deploy_file "$RAW/pi/agent-skills-ui.json" "$AGENT_DIR/agent-skills-ui.json" "个性化 UI 布局/侧栏" || true
  deploy_file "$RAW/pi/agent-skills-editor.json" "$AGENT_DIR/agent-skills-editor.json" "个性化 UI 编辑器/页脚" || true
  deploy_file "$RAW/pi/keybindings.json" "$AGENT_DIR/keybindings.json" "按键(Enter 换行、Ctrl+Enter 提交等)" || true
  deploy_file "$RAW/pi/agents/explore.md" "$AGENT_DIR/agents/explore.md" "explore 子代理" || true
  deploy_file "$RAW/pi/agents/general.md" "$AGENT_DIR/agents/general.md" "general 子代理" || true
fi

# ---- 7. skills 本体 ----
if [ -d "$HOME/.agents/skills/load-mem" ]; then
  if command -v npx >/dev/null 2>&1 && ask "更新 skills 本体(npx skills update -g)?" Y; then
    npx -y skills@latest update -g || true
  fi
elif ! command -v npx >/dev/null 2>&1; then
  echo "跳过 skills 安装(需要 npx:先装 Node 再重跑)"
elif ask "安装 skills 本体(brilliantrough/agent-skills 全部 12 个;pi 原生读 ~/.agents/skills)?" Y; then
  # || true:PromptScript 等无关 agent 不支持全局安装会报错退出,但其余目标已装好
  npx -y skills@latest add brilliantrough/agent-skills --all -g -y || true
fi

# ---- 8. strictdoc(.sdoc 校验依赖;uv 已在 1.3 检查/安装)----
UV_BIN="$(command -v uv 2>/dev/null || echo "$HOME/.local/bin/uv")"
if [ -x "$UV_BIN" ]; then
  if command -v strictdoc >/dev/null 2>&1; then
    echo "strictdoc 已存在,跳过(升级: uv tool upgrade strictdoc)"
  elif ask "用 uv 全局安装 strictdoc==0.28.1(.sdoc 校验依赖)?" Y; then
    "$UV_BIN" tool install strictdoc==0.28.1 || echo "WARN: strictdoc 安装失败(可稍后重试)" >&2
  fi
else
  echo "提示: 未检测到 uv,跳过 strictdoc 安装(.sdoc 校验依赖);装好 uv 后重跑本脚本即可"
fi


# ---- 自检:UI 到底会不会生效(这几个是"没生效"的常见原因)----
echo ""
# ---- 9. 开发本仓库时的类型诊断软链(仅本地;不影响运行)----
# 仓库不装 node_modules,Pi 运行时自己提供这些模块;但编辑器/pi-lens 的 TS 诊断会报
# “Cannot find module '@earendil-works/pi-*' / 'node:*'” 这类假报错。把已装 Pi 包软链进
# 仓库 node_modules 即可消失(node_modules 已在 .gitignore 中排除,不会被提交)。
link_dev_types() {
  [ -f "$PWD/pi/extensions/ui/index.ts" ] || return 0   # 只在仓库源码目录里跑
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
PI_PKG_DIR="$AGENT_DIR/git/github.com/brilliantrough/agent-skills"
if [ -d "$PI_PKG_DIR/.git" ]; then
  echo "  UI 包(git): $(git -C "$PI_PKG_DIR" rev-parse --short HEAD 2>/dev/null) $(git -C "$PI_PKG_DIR" log -1 --pretty=%s 2>/dev/null | cut -c1-50)"
else
  echo "  UI 包(git): 未安装 -> 检查步骤 3 的 git:github.com/brilliantrough/agent-skills"
fi
if pkg_installed "git:github.com/brilliantrough/agent-skills"; then
  echo "  packages[]: 已登记 git:github.com/brilliantrough/agent-skills"
else
  echo "  packages[]: 未登记(扩展不会被加载;`pi install git:github.com/brilliantrough/agent-skills`)"
fi
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
echo "$n. 网关/凭据:脚本启动时已问过「网关地址 + API key」并填进各配置(可用环境变量预填、非交互跑:PI_GATEWAY_BASE_URL / PI_GATEWAY_API_KEY / MCPHUB_HOST)"; n=$((n+1))
echo "   当时跳过了才需要手工填下面这些占位符:"
[ "$PI_OK" -eq 1 ] && echo "   - $MODELS:https://<YOUR_GATEWAY_HOST>(anthropic 协议填根域,openai 协议带 /v1)、<YOUR_NEWAPI_API_KEY>"
[ "$PI_OK" -eq 1 ] && echo "   - $AUTH:coding plan 等内置 provider 的 key(如 zai-coding-cn / kimi-coding)"
echo "   - $SHARED_MCP:https://<YOUR_MCPHUB_HOST>/mcp/web"
echo "   - $MC_SETTINGS:BASE_URL / MODEL / API_KEY(openrouter 走 OpenAI 协议)"
echo "   - $MC_CFG:BASE_URL / API_KEY;historian/dreamer 的 model 用 <provider>/<model-id>"
echo "   - ~/.func(linux-setup.sh 部署):<YOUR_GATEWAY_HOST> / <YOUR_ANTHROPIC_AUTH_TOKEN>"
echo "$n. 重启 claude-mem worker 并验证:"; n=$((n+1))
echo "      cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart"
echo "      curl -s http://$(mem_worker_url)/api/health   # 端口取自 $MC_SETTINGS(见下方提示)"
echo "$n. 项目接入记忆系统: 把本仓库 AGENTS.md 中 memory-system:start/end 之间的块,粘进项目 AGENTS.md"; n=$((n+1))
if [ -x "${CG_BIN:-}" ]; then
  echo "$n. 代码知识图谱(按项目):cd <项目> && codegraph init(建 .codegraph/ 索引;不 init 则 MCP 无内容可查)"; n=$((n+1))
fi
echo "$n. 重启 pi(新配置生效;pi 内 /model 可查看已配置模型)"; n=$((n+1))
if [ "${mc_blocked:-0}" -eq 1 ]; then
  echo "!! magic-context 版本不一致未处理:清掉 \"$OC_MC_CACHE\" 并重启 opencode 后,重跑本脚本启用 Pi 版记忆"
fi
