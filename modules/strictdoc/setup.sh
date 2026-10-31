#!/usr/bin/env bash
# module: strictdoc
# desc: StrictDoc .sdoc 文档校验工具（uv 全局安装，固定版本）
# default: Y
# hosts: any
#
# 只有 .sdoc 校验需要它；没装 uv 时跳过并提示，不自行安装 uv（那是各 setup 的依赖步骤）。
# 升级: uv tool upgrade strictdoc；卸载: uv tool uninstall strictdoc
set -euo pipefail

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) shift 2 ;;          # 宿主无关
    --yes|-y) shift ;;
    *) shift ;;
  esac
done

VERSION="0.28.1"
BIN_EXT=""
case "$(uname -s 2>/dev/null || echo unknown)" in MINGW*|MSYS*|CYGWIN*) BIN_EXT=".exe" ;; esac

if command -v strictdoc >/dev/null 2>&1; then
  echo "strictdoc 已存在，跳过（升级： uv tool upgrade strictdoc）"
  exit 0
fi

uv="$(command -v uv 2>/dev/null || true)"
[ -n "$uv" ] || uv="$HOME/.local/bin/uv$BIN_EXT"
if [ ! -x "$uv" ]; then
  echo "提示: 未检测到 uv，跳过 strictdoc 安装（.sdoc 校验依赖）；装好 uv 后重跑本脚本即可"
  exit 0
fi

echo "== strictdoc =="
"$uv" tool install "strictdoc==$VERSION"
