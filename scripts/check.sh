#!/usr/bin/env bash
# check.sh — 公开的最小体检:语法、skills 组结构、文档计数、敏感值与个人路径。
# 完整自检(private)不随分发;这里是贡献者能自己跑的那一半。
# 用法: bash scripts/check.sh          # 0 = 通过
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

fail=0
err() { printf 'ERROR: %s\n' "$*"; fail=1; }
info() { printf '  %s\n' "$*"; }

# ---- 1. 脚本语法 ----
echo "== 1. 语法 =="
for f in pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh skills-sync.sh skills-external.sh scripts/check.sh; do
  [ -f "$f" ] || { err "缺文件 $f"; continue; }
  bash -n "$f" 2>/dev/null || err "bash -n 失败: $f"
done
while IFS= read -r f; do
  python3 -m py_compile "$f" 2>/dev/null || err "py_compile 失败: $f"
done < <(find skills -name '*.py' -type f 2>/dev/null)
info "shell 与 python 语法检查完成"

# ---- 2. skills 组结构 + 计数 ----
echo "== 2. skills 结构 =="
read -r struct_out counts < <(python3 - <<'PY'
import os, collections
G = ["base", "research", "accel", "kb", "ppt"]
bad, seen, counts = [], collections.Counter(), {}
for g in sorted(os.listdir("skills")):
    p = os.path.join("skills", g)
    if not os.path.isdir(p):
        continue
    if g not in G:
        bad.append(f"未知组目录 {g}(只能是 {G})")
        continue
    n = 0
    for s in sorted(os.listdir(p)):
        d = os.path.join(p, s)
        if not os.path.isdir(d):
            continue
        if not os.path.exists(os.path.join(d, "SKILL.md")):
            bad.append(f"{d} 缺 SKILL.md")
        seen[s] += 1
        n += 1
    counts[g] = n
bad += [f"{s} 跨组重名" for s, c in seen.items() if c > 1]
print("; ".join(bad) if bad else "ok", " ".join(f"{g}={counts.get(g, 0)}" for g in G), sep="\t")
PY
)
[ "$struct_out" = "ok" ] || err "结构: $struct_out"
info "分组: $counts"
total=0
for kv in $counts; do total=$((total + ${kv#*=})); done
info "合计: $total"

# ---- 3. README 计数与结构一致 ----
echo "== 3. 文档计数 =="
grep -q "## Skills（本仓 $total 个）" README.md || err "README 标题计数不是 $total"
grep -q "#skills本仓-$total-个" README.md || err "README 目录锚点不是 $total"
base_n=$(echo "$counts" | tr ' ' '\n' | sed -n 's/^base=//p')
grep -q "默认 base $base_n 个" README.md || err "README 里 base 数量不是 $base_n"
grep -q "共 $total 个" README.md || err "README 的组合计不是 $total"
info "README: 本仓 $total 个, base $base_n 个"

# ---- 4. 敏感值与个人路径 ----
echo "== 4. 敏感值 / 个人路径 =="
# 只扫入库内容(.gitignore 已排除私有资料);命中即报,便于人工确认
if git rev-parse --git-dir >/dev/null 2>&1; then
  files=$(git ls-files '*.sh' '*.md' '*.py' '*.mjs' '*.js' '*.json' '*.yml' '*.yaml' | grep -v '^node_modules/')
else
  files=$(find . -type f \( -name '*.sh' -o -name '*.md' -o -name '*.py' -o -name '*.mjs' -o -name '*.js' \) -not -path './node_modules/*' -not -path './.git/*')
fi
hits=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  h=$(grep -nE '(/home/[a-z]+/|C:/Users/[A-Za-z0-9_.-]+/|192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|sk-[A-Za-z0-9]{16,})' "$f" 2>/dev/null)
  # 类密钥字面量：引号内 20+ 位 ASCII 串（排除 $VAR 与 <占位符>）；以及带真实值的 Cookie 头
  h2=$(grep -nE '(api[_-]?key|secret|password|passwd|token|cookie|authorization)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_./+=-]{20,}["'"'"']|cookie:[[:space:]]*[A-Za-z0-9_%=-]{10,}' "$f" 2>/dev/null)
  [ -z "$h$h2" ] || hits="${hits}${f}:
${h}${h2}
"
done <<< "$files"
if [ -n "$hits" ]; then
  err "疑似个人路径 / 内网地址 / 密钥或 cookie 字面量，逐条确认（文档示例与字段名可豁免，真实值不可）:
$hits"
else
  info "未发现个人路径、内网地址、密钥或 cookie 字面量"
fi

# ---- 5. 分发链路纪律 ----
echo "== 5. 分发链路 =="
grep -q 'codeload.github.com' skills-sync.sh || err "skills-sync.sh 不再从 GitHub 拉取源"
grep -qE 'agent-skills-main/|本地克隆当源' skills-sync.sh && err "skills-sync.sh 出现本地克隆取源"
info "取源仍走 GitHub tarball"

# 通用步骤只在共用脚本里实现一次；setup 里各写一份就会逐渐走偏
grep -q 'memory-system:start' skills-sync.sh || err "skills-sync.sh 缺记忆规范块注入（四个 setup 共用）"
for f in pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh; do
  grep -q 'memory-system:start' "$f" && err "$f 里又出现了记忆规范块实现（应只在 skills-sync.sh）"
done
info "记忆规范块注入只在 skills-sync.sh"

echo
if [ "$fail" = 0 ]; then echo "PASS: 公开体检通过"; else echo "FAIL: 见上方 ERROR"; fi
exit "$fail"
