#!/usr/bin/env bash
# setup.sh — 同步上游 context-mode，并叠加我们的三层改动（幂等，可重复跑）
#
# 三层分工（为什么不是一堆 .patch）：
#   A. 行为补丁  patches/0001-*.patch        —— 真代码改动，构建前 git apply。
#      它必须是 diff：语义改动只有 diff 看得清「改了什么」。代价是行级锚点，上游动了这段会打不上，
#      脚本会停下并打印恢复步骤（见下面的 apply_patches）。
#   B. 锚定改写  fork-patches.mjs            —— 升级口径 / 工具描述压缩 / skill 补充，构建前。
#      这三类落在上游最爱改的文件上（server.ts、extension.ts、SKILL.md），锚点是我们关心的
#      工具名与标题，所以上游往上往下挪几十行都不失效；上游真改了锚点就大声失败。
#   C. 改名     rename-ctx-tools.mjs         —— 构建后，给 11 个工具加前缀，避开 magic-context 的 ctx_search。
#      面很宽（900+ 处，散落在描述/路由块/skill 正文），做成补丁必与上游文案冲突，所以锚在产物上做。
#   另外：剪掉上游的 skills/ctx-upgrade（它教模型去跑会抹掉改名的升级）。
#
# 顺序不能变：A → B →（bun install + build）→ C → verify.mjs
#   B 改的是 src/ 与 skills/ 源文件，必须在构建前；C 打的是构建产物，必须在构建后。
#
# 用法:
#   bash context-mode/setup.sh              # 同步 + 构建 + 三层改动 + 体检
#   bash context-mode/setup.sh --install    # 顺带幂等 pi install
#   bash context-mode/setup.sh --verify     # 只体检当前这棵树（不动上游、不构建）
#
# 注意：永远不要调 ctxm_upgrade（原 ctx_upgrade）——它会从 GitHub 覆盖成纯上游。升级只走本脚本。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CONTEXT_MODE_DIR:-$HOME/Linewrite/forks/context-mode}"
PREFIX="${CONTEXT_MODE_PREFIX:-ctxm_}"
PATCHDIR="$HERE/patches"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
DO_INSTALL=0
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) DO_INSTALL=1; shift ;;
    --verify) VERIFY_ONLY=1; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done
export CONTEXT_MODE_PREFIX="$PREFIX"

for c in git bun node npm; do command -v "$c" >/dev/null || { echo "缺少 $c" >&2; exit 1; }; done
[[ -d "$REPO/.git" ]] || { echo "不是 git clone: $REPO" >&2; exit 1; }

# ── 只体检 ────────────────────────────────────────────────────────────────────
if [[ "$VERIFY_ONLY" == "1" ]]; then
  echo "[context-mode] 体检 $REPO（锚定改写的 --check 只报不改）"
  node "$HERE/fork-patches.mjs" "$REPO" --check || echo "（--check 报告了需要改的地方，跑不带 --verify 的本脚本即会应用）"
  node "$HERE/verify.mjs" "$REPO"
  exit $?
fi

# ── 1. 回到纯上游并快进（我们从不 commit 到上游文件，所以 pull 永远快进） ──────
cd "$REPO"
git checkout -- .
git pull --ff-only
echo "[context-mode] 上游版本: $(node -p "require('./package.json').version") ($(git rev-parse --short HEAD))"

# ── 2. A 层：行为补丁（构建前） ───────────────────────────────────────────────
apply_patches() {
  shopt -s nullglob
  for p in "$PATCHDIR"/*.patch; do
    echo "[context-mode] 应用 $(basename "$p")"
    if ! git apply "$p"; then
      cat >&2 <<MSG

[context-mode] 行为补丁打不上 —— 上游改了这段代码，不是脚本坏了。恢复步骤：
  1. 上面 git 报的行号 = 冲突位置；打开那个补丁里对应的 @@ 块，读它顶部的注释（意图都写在注释里）。
  2. 打开 $REPO 里同一处的新代码，用同样的语义把改动重做一遍（只改必要行，上下文越少越好）。
  3. 用 "git -C $REPO diff -- 文件路径" 生成新补丁覆盖旧的，再重跑本脚本。
  4. 只有「名字/文案级」的替换才适合挪进 fork-patches.mjs；真正的语义改动留在 diff 里。
MSG
      exit 1
    fi
  done
  shopt -u nullglob
}
apply_patches

# ── 2b. 剪掉有害的上游 skill（rm 比删文件补丁稳：删文件 hunk 要带整份旧内容） ──
rm -rf "$REPO/skills/ctx-upgrade"

# ── 2c. B 层：锚定改写（构建前，改 src/ 与 skills/ 源文件） ────────────────────
node "$HERE/fork-patches.mjs" "$REPO"

# ── 3. 构建（产物 gitignore，必须本地构建） ───────────────────────────────────
#     用 bun 而不是 npm：仓库带的是 bun.lock，且 npm 10 解析 vitest 的 peer 图会崩
#     （arborist "Cannot read properties of null (reading 'edgesOut')"）。
bun install --frozen-lockfile || bun install
bun run build

# ── 4. C 层：改名（构建后，所以 assert-bundle / assert-asymmetric-drift 都已跑过） ──
node "$HERE/rename-ctx-tools.mjs" "$REPO" "$PREFIX"

# ── 5. 体检：三层改动是不是真的都落在树上（含拉起 MCP 子进程问工具表） ────────
node "$HERE/verify.mjs" "$REPO"

# ── 6. 安装提示（幂等） ───────────────────────────────────────────────────────
if [[ "$DO_INSTALL" == "1" ]]; then
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
