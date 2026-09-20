#!/usr/bin/env bash
# setup.sh — 同步上游 context-mode，叠加本仓库的三层改动，打包后体检（幂等，可重复跑）
#
#   bash context-mode/setup.sh              # 同步 + 构建 + 三层改动 + 打包 + 体检
#   bash context-mode/setup.sh --publish    # 顺带发 GitHub release（目标机靠它拿新版）
#   bash context-mode/setup.sh --install    # 同 --publish（别名）
#   bash context-mode/setup.sh --verify     # 只体检（不动上游、不构建、不打包）
#
# 顺序：A 补丁 → B 锚定改写 → 构建 → C 改名 → D 打包 → 体检（B 在构建前，C/D 在构建后）。
# 环境变量：CONTEXT_MODE_DIR（clone 位置）、CONTEXT_MODE_PREFIX（工具名前缀，默认 ctxm_）。
# 没有 clone（首次运行或 clone 被删）会自动 clone 上游到 CONTEXT_MODE_DIR 下的路径。
# 不要调 ctxm_upgrade —— 它会从 GitHub 覆盖成纯上游。

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
    --install) DO_PUBLISH=1; shift ;;
    --verify) VERIFY_ONLY=1; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done
export CONTEXT_MODE_PREFIX="$PREFIX"

for c in git bun node npm; do command -v "$c" >/dev/null || { echo "缺少 $c" >&2; exit 1; }; done
UPSTREAM_URL="https://github.com/mksglu/context-mode"
if [[ ! -d "$REPO/.git" ]]; then
  echo "[context-mode] 没有 clone，从上游拉一份 → $REPO"
  mkdir -p "$(dirname "$REPO")"
  git clone "$UPSTREAM_URL" "$REPO" || { echo "clone 失败: $UPSTREAM_URL（目录非空或网络不通）" >&2; exit 1; }
fi

# ── 只体检 ────────────────────────────────────────────────────────────────────
if [[ "$VERIFY_ONLY" == "1" ]]; then
  echo "[context-mode] 体检 $REPO（锚定改写的 --check 只报不改）"
  node "$HERE/fork-patches.mjs" "$REPO" --check || echo "（--check 报告了需要改的地方，跑不带 --verify 的本脚本即会应用）"
  node "$HERE/verify.mjs" "$REPO"
  exit $?
fi

# ── 1. 回到纯上游并快进 ─────────────────────────────────────────────────
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

# ── 2b. 剪掉上游的 ctx-upgrade skill（它教模型去跑会抹掉改名的升级） ──────
rm -rf "$REPO/skills/ctx-upgrade"

# ── 2c. B 层：锚定改写（构建前，改 src/ 与 skills/ 源文件） ────────────────────
node "$HERE/fork-patches.mjs" "$REPO"

# ── 3. 构建（用 bun：仓库只带 bun.lock） ─────────────────────────────────
bun install --frozen-lockfile || bun install
bun run build

# ── 4. C 层：改名（构建后） ────────────────────────────────────────────────
node "$HERE/rename-ctx-tools.mjs" "$REPO" "$PREFIX"

# ── 5. D 层：打包（--publish 才发 release） ───────────────────────────────
node "$HERE/release.mjs" "$REPO"
if [[ "$DO_PUBLISH" == "1" ]]; then
  node "$HERE/release.mjs" "$REPO" --publish
fi

# ── 6. 体检（会解开 tar 包并拉起包内 MCP 子进程问一次工具表） ──────────────
node "$HERE/verify.mjs" "$REPO"

# ── 7. 目标机安装提示；release 副本与 clone 路径不能同时登记 ─────────────────
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
