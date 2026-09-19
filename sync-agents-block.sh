#!/usr/bin/env bash
# 把本仓库 AGENTS.md 里的 memory-system 块同步到各项目 AGENTS.md 的最尾部。
# 用法:
#   bash sync-agents-block.sh [--dry-run] [--create] <项目目录|AGENTS.md 文件>...
#   不给目标时, 扫描 ~/Linewrite 下所有已含该块的项目并更新
# 行为: 块已存在 -> 原地替换(项目自身内容不动); 不存在 -> 追加到最尾部; 文件不存在 -> 跳过(加 --create 才创建)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/AGENTS.md"

DRY=0; CREATE=0; TARGETS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --create) CREATE=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) TARGETS+=("$a") ;;
  esac
done

BLOCK="$(python3 - "$SRC" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf8").read()
m = re.search(r"<!-- memory-system:start -->.*?<!-- memory-system:end -->", s, re.S)
if not m:
    sys.exit("源文件里找不到 memory-system 块")
print(m.group(0), end="")
PY
)"

if [ "${#TARGETS[@]}" -eq 0 ]; then
  while IFS= read -r f; do TARGETS+=("$f"); done < <(grep -rl "<!-- memory-system:start -->" "$HOME/Linewrite" --include=AGENTS.md 2>/dev/null | sort)
fi

changed=0; same=0; skipped=0
for t in "${TARGETS[@]}"; do
  f="$t"; [ -d "$t" ] && f="$t/AGENTS.md"
  if [ ! -f "$f" ]; then
    if [ "$CREATE" = 1 ]; then
      [ "$DRY" = 1 ] || printf '%s\n' "$BLOCK" > "$f"
      echo "created  $f"; changed=$((changed+1))
    else
      echo "skip     $f（无此文件；--create 可创建）"; skipped=$((skipped+1))
    fi
    continue
  fi
  res="$(python3 - "$f" <<PY
import re, sys, pathlib
block = """$BLOCK"""
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf8")
m = re.search(r"<!-- memory-system:start -->.*?<!-- memory-system:end -->", s, re.S)
if m:
    if m.group(0) == block:
        print("same"); sys.exit(0)
    new = s[:m.start()] + block + s[m.end():]
else:
    new = s.rstrip("\n") + "\n\n" + block + "\n"
print("changed")
pathlib.Path("$f.tmp").write_text(new, encoding="utf8")
PY
)"
  case "$res" in
    same) echo "same     $f"; same=$((same+1)) ;;
    changed)
      if [ "$DRY" = 1 ]; then echo "would    $f"; else mv "$f.tmp" "$f"; echo "changed  $f"; fi
      changed=$((changed+1)) ;;
    *) echo "FAIL     $f: $res"; exit 1 ;;
  esac
done
echo "---- 更新 $changed / 已是最新 $same / 跳过 $skipped$([ "$DRY" = 1 ] && echo '（--dry-run，未写入）')"
