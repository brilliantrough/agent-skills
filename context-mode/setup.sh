#!/usr/bin/env bash
# setup.sh — 同步上游 context-mode，并叠加我们的两层改动
#
# 干什么（幂等，可重复跑）：
#   1. 缺 clone 就 clone，已有就 `git checkout -- .` + `git pull --ff-only`
#      —— 我们从不往上游文件上 commit，两步改动都是「用的时候现打」，所以 pull 永远快进
#   2. 行为补丁（patches/*.patch，源码级，构建前）：git apply 锚点不符就报错停下
#   3. bun install + bun run build（产物 build/ 与 *.bundle.mjs 上游 gitignore，必须本地构建）
#   4. 改名补丁（rename-ctx-tools.mjs，构建后）：给 11 个工具名加前缀，避开 magic-context 的 ctx_search
#   5. 打印 pi install 命令（--install 才真装）
#
# 为什么分两层：
#   * 改名是机械且面很宽的（900+ 处，散落在工具描述/路由块/skill 正文），做成源码补丁会跟上游文案
#     改动反复冲突，所以放在构建之后的产物上做。
#   * 行为改动（bugfix）行数少、位置精确，做成 patches/*.patch 用 git apply 打，锚点变了会立刻报错，
#     既不会静默失效，也不会因为"构建后改名"那一步把源码改动冲掉。
#
# 注意：永远不要调 ctxm_upgrade（原 ctx_upgrade）——它会自己从 GitHub 覆盖成纯上游。
#       升级只走本脚本。
#
# 用法: bash context-mode/setup.sh [--install] [--prefix ctxm_]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CONTEXT_MODE_DIR:-$HOME/Linewrite/forks/context-mode}"
PREFIX="${CONTEXT_MODE_PREFIX:-ctxm_}"
RENAME="$HERE/rename-ctx-tools.mjs"
PATCHDIR="$HERE/patches"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
DO_INSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) DO_INSTALL=1; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

for c in git bun node npm; do command -v "$c" >/dev/null || { echo "缺少 $c" >&2; exit 1; }; done

# 1. 回到纯上游并快进
if [[ -d "$REPO/.git" ]]; then
  cd "$REPO"
  git checkout -- .                       # 丢弃上一次的改动（源码补丁 + 改名补丁）
  git pull --ff-only
else
  mkdir -p "$(dirname "$REPO")"
  git clone https://github.com/mksglu/context-mode.git "$REPO"
  cd "$REPO"
fi
echo "[context-mode] 上游版本: $(node -p "require('./package.json').version") ($(git rev-parse --short HEAD))"

# 2. 行为补丁（构建前，源码级）
shopt -s nullglob
for p in "$PATCHDIR"/*.patch; do
  echo "[context-mode] 应用 $(basename "$p")"
  git apply "$p"                        # 锚点不符 → git 报错 + set -e 中止
done
shopt -u nullglob

# 2b. 剪掉对本机有害的上游 skill：ctx-upgrade 教模型「从 GitHub 拉最新版重装」，那会抹掉改名补丁
#     （ctx_search 立刻和 magic-context 撞名）。整目录丢弃用 rm 比用 patch 更稳——patch 的删文件
#     hunk 要带整份旧文件内容，上游一改就冲突。
rm -rf "$REPO/skills/ctx-upgrade"

# 3. 构建（产物 gitignore，必须本地构建）
#    用 bun 而不是 npm：仓库带的是 bun.lock，且 npm 10 解析 vitest 的 peer 图会崩
#    （arborist "Cannot read properties of null (reading 'edgesOut')"）。
bun install --frozen-lockfile || bun install
bun run build

# 4. 改名（构建之后，所以 assert-bundle / assert-asymmetric-drift 都已经跑过了）
node "$RENAME" "$REPO" "$PREFIX"

# 5. 安装提示
if [[ "$DO_INSTALL" == "1" ]]; then
  # 幂等：settings.json 里已有这个路径就别重复写
  if node -e '
    const fs=require("fs"),p=process.argv[1];
    if(!fs.existsSync(p))process.exit(1);
    process.exit((JSON.parse(fs.readFileSync(p,"utf8")).packages??[]).some(s=>s.includes("forks/context-mode"))?0:1)
  ' "$AGENT_DIR/settings.json"; then
    echo "[context-mode] 已在 $AGENT_DIR/settings.json，跳过 pi install"
  else
    read -r -p "把 $REPO 加进 Pi 包列表(pi install)？[Y/n] " a
    [[ "${a:-Y}" =~ ^[Yy]$|^$ ]] && pi install "$REPO" || echo "跳过。手动安装: pi install $REPO"
  fi
else
  echo "[context-mode] 装进 Pi: pi install $REPO"
fi

echo "[context-mode] 完成。重启 Pi 生效（本地路径安装，改动无需重装）。"
