#!/usr/bin/env bash
# module: codegraph
# desc: 代码知识图谱 CLI + MCP 注册（需 codegraph init 才有索引）
# default: Y
# hosts: pi,opencode,codex
#
# CLI 本体宿主无关；MCP 注册按宿主分开：opencode 写 opencode.json，codex 用 codex mcp add，
# Pi 的 mcp.json 由 dot_file 模板提供条目，不需要在这里写。
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
    cfgdir="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
    cfg="$cfgdir/opencode.json"
    if grep -qs '"codegraph"' "$cfg" "$cfgdir/opencode.jsonc" 2>/dev/null; then
      echo "unchanged: codegraph MCP 条目已存在"
      exit 0
    fi
    node_bin=""; shim=""
    if [ "$IS_WIN" = 1 ] && command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
      _js="$(npm root -g 2>/dev/null)/@colbymchenry/codegraph/npm-shim.js"
      [ -f "$_js" ] && { node_bin="$(native "$(command -v node)")"; shim="$(native "$_js")"; }
    fi
    echo "== 写入 codegraph MCP 条目 =="
    python3 - "$cfg" "$(native "$cg")" "$node_bin" "$shim" <<'PY'
import json, sys
path, bin_, node, shim = sys.argv[1:5]
try:
    with open(path) as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {"$schema": "https://opencode.ai/config.json"}
except FileNotFoundError:
    cfg = {"$schema": "https://opencode.ai/config.json"}
servers = cfg.setdefault("mcp", {}).setdefault("servers", {})
if "codegraph" in servers:
    print("unchanged: codegraph MCP 条目已存在")
    raise SystemExit(0)
cmd = [node, shim] if node and shim else [bin_]
servers["codegraph"] = {"type": "local", "command": cmd + ["serve", "--mcp"], "disabled": False}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"added: mcp.codegraph -> {path}")
PY
    ;;
  codex)
    if codex mcp list 2>/dev/null | grep -q '^codegraph'; then
      echo "unchanged: codex MCP codegraph 已存在"
      exit 0
    fi
    echo "== 注册 codex MCP =="
    codex mcp add codegraph -- "$(native "$cg")" serve --mcp || { echo "WARN: CodeGraph MCP 注册失败" >&2; exit 1; }
    ;;
  *)
    echo "MCP 条目由该宿主的配置模板提供，这里只装 CLI"
    ;;
esac
