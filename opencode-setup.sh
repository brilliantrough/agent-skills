#!/usr/bin/env bash
# opencode-setup.sh — 个人 opencode 一键配置(claude-mem + magic-context + ponytail + notify + skills 本体)
# 仓库: brilliantrough/agent-skills
#
# 干什么(交互确认 + 幂等,重复跑安全):
#   询问默认:装缺的软件/插件、写入条目 → [Y/n](回车即装);覆盖已有配置、无代理下继续 → [y/N];
#            非交互环境按各自默认执行
#   0. 代理环境提醒(大小写都查;未设则探测直连,透明代理不拦;都不通才要求确认)
#   1. 依赖检查:python3(配置写入用,缺失则退出)、npx(缺 → 征得同意装 fnm + Node LTS)、
#      bun(缺 → 征得同意装,MCP server 依赖 bun:sqlite)
#   2. claude-mem:未装 → 征得同意跑官方安装器(只为拿 bundle 和 MCP 资产,--provider claude
#      是唯一免浏览器 OAuth 的选项);然后修复 upstream bug(bundle 移出 plugins/ → lib/,
#      写 wrapper;thedotmack/claude-mem#2854/#3328)。再清理 config 里失效的 claude-mem 插件条目
#      (官方安装器每次都会重新注册),并确保 wrapper 条目存在
#   3. 部署(字段级合并)~/.claude-mem/settings.json 与 ~/.config/cortexkit/magic-context.jsonc:
#      dot_file 模板的非敏感字段值优先下发,api key / base url 等本地敏感值保留;下载失败用内嵌兜底
#   4. 部署/更新 ~/.config/opencode/opencode.json(dot_file 模板:providers/agents/mcp/插件条目/
#      compaction)。已存在则只覆盖各 provider 的 models,apiKey 等本地字段原样保留;
#      老 opencode.jsonc 的值自动并入后退役为 .migrated.bak
#   5. MCP 查询工具(claude-mem)+ codegraph 代码知识图谱(CLI 可选安装 + MCP 条目)+
#      插件条目(magic-context、ponytail)+ compaction 关闭 + TUI 侧边栏条目(tui.jsonc)
#      → 写入纯 JSON 的 opencode.json(及 TUI 的 tui.jsonc)
#   6. notify 插件(brilliantrough/opencode-notify-hub,GitHub Release 预构建包)
#   7. skills 本体:npx skills add brilliantrough/agent-skills --all -g -y
#   8. uv(缺则装;含自升级与清华 PyPI 镜像)+ strictdoc(用 uv tool 全局安装,.sdoc 校验依赖)
#
# 用法:bash opencode-setup.sh   (遵循 OPENCODE_CONFIG_DIR,与官方安装器一致)

set -euo pipefail

CFG="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
PLUGINS="$CFG/plugins"
LIB="$CFG/lib"
mkdir -p "$CFG" "$PLUGINS"
BUNDLED="$LIB/claude-mem.js"
MCP_CJS="$HOME/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"
SETTINGS="$HOME/.claude-mem/settings.json"

ask() { # $1=提示 $2=默认(Y/N,缺省 N)
  local a="" def="${2:-N}" hint="y/N"
  [ "$def" = Y ] && hint="Y/n"
  # 不能加 2>/dev/null:read -p 的提示符写往 stderr,吞掉后提示不可见,脚本像卡死
  # 读 /dev/tty:curl|bash 时 stdin 是脚本管道,绝不能从 stdin 读,否则会吞掉脚本行
  if { [ -t 0 ] || [ -e /dev/tty ]; } && read -r -p "$1 [$hint] " a < /dev/tty; then
    if [ -z "$a" ]; then [ "$def" = Y ]; else [[ "$a" =~ ^[Yy]$ ]]; fi
  else
    [ "$def" = Y ]  # 非交互(无 tty):按该询问的默认值
  fi
}

RAW="https://raw.githubusercontent.com/brilliantrough/dot_file/master"
# merge_cfg <url> <dest> — 拉 dot_file 模板后做「字段级」合并,而非整文件覆盖:
#   模板中的非敏感字段值优先 → 新默认值能下发到服务器;
#   敏感键(api key / secret / token / password / credential / bearer / url / endpoint / host)保留本地值;
#   模板里含 <占位符> 的值不覆盖本地已填内容;本地独有的键保留。
#   合并结果与本地一致时不写文件(幂等);有改动先存时间戳 .bak。
#   dest 不存在则直接落模板。符号链接跳过(不穿透)。
merge_cfg() {
  local url="$1" dest="$2" tmp cand out
  if [ -L "$dest" ]; then
    echo "跳过: $dest 是符号链接(指向 $(readlink "$dest")),不覆盖以免破坏链接目标"
    return 1
  fi
  tmp="$(mktemp)"
  echo "fetching: $url"
  if ! curl -fsSL --connect-timeout 8 -m 30 -o "$tmp" "$url"; then
    rm -f "$tmp"; echo "WARN: $url 下载失败,保留现有 $dest" >&2; return 1
  fi
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
SENSITIVE = re.compile(r'(api[_-]?key|secret|token|password|passwd|credential|bearer|base[_-]?url|endpoint|host)', re.I)
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

def merge(cur, new):
    if not isinstance(new, dict) or not isinstance(cur, dict):
        return new
    out = dict(cur)
    for k, v in new.items():
        if k in cur and SENSITIVE.search(k):                       # 敏感键:本地值优先
            continue
        if k in cur and isinstance(v, str) and PLACEHOLDER.search(v):  # 占位值不覆盖已填内容
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
    unchanged) echo "unchanged: $dest"; rm -f "$cand" ;;
    "")        echo "WARN: $dest 合并失败,保留原文件" >&2; rm -f "$cand"; return 1 ;;
    *)         if ask "更新 $dest($out;api key 等敏感值保留,原文件存 $bak)?" Y; then
                 cp "$dest" "$bak"; mv "$cand" "$dest"; echo "updated: $dest"
               else
                 echo "保留原文件: $dest"; rm -f "$cand"; return 2
               fi ;;
  esac
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

# ---- 1. 依赖: python3(必需) ----
command -v python3 >/dev/null 2>&1 || { echo "ERROR: 未检测到 python3(配置写入依赖它)。请先安装(如 apt install python3)后重跑。" >&2; exit 1; }

# ---- 1.1 依赖: npx(fnm + Node)----
if ! command -v npx >/dev/null 2>&1; then
  echo "未检测到 npx(claude-mem 官方安装器与 skills 安装需要 Node)。"
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
BUN_BIN="$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")"

# ---- 2. claude-mem:安装(只为拿 bundle / MCP 资产)+ 修复 ----
if [ ! -f "$BUNDLED" ] && [ ! -f "$PLUGINS/claude-mem.js" ]; then
  if command -v npx >/dev/null 2>&1 && ask "未找到 claude-mem,运行官方安装器 npx claude-mem install --ide opencode?" Y; then
    # --provider claude 是唯一免浏览器 OAuth 的选项(openrouter/gemini 非交互下强制 cmem.ai 登录并 exit 1);
    # 运行时 provider 由下面部署的 settings.json 决定,与安装期选项无关。|| true:安装器退出码不可靠
    npx -y claude-mem install --ide opencode --provider claude < /dev/null || true
  fi
fi

if [ -f "$PLUGINS/claude-mem.js" ]; then
  mkdir -p "$LIB"
  mv -f "$PLUGINS/claude-mem.js" "$BUNDLED"
  echo "moved: plugins/claude-mem.js -> lib/claude-mem.js"
fi

if [ ! -f "$BUNDLED" ]; then
  echo "WARN: 没有 claude-mem bundle,跳过 claude-mem 相关配置" >&2
else
  mkdir -p "$PLUGINS"
  w_tmp="$(mktemp)"
  cat > "$w_tmp" <<'EOF'
// Wrapper for claude-mem's OpenCode plugin.
// Works around upstream bug (thedotmack/claude-mem#2854/#3328): the bundled
// claude-mem.js exports non-function constants (REAL_OPENCODE_EVENT_TYPES,
// REGISTERED_OPENCODE_HOOKS), but opencode's plugin loader requires EVERY
// module export to be a plugin function. This module re-exports only the
// plugin function. Regenerate with opencode-setup.sh.
import { ClaudeMemPlugin } from "../lib/claude-mem.js";

export default ClaudeMemPlugin;
EOF
  if cmp -s "$w_tmp" "$PLUGINS/claude-mem-wrapper.js"; then rm -f "$w_tmp"
  elif ask "更新 $PLUGINS/claude-mem-wrapper.js(claude-mem wrapper 修复)?" Y; then
    mv "$w_tmp" "$PLUGINS/claude-mem-wrapper.js"; echo "wrote: plugins/claude-mem-wrapper.js"
  else rm -f "$w_tmp"; echo "保留原文件: plugins/claude-mem-wrapper.js"; fi

  # ---- 2.1 清理两份 config 里官方安装器注册的失效插件条目 ----
  for name in opencode.jsonc opencode.json; do
    python3 - "$CFG/$name" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        text = f.read()
except FileNotFoundError:
    sys.exit(0)
try:
    cfg = json.loads(text)
except json.JSONDecodeError:
    import re
    if re.search(r"plugins[/\\]claude-mem", text):
        print(f"WARN: {path} 含注释无法自动清理,请手动检查 plugin 数组中的 claude-mem 插件路径")
    sys.exit(0)
plugins = cfg.get("plugin")
if not isinstance(plugins, list):
    sys.exit(0)
clean = [x for x in plugins if not (isinstance(x, str) and "claude-mem" in x and x != "./plugins/claude-mem-wrapper.js")]
if len(clean) != len(plugins):
    if clean:
        cfg["plugin"] = clean
    else:
        cfg.pop("plugin", None)
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"cleaned: {path} plugin 数组中的 claude-mem 条目")
PYEOF
  done
fi

# ---- 3. 部署 settings.json(字段级合并 dot_file 模板;下载失败用内嵌模板兜底)----
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
  "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>"
}
EOF
  echo "wrote: $SETTINGS(含占位符)"
  else
    echo "跳过: $SETTINGS 未创建"
  fi
fi

# ---- 3.1 magic-context 配置文件(字段级合并 dot_file 模板;historian.model 必填,否则插件报错)----
MC_CFG="$HOME/.config/cortexkit/magic-context.jsonc"
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
cfg_full=0
oc_tpl="$(mktemp)"; oc_cand="$(mktemp)"
if curl -fsSL --connect-timeout 8 -m 30 -o "$oc_tpl" "$RAW/opencode/opencode.json"; then
  oc_out="$(python3 - "$CFG/opencode.json" "$CFG/opencode.jsonc" "$oc_tpl" "$HOME" "$oc_cand" <<'PYEOF'
import json, re, os, sys

target_p, jsonc_p, tpl_p, home = sys.argv[1:5]

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
    except Exception:
        return {}

def deep_merge(base, over):  # over 优先(本地值优先),dict 递归
    if isinstance(base, dict) and isinstance(over, dict):
        out = dict(base)
        for k, v in over.items():
            out[k] = deep_merge(base.get(k), v) if k in base else v
        return out
    return over

tpl = json.load(open(tpl_p, encoding='utf-8'))
if home != '/home/pzy000':
    tpl = json.loads(json.dumps(tpl).replace('/home/pzy000', home))

live_json, live_jsonc = load(target_p), load(jsonc_p)
live = live_json if live_json.get('provider') else (live_jsonc or live_json)

merged = deep_merge(tpl, live)
tpl_prov = tpl.get('provider') or {}
live_prov = live.get('provider') or {}
mp = merged.setdefault('provider', {})
for name, p in tpl_prov.items():
    if name in live_prov:
        # 已存在的 provider:本地节点原样保留(options/apiKey 一个字节都不动),只换 models
        mp[name] = {**live_prov[name], 'models': p.get('models', {})}
    elif name not in mp:
        mp[name] = p  # 模板新增的 provider:整块加入(含占位符 options,待首次填写)

out = json.dumps(merged, indent=2, ensure_ascii=False) + '\n'
try:
    same = open(target_p, encoding='utf-8').read() == out
except FileNotFoundError:
    same = False
msgs = []
if not same:
    with open(sys.argv[5], 'w', encoding='utf-8') as f:
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
                 [ -s "$oc_cand" ] && mv "$oc_cand" "$CFG/opencode.json"
                 echo "updated: $CFG/opencode.json"
                 if [ -f "$CFG/opencode.jsonc" ]; then
                   mv "$CFG/opencode.jsonc" "$CFG/opencode.jsonc.migrated-$(date +%Y%m%d%H%M%S).bak"
                   echo "retired: opencode.jsonc(值已并入 opencode.json)"
                 fi
               else
                 echo "保留原文件: $CFG/opencode.json"
               fi ;;
  esac
  cfg_full=1
else
  echo "跳过: opencode.json 模板下载失败(检查代理),现有配置未改动"
fi
rm -f "$oc_tpl" "$oc_cand"

# ---- 4.0 合并后补回 claude-mem wrapper 条目(旧 opencode.jsonc 自带 plugin 数组时,
#      第 4 步的模板合并会丢掉它——2.1 只清理了失效条目,这里兜底确保 wrapper 在)----
if [ -f "$BUNDLED" ]; then
  if ! grep -qs 'claude-mem-wrapper.js' "$CFG/opencode.json" 2>/dev/null && \
     ask "在 $CFG/opencode.json 补回 plugin 条目 ./plugins/claude-mem-wrapper.js?" Y; then
  python3 - "$CFG/opencode.json" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
ENTRY = "./plugins/claude-mem-wrapper.js"
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        text = f.read()
    if text.strip():
        cfg = json.loads(text)
plugins = cfg.setdefault("plugin", [])
if ENTRY not in plugins:
    plugins.append(ENTRY)
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"added: plugin {ENTRY} -> {path}")
PYEOF
  fi
fi

# ---- 4.1 MCP 查询工具 → opencode.json ----
if [ -f "$BUNDLED" ] && [ -f "$MCP_CJS" ]; then
  configured=0
  for name in opencode.jsonc opencode.json; do
    f="$CFG/$name"
    if [ -f "$f" ] && grep -qs 'mcp-server.cjs' "$f"; then configured=1; break; fi
  done
  if [ "$configured" -eq 0 ] && ask "在 $CFG/opencode.json 添加 claude-mem MCP 条目?" Y; then
    python3 - "$CFG/opencode.json" "$BUN_BIN" "$MCP_CJS" <<'PYEOF'
import json, sys
path, bun, cjs = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {"$schema": "https://opencode.ai/config.json"}
except FileNotFoundError:
    cfg = {"$schema": "https://opencode.ai/config.json"}
cfg.setdefault("mcp", {})
if "claude-mem" in cfg["mcp"]:
    sys.exit(0)
cfg["mcp"]["claude-mem"] = {"type": "local", "command": [bun, cjs], "enabled": True}
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
if ! command -v codegraph >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/codegraph" ]; then
  echo "未检测到 codegraph(代码知识图谱,MCP 需要 CLI 提供 graph)。"
  if ask "是否安装 codegraph CLI(curl 官方 install.sh)?" Y; then
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
CG_BIN="$(command -v codegraph 2>/dev/null || echo "$HOME/.local/bin/codegraph")"
if [ -x "$CG_BIN" ]; then
  if ! grep -qs '"codegraph"' "$CFG/opencode.json" "$CFG/opencode.jsonc" 2>/dev/null && \
     ask "在 $CFG/opencode.json 添加 codegraph MCP 条目?" Y; then
    python3 - "$CFG/opencode.json" "$CG_BIN" <<'PYEOF'
import json, sys
path, bin_ = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {"$schema": "https://opencode.ai/config.json"}
except FileNotFoundError:
    cfg = {"$schema": "https://opencode.ai/config.json"}
cfg.setdefault("mcp", {})
if "codegraph" in cfg["mcp"]:
    sys.exit(0)
cfg["mcp"]["codegraph"] = {"type": "local", "command": [bin_, "serve", "--mcp"], "enabled": True}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"added: mcp.codegraph -> {path}")
PYEOF
  fi
fi

# ---- 5. 插件条目: magic-context + ponytail(直写,不跑官方交互 setup)----
need_mc=0
grep -qs 'opencode-magic-context' "$CFG/opencode.jsonc" "$CFG/opencode.json" 2>/dev/null || need_mc=1
need_pt=0
grep -qs 'dietrichgebert/ponytail' "$CFG/opencode.jsonc" "$CFG/opencode.json" 2>/dev/null || need_pt=1

if [ "$need_mc" -eq 1 ] || [ "$need_pt" -eq 1 ]; then
  pkgs=""
  # shellcheck disable=SC2086
  [ "$need_mc" -eq 1 ] && pkgs="@cortexkit/opencode-magic-context@latest"
  # shellcheck disable=SC2086
  [ "$need_pt" -eq 1 ] && pkgs="$pkgs @dietrichgebert/ponytail"
  # shellcheck disable=SC2086
  if ask "未检测到插件条目:$pkgs。直接写入 $CFG/opencode.json?" Y; then
    # shellcheck disable=SC2086
    python3 - "$CFG/opencode.json" $pkgs <<'PYEOF'
import json, sys
path = sys.argv[1]
pkgs = sys.argv[2:]
try:
    with open(path) as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {"$schema": "https://opencode.ai/config.json"}
except FileNotFoundError:
    cfg = {"$schema": "https://opencode.ai/config.json"}
plugins = cfg.setdefault("plugin", [])
added = [p for p in pkgs if p not in plugins]
plugins.extend(added)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"added to {path} plugin: {', '.join(added)}")
PYEOF
  fi
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

# ---- 5.2 TUI 插件条目(magic-context 右侧可视化侧边栏)----
# 侧边栏(占比/historian/compartment 可视化)是独立于 opencode.json 的 TUI 插件,
# magic-context 只在自身 setup 向导/doctor 时才写,这里补上。opencode 同时加载
# tui.json 与 tui.jsonc(tui.jsonc 优先),故:有 jsonc 用 jsonc,否则用 json,都没有则建 tui.jsonc。
# 只增不删——用户故意移除该条目即表示不要侧边栏。
TUI_ENTRY="@cortexkit/opencode-magic-context@latest"
if [ -f "$CFG/tui.jsonc" ]; then TUI_CFG="$CFG/tui.jsonc"
elif [ -f "$CFG/tui.json" ]; then TUI_CFG="$CFG/tui.json"
else TUI_CFG="$CFG/tui.jsonc"; fi
if ! grep -qs 'magic-context' "$CFG/tui.jsonc" "$CFG/tui.json" 2>/dev/null && \
   ask "在 $TUI_CFG 添加 magic-context 侧边栏 TUI 插件条目?" Y; then
python3 - "$TUI_CFG" "$TUI_ENTRY" <<'PYEOF'
import json, re, sys
path, entry = sys.argv[1], sys.argv[2]
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
cfg = load(path)
plugins = cfg.get("plugin")
if not isinstance(plugins, list):
    plugins = []
def id_of(x):
    return x if isinstance(x, str) else (x[0] if isinstance(x, list) and x else "")
if any("magic-context" in id_of(x) for x in plugins):
    print(f"unchanged: {path}(已有 magic-context TUI 条目)")
else:
    plugins.append(entry)
    cfg["plugin"] = plugins
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"added: tui plugin {entry} -> {path}")
PYEOF
fi

# ---- 6. notify 插件(brilliantrough/opencode-notify-hub,GitHub Release 预构建包)----
NOTIFY_TARGET="$PLUGINS/session-notify.js"
if [ ! -f "$NOTIFY_TARGET" ] && command -v curl >/dev/null 2>&1; then
  if ask "未找到 notify 插件,从 GitHub Release 下载最新 opencode-notify-plugin?" Y; then
    python3 - "$PLUGINS" <<'PYEOF' || echo "WARN: notify 插件下载失败(检查代理)" >&2
import json, os, sys, urllib.request, zipfile
plugins_dir = sys.argv[1]
api = "https://api.github.com/repos/brilliantrough/opencode-notify-hub/releases"
req = urllib.request.Request(api, headers={"User-Agent": "opencode-setup"})
rels = json.load(urllib.request.urlopen(req, timeout=30))
url = next((a["browser_download_url"] for r in rels if not r.get("draft")
            for a in r.get("assets", [])
            if a["name"].startswith("opencode-notify-plugin-") and a["name"].endswith(".zip")), None)
if not url:
    raise SystemExit("release 中没有 opencode-notify-plugin-*.zip 资产")
print("downloading:", url)
tmp, _ = urllib.request.urlretrieve(url)
os.makedirs(plugins_dir, exist_ok=True)
with zipfile.ZipFile(tmp) as z:
    name = next(n for n in z.namelist() if n.endswith("session-notify.js"))
    with z.open(name) as src, open(os.path.join(plugins_dir, "session-notify.js"), "wb") as dst:
        dst.write(src.read())
print("installed: plugins/session-notify.js")
PYEOF
  fi
fi

# ---- 7. skills 本体 ----
if [ -d "$HOME/.agents/skills/load-mem" ]; then
  if command -v npx >/dev/null 2>&1 && ask "更新 skills 本体(npx skills update -g)?" Y; then
    npx -y skills@latest update -g || true
  fi
elif ! command -v npx >/dev/null 2>&1; then
  echo "跳过 skills 安装(需要 npx:先装 Node 再重跑)"
elif ask "安装 skills 本体(brilliantrough/agent-skills 全部 12 个)?" Y; then
  # || true:PromptScript 等无关 agent 不支持全局安装会报错退出,但其余目标已装好
  npx -y skills@latest add brilliantrough/agent-skills --all -g -y || true
fi

# ---- 8. uv(可选)+ strictdoc(.sdoc 校验依赖)----
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
echo "$n. 填占位符:"; n=$((n+1))
echo "   - $SETTINGS:BASE_URL / MODEL / API_KEY(openrouter 走 OpenAI 协议,填 OpenAI 协议的 key,不是 Anthropic 的)"
echo "   - $MC_CFG:BASE_URL / API_KEY;historian/dreamer 的 model 用 <provider>/<model-id>"
[ "$cfg_full" -eq 1 ] && echo "   - $CFG/opencode.json:网关地址 / API key 占位符(仅首次部署需填;之后脚本更新只覆盖 models)"
echo "$n. 重启 claude-mem worker 并验证:"; n=$((n+1))
echo "      cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart"
echo "      curl -s 127.0.0.1:37700/api/health"
echo "$n. 项目接入记忆系统: 把本仓库 AGENTS.md 中 memory-system:start/end 之间的块,粘进项目 AGENTS.md"; n=$((n+1))
if [ -x "$CG_BIN" ]; then
  echo "$n. 代码知识图谱(按项目):cd <项目> && codegraph init(建 .codegraph/ 索引,之后自动增量同步;不 init 则 MCP 无内容可查)"; n=$((n+1))
fi
if [ -f "$NOTIFY_TARGET" ]; then
  echo "$n. notify 插件环境变量 —— 在启动 opencode 的 shell 配置(~/.zshrc 或 ~/.bashrc)里 export:"; n=$((n+1))
  echo "      NOTIFY_GATEWAY_URL=<你的网关地址>    NOTIFY_INGEST_KEY=<你的 ingest key>"
  echo "      可选: NOTIFY_MACHINE=<机器名>(多机区分)"
fi
echo "$n. 重启 opencode 生效"
