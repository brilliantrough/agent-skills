#!/usr/bin/env bash
# DeepSeek Harness 套件安装：独立 Node/运行目录，保留已有 profile、凭据与会话。
set -euo pipefail
RAW=https://raw.githubusercontent.com/brilliantrough/dot_file/master
SELF_RAW=https://raw.githubusercontent.com/brilliantrough/agent-skills/main
YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=1 ;;
    *) printf '用法：bash dsh-setup.sh [-y]\n' >&2; exit 2 ;;
  esac
done
ask() {
  local answer
  if [[ "$YES" == 1 ]]; then [[ "$2" == Y ]]; return; fi
  read -r -p "$1 [$2] " answer </dev/tty || answer=
  [[ "${answer:-$2}" =~ ^[Yy]$ ]]
}
for cmd in curl tar; do command -v "$cmd" >/dev/null || { printf '缺少依赖：%s\n' "$cmd" >&2; exit 1; }; done
ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/dsh"
mkdir -p "$ROOT"
NODE=""
for candidate in "$(command -v node 2>/dev/null || true)" "$ROOT/node/bin/node" "$HOME"/.local/share/fnm/node-versions/*/installation/bin/node; do
  if [[ -x "$candidate" ]] && "$candidate" -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>24||a===24&&b>=9?0:1)' 2>/dev/null; then
    NODE="$candidate"; break
  fi
done
if [[ -z "$NODE" ]]; then
  ask '为 dsh 安装独立 Node 24（不更改系统 Node）？' Y || exit 1
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) platform=linux-x64;; Linux-aarch64) platform=linux-arm64;;
    Darwin-x86_64) platform=darwin-x64;; Darwin-arm64) platform=darwin-arm64;;
    *) printf '请先安装 Node >=24.9，再运行本脚本。\n' >&2; exit 1;;
  esac
  node_tar=$(mktemp)
  curl -fsSL --connect-timeout 8 -m 180 "https://nodejs.org/dist/v24.21.0/node-v24.21.0-$platform.tar.gz" -o "$node_tar"
  mkdir -p "$ROOT/node"
  tar -xzf "$node_tar" -C "$ROOT/node" --strip-components=1
  rm -f "$node_tar"
  NODE="$ROOT/node/bin/node"
fi
NODE=$("$NODE" -p 'process.execPath')
export PATH="$(dirname "$NODE"):$PATH"
if [[ ! -f "${DSH_HOME:-$ROOT/home}/profiles/headless/cordis.patch.yml" ]]; then
  for route in claude-newapi codex-newapi anthropic-newapi gemini-newapi; do
    prefix=$(printf '%s' "$route" | tr 'a-z-' 'A-Z_')
    for field in BASE_URL API_KEY; do
      variable="${prefix}_${field}"
      [[ -z "${!variable:-}" ]] || continue
      if "$NODE" --input-type=module - "$route" "$field" <<'JS'
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
try {
  const config = JSON.parse(readFileSync(homedir() + '/.pi/agent/models.json', 'utf8'));
  const value = config.providers?.[process.argv[2]]?.[process.argv[3] === 'BASE_URL' ? 'baseUrl' : 'apiKey'];
  process.exit(typeof value === 'string' && value.length > 0 && !/<[^>]+>/.test(value) ? 0 : 1);
} catch { process.exit(1); }
JS
      then continue; fi
      if [[ "$YES" == 1 ]]; then printf '缺少 %s；可通过环境变量提供。\n' "$variable" >&2; exit 1; fi
      value=""
      if [[ "$field" == API_KEY ]]; then
        read -r -s -p "$route API Key（不回显）：" value </dev/tty
        printf '\n'
      else
        read -r -p "$route 网关 Base URL：" value </dev/tty
      fi
      [[ -n "$value" ]] || { printf '未填写 %s，停止安装。\n' "$variable" >&2; exit 1; }
      export "$variable=$value"
    done
  done
fi
if [[ ! -f "${DSH_HOME:-$ROOT/home}/.credentials.yaml" ]]; then
for route in zai-coding-cn kimi-coding; do
  variable="$(printf '%s' "$route" | tr 'a-z-' 'A-Z_')_API_KEY"
  [[ -z "${!variable:-}" ]] || continue
  if "$NODE" --input-type=module - "$route" <<'JS'
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
try {
  const auth = JSON.parse(readFileSync(homedir() + '/.pi/agent/auth.json', 'utf8'))[process.argv[2]];
  process.exit(auth?.type === 'api_key' && typeof auth.key === 'string' && auth.key.length > 0 && !/<[^>]+>/.test(auth.key) ? 0 : 1);
} catch { process.exit(1); }
JS
  then continue; fi
  if ask "填写 $route 的订阅密钥（也可稍后配置 $variable）？" N; then
    read -r -s -p "$route API Key（不回显）：" value </dev/tty
    printf '\n'
    [[ -z "$value" ]] || export "$variable=$value"
  fi
done
fi
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
curl -fsSL --connect-timeout 8 -m 120 https://github.com/brilliantrough/agent-skills/archive/refs/heads/main.tar.gz -o "$STAGE/suite.tar.gz"
tar -xzf "$STAGE/suite.tar.gz" -C "$STAGE"
SOURCE="$STAGE/agent-skills-main"
curl -fsSL --connect-timeout 8 -m 60 "$RAW/dsh/cordis.patch.json" -o "$STAGE/template.json"
curl -fsSL --connect-timeout 8 -m 120 https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz -o "$STAGE/context-mode.tar.gz"
mkdir -p "$STAGE/context-mode"
tar -xzf "$STAGE/context-mode.tar.gz" -C "$STAGE/context-mode"
curl -fsSL --connect-timeout 8 -m 120 https://github.com/wk544863858/dsh-plugin-magic-context/archive/bb581b4d99fda7608063596d69adb936b706d961.tar.gz -o "$STAGE/magic-context.tar.gz"
mkdir -p "$STAGE/magic-context"
tar -xzf "$STAGE/magic-context.tar.gz" -C "$STAGE/magic-context" --strip-components=1
args=(--root "$ROOT" --source "$SOURCE" --template "$STAGE/template.json" --contextMode "$STAGE/context-mode" --magicContext "$STAGE/magic-context")
claude_bundle="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/thedotmack/dsh"
if [[ -f "$claude_bundle/lib/index.js" ]]; then
  args+=(--claudeMem "$claude_bundle")
else
  printf '尚无官方 claude-mem 运行目录；先完成 dsh 安装，随后可用官方安装器接入。\n'
fi
[[ "$YES" != 1 ]] || args+=(--yes)
"$NODE" "$SOURCE/dsh/deploy.mjs" "${args[@]}"
"$ROOT/dsh" --version
"$ROOT/dsh" --dump-config --profile tui >/dev/null
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
if ask '同步基础 skills（base；复用 ~/.agents/skills）？' Y; then
  curl -fsSL --connect-timeout 8 -m 60 "$SELF_RAW/skills-sync.sh" -o "$STAGE/skills-sync.sh"
  bash "$STAGE/skills-sync.sh" base
fi
printf '\n安装完成。新终端运行 dsh tui；批处理运行 dsh --profile headless "任务"。\n'
if [[ ! -f "$claude_bundle/lib/index.js" ]]; then
  printf 'claude-mem 官方安装命令：DSH_HOME=%q npx -y claude-mem@latest install --ide dsh --dsh-profile tui --no-auto-start\n' "${DSH_HOME:-$ROOT/home}"
fi
