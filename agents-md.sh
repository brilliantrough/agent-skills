#!/usr/bin/env bash
# agents-md.sh — 把 AGENTS.tail.md 里的 memory-system 块写进项目 AGENTS.md 尾部（幂等）。
#
# 用法: bash agents-md.sh [目标文件] [--source <本地 AGENTS.tail.md>] [--raw <仓库 raw 基址>]
#   目标文件默认 $PWD/AGENTS.md。
#   源优先级: --source（须含 memory-system 标记）→ 脚本同目录的 AGENTS.tail.md → 下载 <raw>/AGENTS.tail.md
#
# 幂等语义: 已是同一块 → 不动；有旧块 → 原位替换该块；没有 → 追加到文件末尾。
#   只改这一个标记块，文件其余内容（含结尾的其它规范）原样保留。
#
# 顺序: 必须在宿主安装与配置合并之后执行。本脚本只写项目 AGENTS.md，不碰宿主配置，
#   但官方安装器（如 claude-mem install）会重写自己的 settings；任何"装完再合并配置"的步骤都不要插到它后面。
set -euo pipefail

TARGET=""
SOURCE=""
RAW="${AGENT_SKILLS_RAW:-https://raw.githubusercontent.com/brilliantrough/agent-skills/main}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) SOURCE="${2:-}"; shift 2 ;;
    --raw) RAW="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) TARGET="$1"; shift ;;
  esac
done
TARGET="${TARGET:-$PWD/AGENTS.md}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# ---- 取源：显式 > 本地同目录 > 下载 ----
src_ok=0
if [ -n "$SOURCE" ] && [ -f "$SOURCE" ] && grep -q '<!-- memory-system:start -->' "$SOURCE"; then
  cp "$SOURCE" "$tmp" && src_ok=1
fi
if [ "$src_ok" = 0 ]; then
  here="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
  if [ -n "$here" ] && [ -f "$here/AGENTS.tail.md" ] && [ "$here/AGENTS.tail.md" != "$TARGET" ] \
     && grep -q '<!-- memory-system:start -->' "$here/AGENTS.tail.md"; then
    cp "$here/AGENTS.tail.md" "$tmp" && src_ok=1
  fi
fi
if [ "$src_ok" = 0 ]; then
  if curl -fsSL --connect-timeout 8 -m 60 -o "$tmp" "$RAW/AGENTS.tail.md" 2>/dev/null \
     && grep -q '<!-- memory-system:start -->' "$tmp"; then
    src_ok=1
  fi
fi
[ "$src_ok" = 1 ] || { echo "ERROR: 取不到 AGENTS.tail.md（本地不存在且下载失败）" >&2; exit 1; }

# ---- 写入（同一块不动、旧块替换、无块追加）----
python3 - "$tmp" "$TARGET" <<'PY'
import pathlib, re, sys

src = pathlib.Path(sys.argv[1]).read_text(encoding="utf8")
m = re.search(r"<!-- memory-system:start -->.*?<!-- memory-system:end -->", src, re.S)
if not m:
    sys.exit("取到的源文件里找不到 memory-system 块")
block = m.group(0)

p = pathlib.Path(sys.argv[2])
old = p.read_text(encoding="utf8") if p.exists() else ""
cur = re.search(r"<!-- memory-system:start -->.*?<!-- memory-system:end -->", old, re.S)
if cur and cur.group(0) == block:
    print("已是最新: " + str(p))
    raise SystemExit(0)
new = (old[:cur.start()] + block + old[cur.end():]) if cur else (old.rstrip("\n") + "\n\n" + block + "\n" if old else block + "\n")
p.write_text(new, encoding="utf8")
print(("已更新: " if cur else "已追加: ") + str(p))
PY
