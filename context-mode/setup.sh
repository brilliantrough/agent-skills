#!/usr/bin/env bash
# setup.sh — 固定上游版本，应用 fork 补丁，构建、改名、打包并验证。
#   bash context-mode/setup.sh              # 构建候选包，不发布、不安装
#   bash context-mode/setup.sh --publish    # 验证后发布 GitHub release
#   bash context-mode/setup.sh --verify     # 只验证当前源码与候选包
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_VERSION=2.2.1
WORK="${CONTEXT_MODE_DIR:-$HERE/.work/v$UPSTREAM_VERSION}"
SRC="$WORK/source"
DO_PUBLISH=0
VERIFY_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish|--install) DO_PUBLISH=1; shift ;;
    --verify) VERIFY_ONLY=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
for cmd in node bun curl tar python3; do command -v "$cmd" >/dev/null || { echo "缺少 $cmd" >&2; exit 1; }; done
node -e 'const [a,b]=process.versions.node.split(".").map(Number);if(a<24||a===24&&b<15)throw new Error(`context-mode v2 需要 Node >=24.15，当前 ${process.version}`)'

if [[ "$VERIFY_ONLY" == 1 ]]; then
  node "$HERE/verify.mjs" "$SRC"
  exit $?
fi

mkdir -p "$WORK"
echo "[context-mode] 下载固定上游 v$UPSTREAM_VERSION"
curl -fsSL --connect-timeout 8 -m 120 "https://github.com/mksglu/context-mode/archive/refs/tags/v$UPSTREAM_VERSION.tar.gz" -o "$WORK/source.tar.gz"
rm -rf "$SRC"
mkdir -p "$SRC"
tar -xzf "$WORK/source.tar.gz" -C "$SRC" --strip-components=1

echo "[context-mode] 安装 bun.lock 锁定的构建依赖"
(cd "$SRC" && bun install --frozen-lockfile)

echo "[context-mode] A/B：行为与提示补丁"
node "$HERE/fork-patches.mjs" "$SRC"

echo "[context-mode] 官方自包含构建"
node "$SRC/build/build.mjs" --out "$SRC/release-out" --version "$UPSTREAM_VERSION"

echo "[context-mode] C：统一 ctxm_* 工具名"
node "$HERE/rename-ctx-tools.mjs" "$SRC/release-out"

echo "[context-mode] D：打包两个兼容资产"
node "$HERE/release.mjs" "$SRC"

echo "[context-mode] 真实加载与行为验证"
node "$HERE/verify.mjs" "$SRC"

if [[ "$DO_PUBLISH" == 1 ]]; then
  command -v gh >/dev/null || { echo "缺少 gh，不能发布" >&2; exit 1; }
  gh auth status >/dev/null
  node "$HERE/release.mjs" "$SRC" --publish
else
  echo "[context-mode] 候选包已就绪：context-mode/dist/；未发布、未安装、未重启宿主"
fi
