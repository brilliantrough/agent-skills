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
#   D. 发布     release.mjs                  —— 构建后，把 Pi 需要的那份产物打成 tar.gz 发到 GitHub release。
#      为什么不进 git：这是编译产物（~1.4M），diff 无人 review；目标是「目标机一键拿到我们维护的插件」。
#      包里带生成的 package.json（Pi 靠它的 pi.extensions/pi.skills 加载）+ LICENSE(Elastic-2.0) + VENDORED.json。
#   另外：剪掉上游的 skills/ctx-upgrade（它教模型去跑会抹掉改名的升级）。
#
# 顺序不能变：A → B →（bun install + build）→ C → D 打包 → verify.mjs
#   B 改的是 src/ 与 skills/ 源文件，必须在构建前；C 打的是构建产物，必须在构建后。
#
# 用法:
#   bash context-mode/setup.sh              # 同步 + 构建 + 三层改动 + 打包 + 体检
#   bash context-mode/setup.sh --publish    # 顺带 gh release create（目标机靠它拿新版）
#   bash context-mode/setup.sh --verify     # 只体检（不动上游、不构建、不打包）
#
# 注意：永远不要调 ctxm_upgrade（原 ctx_upgrade）——它会从 GitHub 覆盖成纯上游。升级只走本脚本。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CONTEXT_MODE_DIR:-$HOME/Linewrite/forks/context-mode}"
PREFIX="${CONTEXT_MODE_PREFIX:-ctxm_}"
PATCHDIR="$HERE/patches"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
DO_PUBLISH=0
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish) DO_PUBLISH=1; shift ;;
    --install) DO_PUBLISH=1; shift ;; # 旧名，行为已变成「发布」
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

# ── 5. D 层：发布包（产物走 GitHub release，不进 git 历史） ──────────────────
#     目标机只需要下载这个 ~400K 的 tar 包：不需要 bun、不需要 clone、也不需知道上游。
node "$HERE/release.mjs" "$REPO"
if [[ "$DO_PUBLISH" == "1" ]]; then
  node "$HERE/release.mjs" "$REPO" --publish
fi

# ── 6. 体检：三层改动 + 发布包是不是真的都落在树上（解开 tar 包，拉起包内 MCP 子进程问工具表） ──
node "$HERE/verify.mjs" "$REPO"

# ── 7. 目标机怎么装（幂等）+ 两个副本不能同时登记 ───────────────────────────────
#     release 解出来的目录 与 本地 clone 路径 同时登记 → 两个扩展注册同名 ctxm_* 工具 → Pi 启动 exit 1。
python3 - "$AGENT_DIR/settings.json" "$AGENT_DIR" <<'PY'
import json, os, sys
try:
    pkgs = json.load(open(sys.argv[1], encoding="utf-8")).get("packages") or []
except Exception:
    pkgs = []
agent = sys.argv[2]
abs_of = lambda p: os.path.normpath(p if os.path.isabs(str(p)) else os.path.join(agent, str(p)))
stale = [abs_of(p) for p in pkgs if "context-mode" in str(p) and "vendor" not in str(p)]
installed = any("vendor/context-mode" in str(p) for p in pkgs)
print("[context-mode] 目标机安装/更新:")
print("  curl -fsSL https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz \\")
print("    | tar -xz -C ~/.pi/agent/vendor/context-mode && pi install ~/.pi/agent/vendor/context-mode")
print("[context-mode] 本机本发布包副本：" + ("已登记" if installed else "未登记（其它机器跑 pi-setup.sh 会自动装）"))
if stale:
    print("[context-mode] ⚠ 还登记着旧的 clone 路径：" + ", ".join(stale))
    print("[context-mode] ⚠ 它和发布包副本会同时注册 ctxm_* 工具，Pi 启动会 exit 1。摘掉一个（相对形式 pi remove 匹配不到，用绝对路径）：")
    print("  pi remove " + stale[0])
PY

echo "[context-mode] 完成。目标机重启 Pi 生效；本机改完 clone 后要 --publish 才能让其它机器拿到。"
