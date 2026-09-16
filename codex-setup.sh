#!/usr/bin/env bash
# codex-setup.sh — Codex 插件配置(best effort;本仓库仍以 OpenCode 为主)
# 0. 检查 Codex >=0.128.0 及插件命令、Python 3.11+、网络;不安装/升级 Codex 本体
# 1. 缺失时询问安装 Node LTS、Bun、uv;可选安装 strictdoc==0.28.1
# 2. claude-mem:优先复用本机 runtime;缺失时运行官方 codex-cli 安装器
#    安装器会修改共享配置并停止 worker;恢复 settings.json/原 Codex 配置,再原生注册
# 3. 原生安装 Ponytail;注册 CodeGraph MCP;安装缺失的本仓库 skills(不修改内容)
# 4. 提示 /hooks 信任和 /mcp 检查;Magic Context、notify 不安装,原生压缩不变
# 已配置项不重写、不自动升级;冲突/显式禁用项保留;修改前备份,不碰模型/认证配置
# 用法:bash codex-setup.sh;支持 CODEX_HOME(首次 claude-mem 官方安装仅支持默认路径)
set -euo pipefail

CFG="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CFG/config.toml"
MEM_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/thedotmack"
SETTINGS="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json"
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
errors=0

ask() {
  local a="" def="${2:-N}" hint="y/N"
  [ "$def" = Y ] && hint="Y/n"
  if { true < /dev/tty; } 2>/dev/null && read -r -p "$1 [$hint] " a < /dev/tty; then
    if [ -z "$a" ]; then [ "$def" = Y ]; else [[ "$a" =~ ^[Yy]$ ]]; fi
  else
    echo "$1 [$hint] (非交互,默认 $def)"
    [ "$def" = Y ]
  fi
}
warn() { echo "WARN: $*" >&2; errors=$((errors + 1)); }
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
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "20"
}
JSON
      )
      echo "wrote: $SETTINGS;使用前请填写占位符"
    else mem_ok=0; fi
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
for s in grilling grill-with-docs domain-modeling tdd diagnosing-bugs code-review load-mem save-mem migrate-mem plan-brief quick-do personal-ui-taste; do
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
echo "3. claude-mem 后端配置: $SETTINGS;如刚运行安装器,填好配置后执行 npx claude-mem@latest start。"
echo '4. 新项目执行 codegraph init;已有项目索引可复用。'
echo '5. skills 原样复用;缺少 Magic Context 的 ctx_* 工具时仅 best effort,以 OpenCode 为主。'
echo '6. 本脚本不升级已有插件/skills;更新方法见 README 的 Codex 一节。'
if [ "$errors" != 0 ]; then
  echo "WARN: $errors 项未完成,请检查上方输出后重跑" >&2
  exit 1
fi
