#!/usr/bin/env bash
# opencode-setup.sh — 个人 opencode 一键配置(claude-mem + magic-context + ponytail + notify + skills 本体)
# 仓库: brilliantrough/agent-skills
#
# 干什么(交互确认 + 幂等,重复跑安全):
#   0. 代理环境提醒(国内网络下载易卡;http_proxy/https_proxy 未设时要求确认)
#   1. 依赖检查:python3(配置写入用,缺失则退出)、npx(缺 → 征得同意装 fnm + Node LTS)、
#      bun(缺 → 征得同意装,MCP server 依赖 bun:sqlite)
#   2. claude-mem:未装 → 征得同意跑官方安装器(只为拿 bundle 和 MCP 资产);然后修复
#      upstream bug(bundle 移出 plugins/ → lib/,写 wrapper;thedotmack/claude-mem#2854/#3328)
#   3. 清理 config 里失效的 claude-mem 插件条目(官方安装器每次都会重新注册)
#   4. 部署 ~/.claude-mem/settings.json 品味模板(已存在则不覆盖);占位符见文末清单
#   5. MCP 查询工具(插件本体不带工具,MCP 是唯一来源)→ 自动写 opencode.json
#   6. 插件条目:magic-context + ponytail 直接写入 opencode.json(不跑官方交互 setup,
#      magic-context 无配置文件即全默认,与本机品味一致)。只写纯 JSON 的 opencode.json
#      (带注释的 jsonc 留给用户手动维护,两份 config opencode 深度合并)
#   7. skills 本体:npx skills add brilliantrough/agent-skills --all -g -y
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

ask() { # 读 /dev/tty:curl|bash 时 stdin 是脚本管道,绝不能从 stdin 读,否则会吞掉脚本行
  local a=""
  # 不能加 2>/dev/null:read -p 的提示符写往 stderr,吞掉后提示不可见,脚本像卡死
  if { [ -t 0 ] || [ -e /dev/tty ]; } && read -r -p "$1 [y/N] " a < /dev/tty; then
    [[ "$a" =~ ^[Yy]$ ]]
  else
    false  # 非交互环境一律默认否
  fi
}

RAW="https://raw.githubusercontent.com/brilliantrough/dot_file/master"
# fetch_cfg <url> <dest> — 已存在则征求覆盖(.bak 备份),拒绝时返回非 0
fetch_cfg() {
  local dest="$2"
  if [ -f "$dest" ]; then
    ask "$dest 已存在,用 dot_file 仓库版本覆盖?(原文件存为 .bak,占位符需重新填充)" || return 1
    cp "$dest" "$dest.bak"
  fi
  mkdir -p "$(dirname "$dest")"
  echo "fetching: $1"
  curl -fsSL --connect-timeout 8 -m 30 -o "$dest" "$1" && echo "fetched: $dest"
}

echo "== opencode 一键配置 =="

# ---- 0. 代理提醒 ----
proxy="${http_proxy:-${https_proxy:-${all_proxy:-}}}"
if [ -n "$proxy" ]; then
  echo "代理: $proxy"
else
  echo "提醒: 未检测到代理环境变量(http_proxy/https_proxy/all_proxy)。"
  echo "      国内网络下 curl / npm / npx 下载可能长时间卡住,建议先配置代理再执行。"
  ask "没有代理也继续吗？" || exit 1
fi

# ---- 1. 依赖: python3(必需) ----
command -v python3 >/dev/null 2>&1 || { echo "ERROR: 未检测到 python3(配置写入依赖它)。请先安装(如 apt install python3)后重跑。" >&2; exit 1; }

# ---- 1.1 依赖: npx(fnm + Node)----
if ! command -v npx >/dev/null 2>&1; then
  echo "未检测到 npx(claude-mem 官方安装器与 skills 安装需要 Node)。"
  if ask "是否安装 fnm + Node LTS？"; then
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
  if ask "是否安装 bun？"; then
    curl -fsSL --connect-timeout 8 -m 60 https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
  else
    echo "跳过 bun(claude-mem MCP 工具将无法运行)"
  fi
fi
BUN_BIN="$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")"

# ---- 2. claude-mem:安装(只为拿 bundle / MCP 资产)+ 修复 ----
if [ ! -f "$BUNDLED" ] && [ ! -f "$PLUGINS/claude-mem.js" ]; then
  if command -v npx >/dev/null 2>&1 && ask "未找到 claude-mem,运行官方安装器 npx claude-mem install --ide opencode?"; then
    # </dev/null:非 TTY 让安装器结尾的 cmem Pro 试用推销自动跳过(skip = 继续本地生成)
    npx -y claude-mem install --ide opencode < /dev/null
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
  cat > "$PLUGINS/claude-mem-wrapper.js" <<'EOF'
// Wrapper for claude-mem's OpenCode plugin.
// Works around upstream bug (thedotmack/claude-mem#2854/#3328): the bundled
// claude-mem.js exports non-function constants (REAL_OPENCODE_EVENT_TYPES,
// REGISTERED_OPENCODE_HOOKS), but opencode's plugin loader requires EVERY
// module export to be a plugin function. This module re-exports only the
// plugin function. Regenerate with opencode-setup.sh.
import { ClaudeMemPlugin } from "../lib/claude-mem.js";

export default ClaudeMemPlugin;
EOF
  echo "wrote: plugins/claude-mem-wrapper.js"

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
clean = [x for x in plugins if not (isinstance(x, str) and "claude-mem" in x)]
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

  # ---- 2.2 确保 wrapper 条目存在(官方安装器注册的是失效条目,清理后可能两个 config 都没有)----
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

# ---- 3. 部署 settings.json(优先 dot_file 仓库,下载失败用内嵌模板兜底)----
mkdir -p "$HOME/.claude-mem"
fetch_cfg "$RAW/opencode/claude-mem.settings.json" "$SETTINGS" || true
if [ ! -f "$SETTINGS" ]; then
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
  echo "wrote: $SETTINGS(含占位符,待填项见文末清单)"
fi

# ---- 3.1 magic-context 配置文件(优先 dot_file 仓库;historian.model 必填,否则插件报错)----
MC_CFG="$HOME/.config/cortexkit/magic-context.jsonc"
fetch_cfg "$RAW/opencode/magic-context.jsonc" "$MC_CFG" || true
if [ ! -f "$MC_CFG" ]; then
  mkdir -p "$HOME/.config/cortexkit"
  cat > "$MC_CFG" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/cortexkit/magic-context/master/assets/magic-context.schema.json",
  "historian": {
    "opencode": {
      "model": "anthropic-newapi/deepseek-v4-flash"
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
      "model": "anthropic-newapi/deepseek-v4-flash"
    }
  },
  "sidekick": {
    "disable": true
  }
}
EOF
  echo "wrote: $MC_CFG(占位符待填项见文末清单;historian/dreamer 的 model 按实际 provider/model-id 修改)"
fi

# ---- 4. 完整 opencode.jsonc(可选,来自 dot_file 仓库:providers/agents/mcp/插件条目/compaction)----
cfg_full=0
if fetch_cfg "$RAW/opencode/opencode.jsonc" "$CFG/opencode.jsonc"; then
  sed -i "s|/home/pzy000|$HOME|g" "$CFG/opencode.jsonc"
  echo "fetched: $CFG/opencode.jsonc(home 路径已替换;网关与 key 占位符待填,见文末清单)"
  cfg_full=1
fi

# ---- 4.1 MCP 查询工具 → opencode.json ----
if [ -f "$BUNDLED" ] && [ -f "$MCP_CJS" ]; then
  configured=0
  for name in opencode.jsonc opencode.json; do
    f="$CFG/$name"
    if [ -f "$f" ] && grep -qs 'mcp-server.cjs' "$f"; then configured=1; break; fi
  done
  if [ "$configured" -eq 0 ]; then
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
  echo "WARN: 未找到 $MCP_CJS,跳过 MCP 配置(先完成 claude-mem 官方安装)" >&2
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
  if ask "未检测到插件条目:$pkgs。直接写入 $CFG/opencode.json?"; then
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
if ! grep -qs '"compaction"' "$CFG/opencode.jsonc" "$CFG/opencode.json" 2>/dev/null; then
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

# ---- 6. notify 插件(brilliantrough/opencode-notify-hub,GitHub Release 预构建包)----
NOTIFY_TARGET="$PLUGINS/session-notify.js"
if [ ! -f "$NOTIFY_TARGET" ] && command -v curl >/dev/null 2>&1; then
  if ask "未找到 notify 插件,从 GitHub Release 下载最新 opencode-notify-plugin?"; then
    python3 - "$PLUGINS" <<'PYEOF' || echo "WARN: notify 插件下载失败,可按仓库 PLUGIN-INSTALL.md 手动安装" >&2
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
if [ ! -d "$HOME/.agents/skills/load-mem" ]; then
  if command -v npx >/dev/null 2>&1 && ask "安装 skills 本体(brilliantrough/agent-skills 全部 11 个)?"; then
    # || true:PromptScript 等无关 agent 不支持全局安装会报错退出,但其余目标已装好
    npx -y skills@latest add brilliantrough/agent-skills --all -g -y || true
  fi
fi

# ---- 8. strictdoc 检查(只提醒,不代装——env 管理器是用户的选择)----
command -v strictdoc >/dev/null 2>&1 || echo "提示: 未检测到 strictdoc(记忆 skill 的 .sdoc 校验依赖)。建议装进项目 venv/conda:pip install strictdoc==0.28.1"

# ---- 完成:占位符清单 + 收尾动作 ----
echo ""
echo "== done. 需要你手工完成的 =="
echo "1. 填占位符:"
echo "   - $SETTINGS:BASE_URL / MODEL / API_KEY"
echo "   - $MC_CFG:BASE_URL / API_KEY(historian、dreamer 的 model 按实际 provider/model-id 改)"
[ "$cfg_full" -eq 1 ] && echo "   - $CFG/opencode.jsonc:网关地址 / API key 占位符"
echo "2. 重启 claude-mem worker 并验证:"
echo "      cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:restart"
echo "      curl -s 127.0.0.1:37700/api/health"
echo "3. 项目接入记忆系统: 把本仓库 AGENTS.md 中 memory-system:start/end 之间的块,粘进项目 AGENTS.md"
if [ -f "$NOTIFY_TARGET" ]; then
  echo "4. notify 插件环境变量 —— 在启动 opencode 的 shell 配置(~/.zshrc 或 ~/.bashrc)里 export:"
  echo "      NOTIFY_GATEWAY_URL=<你的网关地址>    NOTIFY_INGEST_KEY=<你的 ingest key>"
  echo "      可选: NOTIFY_MACHINE=<机器名>(多机区分),其余 NOTIFY_* 调参项见插件 config.ts"
  echo "5. 重启 opencode 生效"
else
  echo "4. 重启 opencode 生效"
fi
