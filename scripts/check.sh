#!/usr/bin/env bash
# check.sh — 公开的最小体检:语法、skills 组结构、文档计数、敏感值与个人路径、skills 文本的链接与字符。
# 完整自检(private)不随分发;这里是贡献者能自己跑的那一半。
# 用法: bash scripts/check.sh          # 0 = 通过
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

fail=0
err() { printf 'ERROR: %s\n' "$*"; fail=1; }
info() { printf '  %s\n' "$*"; }

# ---- 1. 脚本语法 ----
echo "== 1. 语法 =="
for f in pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh skills-sync.sh skills-external.sh modules/run.sh scripts/check.sh; do
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

# 模块契约：元数据齐全、默认 N（写 Y 必须在 desc 里说明）、四个 setup 都走通用分发
for d in modules/*/; do
  [ -f "$d/setup.sh" ] || continue
  n="$(sed -n 's/^# module:[[:space:]]*//p' "$d/setup.sh" | head -1)"
  [ "$n" = "$(basename "$d")" ] || err "$d 的 # module: 与目录名不一致（得到 '${n:-空}'）"
  sed -n 's/^# desc:[[:space:]]*//p' "$d/setup.sh" | grep -q . || err "$d 缺 # desc:"
  def="$(sed -n 's/^# default:[[:space:]]*//p' "$d/setup.sh" | head -1)"
  case "$def" in N|Y) ;; *) err "$d 的 # default: 缺失或不是 N/Y（得到 '${def:-空}'）" ;; esac
  sed -n 's/^# hosts:[[:space:]]*//p' "$d/setup.sh" | grep -q . || err "$d 缺 # hosts:"
done
for f in pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh; do
  grep -q 'modules/run.sh' "$f" || err "$f 未接通用模块分发（modules/run.sh）"
done
info "模块契约与通用分发入口检查完成"

# ---- 6. skills 文本：相对链接、锚点、混入的外文字符 ----
echo "== 6. skills 文本 =="
text_out=$(python3 - <<'PY'
import os, re, subprocess
try:
    files = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "skills"], text=True).split("\n")
except Exception:
    files = [os.path.join(d, f) for d, _, fs in os.walk("skills") for f in fs]
files = [f for f in files if f.endswith(".md") and os.path.isfile(f)]
FENCE = re.compile(r"^\s*(```|~~~)")
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
# 简体正文里不该出现的假名、谚文，以及高频繁体字
FOREIGN = re.compile("[぀-ヿ가-힯ᄀ-ᇿ與僅該誤為這個們來時國說會學對發經過還無現實點應關開問題體總結構據證驗險護標準備種樣碼專處當從後進運動態數類變確認際選擇記錄]")

def lines(path):
    fenced = False
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        if FENCE.match(line):
            fenced = not fenced
            continue
        if not fenced:
            yield i, line

def anchors(path, cache={}):
    if path not in cache:
        seen, out = {}, set()
        for _, line in lines(path):
            out.update(re.findall(r"<a\s+(?:id|name)=\"([^\"]+)\"", line))
            m = re.match(r"#{1,6}\s+(.*?)\s*#*\s*$", line)
            if not m:
                continue
            slug = re.sub(r"[^\w\- ]", "", m.group(1).lower()).replace(" ", "-")
            n = seen.get(slug, 0)
            seen[slug] = n + 1
            out.add(slug if n == 0 else f"{slug}-{n}")
        cache[path] = out
    return cache[path]

bad = []
for f in files:
    for i, line in lines(f):
        m = FOREIGN.search(line)
        if m:
            bad.append(f"{f}:{i}: 混入外文字符 {m.group(0)!r}")
        for target in LINK.findall(re.sub(r"`[^`]*`", "", line)):
            if re.match(r"[a-z][a-z0-9+.-]*:", target) or target.startswith("<"):
                continue
            path, _, frag = target.partition("#")
            dest = os.path.normpath(os.path.join(os.path.dirname(f), path)) if path else f
            if not os.path.exists(dest):
                bad.append(f"{f}:{i}: 链接目标不存在 {target}")
            elif frag and dest.endswith(".md") and frag.lower() not in anchors(dest):
                bad.append(f"{f}:{i}: 锚点不存在 {target}（改链接，或恢复 {dest} 的标题文字）")
print("\n".join(bad))
PY
)
if [ -n "$text_out" ]; then
  err "skills 文本问题:
$text_out"
else
  info "相对链接、锚点可解析；未混入假名、谚文或繁体字"
fi

echo
if [ "$fail" = 0 ]; then echo "PASS: 公开体检通过"; else echo "FAIL: 见上方 ERROR"; fi
exit "$fail"
