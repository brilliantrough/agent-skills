#!/usr/bin/env bash
# check.sh — 公开体检与本仓 lint:语法、skills 结构与索引、文档计数、敏感值、skills 文本链接与字符、skill 与 shell 规范。
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

# ---- 7. skill lint：frontmatter、体量、互相索引 ----
# 规则来源：skills/base/writing-skill/SKILL.md；每条报错写明位置和改法。
echo "== 7. skill lint =="
lint_out=$(python3 - <<'PY'
import os, re
DESC_MAX, BODY_MAX = 400, 24000
# 上游原文技能与 accel 组（装一次、就地特化）不受 description 长度约束
UPSTREAM = {"grilling", "domain-modeling", "tdd", "diagnosing-bugs", "code-review", "teach"}
skills = {}
for g in sorted(os.listdir("skills")):
    gp = os.path.join("skills", g)
    if os.path.isdir(gp):
        for n in sorted(os.listdir(gp)):
            if os.path.isfile(os.path.join(gp, n, "SKILL.md")):
                skills[n] = (g, os.path.join(gp, n))
readme = open("README.md", encoding="utf-8").read()
corpus = {}
for r, ds, fs in os.walk("."):
    ds[:] = [x for x in ds if x not in (".git", "node_modules", "docs")]
    for f in fs:
        if f.endswith((".md", ".sh", ".py", ".mjs", ".js", ".ts", ".json")):
            try:
                corpus[os.path.normpath(os.path.join(r, f))] = open(os.path.join(r, f), encoding="utf-8").read()
            except (UnicodeDecodeError, OSError):
                pass
bad = []
for name, (group, d) in skills.items():
    main = os.path.join(d, "SKILL.md")
    raw = open(main, encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n", raw, re.S)
    if not m:
        bad.append(f"{main}:1: 缺 frontmatter；文件开头补 '---' 包住的 name 与 description")
        continue
    meta = dict(re.findall(r"^([A-Za-z_-]+):[ \t]*(.*)$", m.group(1), re.M))
    if meta.get("name", "").strip("\"'") != name:
        bad.append(f"{main}: name 是 {meta.get('name')!r}，应与目录名 {name!r} 一致")
    desc = meta.get("description", "")
    if not desc:
        bad.append(f"{main}: 缺单行 description；写“做什么＋何时用＋与相邻 skill 的分工”")
    elif desc[0] not in "\"'" and re.search(r": | #", desc):
        bad.append(f"{main}: description 未加引号却含 ': ' 或 ' #'，YAML 会解析失败；改写该处标点或整体加引号")
    if group != "accel" and name not in UPSTREAM and len(desc.strip("\"'")) > DESC_MAX:
        bad.append(f"{main}: description {len(desc)} 字符，上限 {DESC_MAX}；删掉对正文流程的复述，保留触发词")
    size = len(raw.encode("utf-8"))
    if size > BODY_MAX:
        bad.append(f"{main}: {size} 字节，上限 {BODY_MAX}；把查表、案例和分支知识拆到 references/")
    if f"`{name}`" not in readme and f"/{name}/" not in readme:
        bad.append(f"README.md: 技能表里没有 `{name}`；在 {group} 组的表里加一行")
    docs = [os.path.join(r, f) for r, _, fs in os.walk(d) for f in fs if f.endswith(".md")]
    texts = {p: open(p, encoding="utf-8").read() for p in docs}
    for p in docs:
        # 上游技能与模板素材按其来源组织，不要求可达
        if p == main or name in UPSTREAM or "/assets/" in p:
            continue
        if not any(os.path.basename(p) in t for q, t in corpus.items() if q != p):
            bad.append(f"{p}: 仓库里没有任何文件提到它；在 SKILL.md 写明何时读，或删除")
    for p, t in texts.items():
        for ref in set(re.findall(r"`((?:exp|kb|accel)-[a-z0-9]+(?:-[a-z0-9]+)*)`", t)):
            if ref not in skills:
                bad.append(f"{p}: 提到技能 `{ref}`，但 skills/ 下没有；改成现有技能名，或去掉反引号说明它是外部能力")
print("\n".join(bad))
PY
)
if [ -n "$lint_out" ]; then
  err "skill lint:
$lint_out"
else
  info "frontmatter、description/主体体量、README 索引、reference 可达、技能互引检查完成"
fi

# ---- 8. shell lint：脚本头、行尾、共用实现不分叉 ----
echo "== 8. shell lint =="
fail_before=$fail; fail=0
sh_files=$(git ls-files '*.sh' 2>/dev/null || find . -name '*.sh' -not -path './node_modules/*' -not -path './.git/*')
for f in $sh_files; do
  [ -f "$f" ] || continue
  [ "$(head -1 "$f")" = '#!/usr/bin/env bash' ] || err "$f:1: 首行应为 #!/usr/bin/env bash"
  head -60 "$f" | grep -qE '^set -e?uo pipefail' || err "$f: 前 60 行内缺 set -euo pipefail（纯检查脚本可用 set -uo pipefail）"
  if grep -q $'\r' "$f"; then err "$f: 含 CRLF 行尾；转成 LF（.gitattributes 已锁 *.sh 为 LF）"; fi
done
share_out=$(python3 - <<'PY'
import re
SETUPS = ["pi-setup.sh", "opencode-setup.sh", "codex-setup.sh", "dsh-setup.sh"]
SHARED = ["skills-sync.sh", "skills-external.sh", "modules/run.sh"]
# setup 可单文件 curl 运行，这些函数允许各带一份，但各份必须逐字一致
LOCKED = ["ensure_image_gen", "ensure_mem_worker_keys", "fill_template_placeholders", "nbin", "npath", "resolve_python3"]
FN = re.compile(r"^([A-Za-z_]\w*)\(\)\s*\{(.*?)^\}", re.M | re.S)
defs = {f: dict(FN.findall(open(f, encoding="utf-8").read())) for f in SETUPS + SHARED}
bad = []
for fn in LOCKED:
    have = [(f, defs[f][fn]) for f in SETUPS if fn in defs[f]]
    for f, body in have[1:]:
        if body != have[0][1]:
            bad.append(f"{f}: 函数 {fn} 与 {have[0][0]} 的副本不一致；两处同步修改，确属宿主差异就改名并移出 LOCKED")
for f in SETUPS:
    for s in SHARED:
        for fn in sorted(set(defs[f]) & set(defs[s])):
            bad.append(f"{f}: 重新定义了 {s} 里的 {fn}；通用步骤只在 {s} 实现一次，setup 里改为调用")
print("\n".join(bad))
PY
)
[ -z "$share_out" ] || err "共用实现分叉:
$share_out"
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  shellcheck -S error $sh_files || err "shellcheck 报 error 级问题，见上"
elif [ "$fail" = 0 ]; then
  info "未安装 shellcheck，该项跳过"
fi
[ "$fail" = 0 ] && info "脚本头、行尾、共用函数一致"
[ "$fail_before" = 1 ] && fail=1

echo
if [ "$fail" = 0 ]; then echo "PASS: 公开体检通过"; else echo "FAIL: 见上方 ERROR"; fi
exit "$fail"
