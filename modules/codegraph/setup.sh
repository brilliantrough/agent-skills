#!/usr/bin/env bash
# module: codegraph
# desc: 代码知识图谱 CLI + MCP 注册（需 codegraph init 才有索引）
# default: Y
# hosts: pi,opencode,codex,antigravity
#
# CLI 本体宿主无关；MCP 注册按宿主分开：opencode 写 opencode.json（配置根与 opencode-setup.sh 一致：
# OPENCODE_CONFIG_DIR > XDG_CONFIG_HOME/opencode > ~/.config/opencode），codex 用 codex mcp add，
# antigravity 经 migrate-agents-tail.py --antigravity-mcp 合并 ~/.gemini/config/mcp_config.json 并桥接 T3，
# Pi 的 mcp.json 由本仓模板提供条目，不需要在这里写。
# 已有的 remote 或带 url 的 codegraph 条目属用户自定义，不自动改成 local：保留原文件并提示手工处理。
# 卸载: npm uninstall -g @colbymchenry/codegraph（或删 ~/.local/bin/codegraph），再删对应 MCP 条目。
set -euo pipefail

HOST=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --yes|-y) shift ;;
    *) shift ;;
  esac
done

IS_WIN=0
BIN_EXT=""
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*) IS_WIN=1; BIN_EXT=".exe" ;;
esac

# ---- CLI ----
cg="$(command -v codegraph 2>/dev/null || true)"
[ -n "$cg" ] || [ ! -x "$HOME/.local/bin/codegraph$BIN_EXT" ] || cg="$HOME/.local/bin/codegraph$BIN_EXT"
if [ -z "$cg" ]; then
  echo "未检测到 codegraph（代码知识图谱，MCP 需要 CLI 提供 graph）。"
  if [ "$IS_WIN" = 1 ]; then
    # 官方 install.sh 只认 Darwin/Linux；Windows 走 npm
    if ! command -v npm >/dev/null 2>&1; then
      echo "跳过 codegraph: 未检测到 npm"
    else
      echo "== 安装 codegraph CLI（npm）=="
      npm install -g @colbymchenry/codegraph@latest || { echo "WARN: codegraph 安装失败，请看上方输出" >&2; exit 1; }
    fi
  else
    echo "== 安装 codegraph CLI（官方 install.sh）=="
    tmp="$(mktemp)"
    if curl -fsSL --connect-timeout 8 -m 60 -o "$tmp" https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh; then
      sh "$tmp" || { rm -f "$tmp"; echo "WARN: codegraph 安装脚本退出码非 0" >&2; exit 1; }
    else
      rm -f "$tmp"; echo "WARN: codegraph 安装脚本下载失败（检查代理）" >&2; exit 1
    fi
    rm -f "$tmp"
    export PATH="$HOME/.local/bin:$PATH"
  fi
  cg="$(command -v codegraph 2>/dev/null || true)"
  [ -n "$cg" ] || [ ! -x "$HOME/.local/bin/codegraph$BIN_EXT" ] || cg="$HOME/.local/bin/codegraph$BIN_EXT"
fi

if [ -z "$cg" ]; then
  echo "WARN: codegraph 不可用，跳过 MCP 注册" >&2
  exit 1
fi
echo "codegraph: $cg"

# ---- MCP 注册（按宿主）----
native() { [ "$IS_WIN" = 1 ] && cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }

case "$HOST" in
  opencode)
    cfgdir="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
    cfg="$cfgdir/opencode.json"
    if [ "${AGENT_SKILLS_NO_CONFIG_WRITE:-0}" = 1 ]; then
      echo "跳过: 本次计划未写入配置，不登记 codegraph MCP 条目（CLI 已就绪，可重跑 setup 或手工添加）"
      exit 0
    fi
    node_bin=""; shim=""
    if [ "$IS_WIN" = 1 ] && command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
      _js="$(npm root -g 2>/dev/null)/@colbymchenry/codegraph/npm-shim.js"
      [ -f "$_js" ] && { node_bin="$(native "$(command -v node)")"; shim="$(native "$_js")"; }
    fi
    echo "== 写入 codegraph MCP 条目 =="
    python3 - "$cfg" "$(native "$cg")" "$node_bin" "$shim" <<'PY'
import datetime, json, pathlib, re, shutil, sys
path, bin_, node, shim = sys.argv[1:5]
p = pathlib.Path(path)
jsonc_path = p.with_suffix('.jsonc')
def load(path):
    try:
        text = path.read_text(encoding='utf-8')
    except FileNotFoundError:
        return {}
    string = r'"(?:\\.|[^"\\])*"'
    text = re.sub(f'({string})|//[^\n]*|/\\*[\\s\\S]*?\\*/', lambda m: m[1] or '', text)
    text = re.sub(f'({string})|,(\\s*[}}\\]])', lambda m: m[1] or m[2], text)
    return json.loads(text) if text.strip() else {}
def merge(base, over):
    out = dict(base)
    for key, value in over.items():
        out[key] = merge(out[key], value) if isinstance(out.get(key), dict) and isinstance(value, dict) else value
    return out
json_cfg = load(p)
if not json_cfg:
    json_cfg = {'$schema': 'https://opencode.ai/config.json'}
jsonc_cfg = load(jsonc_path)
effective = merge(json_cfg, jsonc_cfg)
missing = object()
def entries(doc):
    mcp = doc.get('mcp') if isinstance(doc.get('mcp'), dict) else {}
    servers = mcp.get('servers') if isinstance(mcp.get('servers'), dict) else {}
    return mcp.get('codegraph', missing), servers.get('codegraph', missing)
def jsonc_blocks_write(doc):
    if 'mcp' not in doc:
        return False
    mcp = doc['mcp']
    if not isinstance(mcp, dict) or 'codegraph' in mcp:
        return True
    if 'servers' not in mcp:
        return False
    servers = mcp['servers']
    return not isinstance(servers, dict) or 'codegraph' in servers
legacy, nested = entries(effective)
for entry in (legacy, nested):
    if isinstance(entry, dict) and (str(entry.get('type', '')).lower() == 'remote' or 'url' in entry):
        print('WARN: 有效配置中的 codegraph 是 remote／带 url 的自定义条目，保留 JSON／JSONC；如需本地 CLI 请手工修改', file=sys.stderr)
        raise SystemExit(0)
if legacy is not missing and nested is not missing:
    print('WARN: 旧式 mcp.codegraph 与 mcp.servers.codegraph 同时存在，保留原文件；请先归一化配置', file=sys.stderr)
    raise SystemExit(0)
sensitive = re.compile(r"(api[_-]?key|secret|token|password|passwd|credential|bearer|auth|cookie|ingest|webhook|base[_-]?url|url|endpoint|host|(^|[._-])key$)", re.I)
def managed(local, template):
    if not isinstance(template, dict):
        return template
    out = dict(template)
    if isinstance(local, dict):
        for key, value in local.items():
            if sensitive.search(key):
                out[key] = value
            elif isinstance(value, dict):
                nested_value = managed(value, out.get(key, {}))
                if nested_value or key in out:
                    out[key] = nested_value
    return out
cmd = [node, shim] if node and shim else [bin_]
template = {'type': 'local', 'command': cmd + ['serve', '--mcp'], 'disabled': False}
existing = nested if nested is not missing else legacy
updated = managed(None if existing is missing else existing, template)
if existing is not missing and existing == updated:
    print('unchanged: mcp.codegraph')
    raise SystemExit(0)
if jsonc_blocks_write(jsonc_cfg):
    print('WARN: codegraph 位于 opencode.jsonc 或受其空值覆盖，保留两个文件；请先运行 opencode-setup.sh 归一化，再注册 MCP', file=sys.stderr)
    raise SystemExit(0)
if p.exists():
    backup = p.with_name(p.name + '.bak-codegraph-' + datetime.datetime.now().strftime('%Y%m%d%H%M%S'))
    shutil.copy2(p, backup)
    print(f'backup: {backup}')
mcp = json_cfg.setdefault('mcp', {})
if legacy is not missing:
    mcp['codegraph'] = updated
else:
    mcp.setdefault('servers', {})['codegraph'] = updated
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(json_cfg, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(f'updated: mcp.codegraph -> {p}')
PY
    ;;
  codex)
    if codex mcp list 2>/dev/null | grep -qE '^codegraph([[:space:]:]|$)'; then
      echo "unchanged: codex MCP codegraph 已存在"
      exit 0
    fi
    echo "== 注册 codex MCP =="
    codex mcp add codegraph -- "$(native "$cg")" serve --mcp || { echo "WARN: CodeGraph MCP 注册失败" >&2; exit 1; }
    ;;
  antigravity)
    if [ "${AGENT_SKILLS_NO_CONFIG_WRITE:-0}" = 1 ]; then
      echo "跳过: 本次计划未写入配置，不登记 codegraph MCP 条目（CLI 已就绪，可重跑 setup 或手工添加）"
      exit 0
    fi
    here="$(cd "$(dirname "$0")/../.." && pwd)"
    python3 "$here/scripts/migrate-agents-tail.py" --antigravity-mcp
    ;;
  *)
    echo "MCP 条目由该宿主的配置模板提供，这里只装 CLI"
    ;;
esac
