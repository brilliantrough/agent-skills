#!/usr/bin/env bash
# module: agent-reach
# desc: 官方只读检索 CLI + 无头浏览器(小红书/Reddit/X/YouTube 等;体积较大)
# default: N
# hosts: any
#
# 安装器随 base 组的 agent-reach-install skill 落到 ~/.agents/skills。
# 已装则跳过，不触碰 ~/.agent-reach 里的 X token 与浏览器登录态。
# 卸载: agent-reach --version 确认来源后 `uv tool uninstall agent-reach`；cookie 在各配置文件里，按需删。
set -euo pipefail

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) shift 2 ;;          # 宿主无关:四个宿主都只是调 bash
    --yes|-y) shift ;;
    *) shift ;;
  esac
done

if command -v agent-reach >/dev/null 2>&1 || [ -x "$HOME/.local/bin/agent-reach" ]; then
  echo "agent-reach 已存在，跳过（升级： agent-reach update）"
  exit 0
fi

installer="$HOME/.agents/skills/agent-reach-install/scripts/install.sh"
if [ ! -f "$installer" ]; then
  echo "ERROR: 缺少 $installer（base 组的 agent-reach-install skill 未安装）" >&2
  exit 1
fi
bash "$installer"
