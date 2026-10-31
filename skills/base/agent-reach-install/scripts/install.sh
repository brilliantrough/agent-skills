#!/usr/bin/env bash
# agent-reach 官方 CLI 安装器。只装上游官方包，不打任何补丁。
# 由 pi-setup.sh / opencode-setup.sh 在 skills 同步后调用；也可手工执行。
# 幂等：已安装则只报告版本并退出，不重装、不动 ~/.agent-reach 里的配置与登录态。
set -euo pipefail

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# uv 把可执行文件放在 ~/.local/bin；非交互 shell 常不在 PATH 里，先补上再判断，
# 否则已安装也会被当成未安装而重装。
export PATH="$HOME/.local/bin:$PATH"

note() { printf '%s\n' "$*"; }
ok()   { printf '   ok   %s\n' "$*"; }
warn() { printf '   warn %s\n' "$*" >&2; }

UV_BIN="$(command -v uv 2>/dev/null || true)"
[ -n "$UV_BIN" ] || UV_BIN="$HOME/.local/bin/uv"

if ! command -v agent-reach >/dev/null 2>&1; then
  if [ "$CHECK" = 1 ]; then
    note "agent-reach: 未安装（将安装官方包并执行 agent-reach setup）"
    exit 0
  fi
  if [ ! -x "$UV_BIN" ]; then
    warn "未检测到 uv，跳过 agent-reach 安装；装好 uv 后重跑即可"
    exit 0
  fi
  note "== agent-reach: 安装官方包 =="
  "$UV_BIN" tool install --python 3.12 \
    https://github.com/Panniantong/Agent-Reach/releases/latest/download/agent-reach.zip
  export PATH="$HOME/.local/bin:$PATH"
  note "== agent-reach: setup（默认渠道 + 官方 skill + 无头浏览器）=="
  agent-reach setup || warn "setup 未完全成功，可稍后执行 agent-reach setup 重试"
  note "== agent-reach: 安装 X / 小红书所需的官方工具（Node/OpenCLI）=="
  agent-reach add twitter >/dev/null 2>&1 || warn "add twitter 未完全成功，可稍后重试"
  agent-reach add xiaohongshu >/dev/null 2>&1 || warn "add xiaohongshu 未完全成功，可稍后重试"
fi

export PATH="$HOME/.local/bin:$PATH"
if command -v agent-reach >/dev/null 2>&1; then
  ok "agent-reach 已就绪（$(agent-reach version 2>/dev/null | head -c 120 || echo version unknown)）"
else
  warn "agent-reach 仍不在 PATH 中，请检查 ~/.local/bin 是否加入 PATH"
  exit 1
fi

# ---- X 凭据（可选；真实值绝不进仓库）----
# 来源优先级：环境变量 X_AUTH_TOKEN/X_CT0 > 本地私密文件
#   ~/.config/agent-reach/x-cookies.env  （0600，两行 X_AUTH_TOKEN=... / X_CT0=...）
# config.yaml 已有凭据时不覆盖；浏览器 cookie 每次都会确保注入（opencli 后端读浏览器）。
seed_x_credentials() {
  local token="${X_AUTH_TOKEN:-}" ct0="${X_CT0:-}" src="环境变量"
  local secret="$HOME/.config/agent-reach/x-cookies.env"
  if [ -z "$token" ] || [ -z "$ct0" ]; then
    if [ -f "$secret" ]; then
      # shellcheck disable=SC1090
      . "$secret"
      token="${X_AUTH_TOKEN:-}"; ct0="${X_CT0:-}"; src="$secret"
    fi
  fi
  if [ -z "$token" ] || [ -z "$ct0" ]; then
    note "   提示: 未提供 X 凭据，跳过（需要时设 X_AUTH_TOKEN/X_CT0，或写 $secret）"
    return 0
  fi
  local cfg="$HOME/.agent-reach/config.yaml"
  if [ -f "$cfg" ] && grep -q '^twitter_auth_token: .' "$cfg" && grep -q '^twitter_ct0: .' "$cfg"; then
    ok "X 凭据已存在，保留不覆盖"
  else
    [ "$CHECK" = 1 ] && { note "X 凭据: 将从 $src 写入 $cfg"; return 0; }
    mkdir -p "$(dirname "$cfg")"
    python3 - "$cfg" "$token" "$ct0" <<'PY'
import sys
path, token, ct0 = sys.argv[1:4]
lines = []
try:
    lines = open(path, encoding='utf-8').read().splitlines()
except FileNotFoundError:
    pass
out, seen = [], set()
for line in lines:
    key = line.split(':', 1)[0].strip()
    if key == 'twitter_auth_token':
        out.append(f'twitter_auth_token: {token}'); seen.add(key)
    elif key == 'twitter_ct0':
        out.append(f'twitter_ct0: {ct0}'); seen.add(key)
    else:
        out.append(line)
if 'twitter_auth_token' not in seen:
    out.append(f'twitter_auth_token: {token}')
if 'twitter_ct0' not in seen:
    out.append(f'twitter_ct0: {ct0}')
open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY
    chmod 600 "$cfg"
    ok "X 凭据已写入 $cfg（来源: $src，权限 600）"
  fi

  # opencli 后端从浏览器 cookie 取 ct0，仅写 config.yaml 不够，必须注入浏览器
  [ "$CHECK" = 1 ] && return 0
  local tmp
  tmp="$(mktemp)"
  python3 - "$tmp" "$token" "$ct0" <<'PY'
import json
import sys
path, token, ct0 = sys.argv[1:4]
json.dump([
    {"name": "auth_token", "value": token, "domain": ".x.com", "path": "/",
     "secure": True, "httpOnly": True},
    {"name": "ct0", "value": ct0, "domain": ".x.com", "path": "/", "secure": True},
], open(path, 'w'))
PY
  bash "$(dirname "$0")/inject-cookies.sh" "$tmp" || warn "X cookie 注入失败，可稍后重试"
  rm -f "$tmp"
}
seed_x_credentials

# ---- 小红书 cookie（可选；注入官方无头浏览器，不改上游查询逻辑）----
XHS_FILE="${XHS_COOKIE:-$HOME/.config/agent-reach/xhs-cookies.json}"
if [ -f "$XHS_FILE" ]; then
  if [ "$CHECK" = 1 ]; then
    note "小红书 cookie: 将从 $XHS_FILE 注入 Reach 浏览器"
  else
    bash "$(dirname "$0")/inject-cookies.sh" "$XHS_FILE" \
      || warn "小红书 cookie 注入失败，可稍后重试"
  fi
else
  note "   提示: 未提供小红书 cookie（需要时写 $XHS_FILE 或设 XHS_COOKIE）"
fi
