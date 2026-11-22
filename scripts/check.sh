#!/usr/bin/env bash
# check.sh — 公开体检、本仓 lint 与离线 Verification（--with-tests）。
# 完整自检(private)不随分发;这里是贡献者能自己跑的那一半。
# 用法: bash scripts/check.sh [--with-tests]   # 0 = 通过
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

WITH_TESTS=0
for a in "$@"; do
  case "$a" in
    --with-tests) WITH_TESTS=1 ;;
    *) echo "未知参数: $a(可用: --with-tests)" >&2; exit 2 ;;
  esac
done

fail=0
public_skipped=0
err() { printf 'ERROR: %s\n' "$*"; fail=1; }
info() { printf '  %s\n' "$*"; }

# ---- 1. 脚本语法与安装流程 ----
echo "== 1. 语法与安装流程 =="
for f in pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh skills-sync.sh skills-external.sh modules/run.sh scripts/check.sh; do
  [ -f "$f" ] || { err "缺文件 $f"; continue; }
  bash -n "$f" 2>/dev/null || err "bash -n 失败: $f"
done
while IFS= read -r f; do
  python3 -m py_compile "$f" 2>/dev/null || err "py_compile 失败: $f"
done < <(find skills -name '*.py' -type f 2>/dev/null)
info "shell 与 python 语法检查完成"
preflight_out="$(python3 tests/setup-preflight.py 2>&1)"; preflight_rc=$?
printf '%s\n' "$preflight_out"
if [ "$preflight_rc" != 0 ]; then
  err "安装前置流程回归失败: tests/setup-preflight.py"
elif [[ "$preflight_out" == "SKIP:"* ]]; then
  printf '  SKIP setup-preflight.py: %s\n' "${preflight_out#SKIP: }"
  public_skipped=1
elif ! printf '%s\n' "$preflight_out" | grep -Eq '^[[:space:]]*PASS([: ]|$)'; then
  err "安装前置流程回归退出 0 但未输出 PASS"
else
  info "安装前置流程回归通过"
fi

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
# 源码基准 = 一棵本地 git 树:默认受管 clone,AGENT_SKILLS_SOURCE 可指定已有工作树。
# 已明确推翻旧的"只能 tarball、不读本地 clone"规则(2026-11)。
for f in pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh skills-sync.sh; do
  grep -q '^acquire_source() {' "$f" || err "$f 缺 acquire_source(统一源码基准入口)"
done
grep -q 'AGENT_SKILLS_SOURCE' skills-sync.sh || err "skills-sync.sh 未支持显式 AGENT_SKILLS_SOURCE"
if grep -nE 'codeload\.github\.com|archive/refs/heads' skills-sync.sh pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh; then
  err "取源又回到 GitHub tarball;模板与 skills 必须从本地源码树取"
fi
grep -q 'releases/latest/download\|releases/download' pi-setup.sh opencode-setup.sh dsh-setup.sh \
  || err "编译产物分发入口丢失(release)应保留"
info "取源走本地源码树;编译产物仍走 Release"

# 配置模板随本仓分发(templates/);setup 不再依赖其它仓库
if grep -nE 'githubusercontent\.com/[^/]+/dot_file' pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh skills-sync.sh skills-external.sh modules/run.sh modules/*/setup.sh; then
  err "setup 里出现 dot_file 仓库的下载地址;模板放进 templates/,经 RAW 变量(指向本仓 templates/)取用"
fi
# 脚本里以 RAW 变量加相对路径引用模板;逐个核对文件存在
tpl_missing=0
for t in $(grep -ohE '[^A-Z_]RAW/[A-Za-z0-9_./-]+' pi-setup.sh opencode-setup.sh codex-setup.sh dsh-setup.sh | sort -u); do
  f="templates/${t#*RAW/}"
  if [ ! -f "$f" ]; then err "setup 引用了不存在的模板 $f;补上文件或改引用"; tpl_missing=1
  elif git rev-parse --git-dir >/dev/null 2>&1 && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    err "模板 $f 在本机存在但没有入库(多半被 ignore 规则挡住);git add 后再 push,否则 setup 下载会 404"; tpl_missing=1
  fi
done
[ "$tpl_missing" = 0 ] && info "setup 引用的模板都在 templates/"

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
DESC_MAX, BODY_MAX, ITEM_MAX = 400, 24000, 400
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
    if group != "accel" and name not in UPSTREAM:
        fenced = False
        for i, line in enumerate(raw.split("\n"), 1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
            m = None if fenced else re.match(r"\s*(?:[-*]|\d+\.)\s+(.*)$", line)
            if m and len(m.group(1)) > ITEM_MAX:
                bad.append(f"{main}:{i}: 列表条目 {len(m.group(1))} 字符，上限 {ITEM_MAX}；一个条目只写一个动作，其余拆成子条目")
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
  info "frontmatter、description/主体体量、条目长度、README 索引、reference 可达、技能互引检查完成"
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
ALL3 = ["pi-setup.sh", "opencode-setup.sh", "codex-setup.sh"]
PI_OC = ["pi-setup.sh", "opencode-setup.sh"]
# setup 可单文件 curl 运行，这些函数允许各带一份，但列出的各份必须逐字一致。
# 宿主差异用参数表达；确实不同的实现改名，不放进这张表。
LOCKED = {
    "npath": ALL3, "rpath": ALL3, "nbin": ALL3, "resolve_python3": ALL3,
    "ask": ALL3, "ask_value": ALL3, "fill_template_placeholders": ALL3, "mem_worker_url": ALL3,
    "file_url": SETUPS + ["skills-sync.sh"], "acquire_source": SETUPS + ["skills-sync.sh"],
    "net_ok": PI_OC, "config_probe": PI_OC, "collect_gateway_values": PI_OC, "ensure_mem_provider": PI_OC,
    "ensure_mem_worker_keys": PI_OC, "ensure_image_gen": PI_OC,
}

def functions(path):
    out, name, body, heredoc = {}, None, [], None
    for line in open(path, encoding="utf-8"):
        if name is None:
            m = re.match(r"([A-Za-z_]\w*)\(\)\s*\{(.*)$", line)
            if not m:
                continue
            if m.group(2).rstrip().endswith("}"):  # 单行函数
                out[m.group(1)] = m.group(2).rstrip()
            else:
                name, body = m.group(1), [m.group(2)]
            continue
        if heredoc:
            body.append(line)
            if line.strip() == heredoc:
                heredoc = None
            continue
        if line.rstrip("\n") == "}":
            out[name] = "".join(body)
            name, heredoc = None, None
            continue
        body.append(line)
        marker = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)", line)
        if marker:
            heredoc = marker.group(1)
    return out

defs = {f: functions(f) for f in SETUPS + SHARED}
bad = []
for fn, files in LOCKED.items():
    missing = [f for f in files if fn not in defs[f]]
    for f in missing:
        bad.append(f"{f}: 缺函数 {fn}（LOCKED 要求它与 {files[0]} 保持一致）；补上，或把它移出 LOCKED")
    have = [f for f in files if fn in defs[f]]
    for f in have[1:]:
        if defs[f][fn] != defs[have[0]][fn]:
            bad.append(f"{f}: 函数 {fn} 与 {have[0]} 的副本不一致；两处同步修改，宿主差异改用参数传入")
for f in SETUPS:
    for s in SHARED:
        for fn in sorted(set(defs[f]) & set(defs[s])):
            if f in LOCKED.get(fn, []) and s in LOCKED.get(fn, []):  # LOCKED 明确允许逐字节副本(如取源层)
                continue
            bad.append(f"{f}: 重新定义了 {s} 里的 {fn}；通用步骤只在 {s} 实现一次，setup 里改为调用")
# 私密值永不覆盖：三份内嵌合并逻辑的敏感键正则必须逐字一致
sens = {f: re.findall(r"^SENSITIVE = .*$", open(f, encoding="utf-8").read(), re.M) for f in ALL3}
for f in ALL3:
    if len(sens[f]) != 1:
        bad.append(f"{f}: 应恰有一行 SENSITIVE = …，实际 {len(sens[f])} 行")
    elif sens[f] != sens[ALL3[0]]:
        bad.append(f"{f}: SENSITIVE 正则与 {ALL3[0]} 不一致；三份同步修改并跑 tests/merge-private-preservation.py")
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
[ "$fail" = 0 ] && info "脚本头、行尾、共用函数与 SENSITIVE 一致"
[ "$fail_before" = 1 ] && fail=1

# ---- 9. 行为回归(仅 --with-tests) ----
# 缺前置条件报 SKIP 与原因,不算通过;不联网、不写 live 配置、不自动安装或构建。
if [ "$WITH_TESTS" = 1 ]; then
  echo "== 9. 行为回归 =="
  skipped=0
  test_cache="$(mktemp -d)"
  export XDG_CACHE_HOME="$test_cache/xdg" BUN_INSTALL_CACHE_DIR="$test_cache/bun" NODE_DISABLE_COMPILE_CACHE=1
  trap 'rm -rf "$test_cache"' EXIT
  t_fail() { printf '   FAIL %s: %s\n' "$1" "$2"; fail=1; }
  t_skip() { printf '   SKIP %s: %s\n' "$1" "$2"; skipped=$((skipped + 1)); }
  t_run() { # $1=名称,其余=命令;输出里任何 SKIP 行都计入未验证;退出码非零一律 FAIL
    local name="$1" out rc skips; shift
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" != 0 ]; then
      printf '   FAIL %s: 退出码 %s\n' "$name" "$rc"; printf '%s\n' "$out" | tail -12 | sed 's/^/        /'; fail=1
      return
    fi
    case "$out" in
      "SKIP:"*)
        if [[ "$out" != *$'\n'* ]]; then local reason="${out#SKIP: }"; t_skip "$name" "$reason"; return; fi ;;
    esac
    if ! printf '%s\n' "$out" | grep -Eq '^[[:space:]]*PASS([: ]|$)'; then
      printf '   FAIL %s: 退出 0 但未输出 PASS\n' "$name"
      printf '%s\n' "$out" | tail -12 | sed 's/^/        /'; fail=1
      return
    fi
    skips="$(printf '%s\n' "$out" | grep -E '^[[:space:]]*SKIP([: ]|$)|SKIP HOST ' | sed -E 's/^[[:space:]]*//')"
    if [ -n "$skips" ]; then
      printf '   PASS %s（有场景 SKIP，未验证）\n' "$name"
      printf '%s\n' "$skips" | sed 's/^[[:space:]]*/        /'
      skipped=$((skipped + 1))
    else printf '   PASS %s\n' "$name"; fi
  }
  no_node() { ! command -v node >/dev/null 2>&1; }
  no_bun() { ! command -v bun >/dev/null 2>&1; }
  no_py() { ! command -v python3 >/dev/null 2>&1; }
  oc_src=opencode/migrate-config.mjs
  # 依赖被软链到 live runtime 时测试会跑到 live 代码上;默认不执行,显式路径由用户负责隔离。
  dep_reason() { # 输出跳过原因;可运行时无输出
    node -e 'const fs=require("fs"),p=require("path");let r;try{r=fs.realpathSync(p.join("node_modules",process.argv[1]))}catch{process.exit(1)}const root=fs.realpathSync(".");process.exit(r===root||r.startsWith(root+p.sep)?0:2)' "$1"
    case "$?" in
      1) printf 'node_modules 缺 %s(需 npm install;不自动执行)' "$1" ;;
      2) printf '%s 的物理路径在仓库外(软链到 live runtime),不跟随执行' "$1" ;;
    esac
  }
  t_case() { # $1=本仓测试文件 $2=跳过原因(空=可运行) 其余=命令;缺文件先 FAIL,不被 SKIP 掩盖
    local f="$1" why="$2" name; shift 2; name="$(basename "$f")"
    if [ ! -f "$f" ]; then t_fail "$name" "本仓正式资产缺失: $f"; return; fi
    if [ -n "$why" ]; then t_skip "$name" "$why"; return; fi
    t_run "$name" "$@"
  }

  if no_node; then why="缺 node"; else why="$(dep_reason @earendil-works/pi-coding-agent)"; fi
  t_case tests/ui-render-dedupe.mjs "$why" node tests/ui-render-dedupe.mjs

  if no_node; then why="缺 node"; else why="$(dep_reason @earendil-works/pi-tui)"; fi
  t_case tests/ui-copy-clean.mjs "$why" node tests/ui-copy-clean.mjs

  if no_node; then why="缺 node"; else why=""; fi
  t_case tests/pretty-tui-grouping.mjs "$why" node --experimental-strip-types tests/pretty-tui-grouping.mjs
  t_case tests/verification-agent.mjs "$why" node tests/verification-agent.mjs

  if no_node; then why="缺 node"
  elif [ ! -f context-rewrite/node_modules/acp-kernel/package.json ]; then why="缺 context-rewrite/node_modules/acp-kernel(需 npm ci;不自动执行)"
  else why=""; fi
  t_case context-rewrite/demo.mjs "$why" node context-rewrite/demo.mjs

  if no_node; then why="缺 node"; else why="$(dep_reason @earendil-works/pi-tui)"; fi
  t_case tests/ui-sidebar.mjs "$why" node --experimental-strip-types tests/ui-sidebar.mjs

  # 会话周期会加载真实宿主；只有显式 PI_HOST_DIR 才跑，隔离由调用方负责。
  if no_node; then why="缺 node"
  elif [ -z "${PI_HOST_DIR:-}" ]; then why="需 PI_HOST_DIR 显式指定隔离的 Pi 宿主(不跑 live 宿主)"
  else why=""; fi
  t_case tests/pretty-tui-session-cycle.mjs "$why" node tests/pretty-tui-session-cycle.mjs

  if no_py; then pwhy="缺 python3"; else pwhy=""; fi
  t_case tests/merge-private-preservation.py "$pwhy" python3 tests/merge-private-preservation.py
  t_case tests/nju-ppt-install.py "$pwhy" python3 tests/nju-ppt-install.py
  t_case tests/pi-setup-windows-git-bash.py "$pwhy" python3 tests/pi-setup-windows-git-bash.py
  t_case tests/pi-setup-shell-messages.py "$pwhy" python3 tests/pi-setup-shell-messages.py
  t_case tests/check-gate.py "$pwhy" python3 tests/check-gate.py
  t_case tests/source-bench.py "$pwhy" python3 tests/source-bench.py
  t_case skills/ppt/nju-ppt/scripts/test_check_brief.py "$pwhy" python3 skills/ppt/nju-ppt/scripts/test_check_brief.py

  # Git Bash 上 ln -s 会复制文件,脚本自己打印 SKIP 并退出 0。
  t_case tests/merge-symlink-writethrough.sh "$pwhy" bash tests/merge-symlink-writethrough.sh

  if [ -f "$oc_src" ]; then :; else t_fail "$(basename "$oc_src")" "本仓正式资产缺失: $oc_src;两个 OpenCode 回归依赖它"; fi
  if no_bun; then why="缺 bun(迁移脚本是 bun 入口)"
  elif [ ! -f opencode/node_modules/@opencode/core/package.json ] || [ ! -f opencode/node_modules/jsonc-parser/package.json ]; then
    why="缺 OpenCode 迁移依赖(opencode/node_modules;不自动安装或联网补齐)"
  else why=""; fi
  t_case tests/opencode-config-migration.mjs "$why" bun --no-install tests/opencode-config-migration.mjs

  if no_bun; then why="缺 bun(迁移脚本是 bun 入口)"
  elif [ ! -f opencode/node_modules/@opencode/core/package.json ] || [ ! -f opencode/node_modules/jsonc-parser/package.json ]; then
    why="缺 OpenCode 迁移依赖(opencode/node_modules;不自动安装或联网补齐)"
  elif no_py; then why="缺 python3"
  else why=""; fi
  t_case tests/sim-opencode-config.sh "$why" bash tests/sim-opencode-config.sh "$PWD"

  if no_node; then why="缺 node"; else why=""; fi
  t_case tests/nju-ppt-html.mjs "$why" node tests/nju-ppt-html.mjs

  # 成稿由 ppt-master 产出,tests/ 里没有可复用样本;不自动安装引擎。
  if [ ! -f tests/nju-ppt-editability.py ]; then t_fail nju-ppt-editability.py "本仓正式资产缺失: tests/nju-ppt-editability.py"
  elif no_py; then t_skip nju-ppt-editability.py "缺 python3"
  elif [ -z "${NJU_PPT_PPTX:-}" ]; then t_skip nju-ppt-editability.py "需要成稿 PPTX(设 NJU_PPT_PPTX=<路径>)"
  elif [ ! -f "$NJU_PPT_PPTX" ]; then t_fail nju-ppt-editability.py "NJU_PPT_PPTX 指向的文件不存在"
  else t_run nju-ppt-editability.py python3 tests/nju-ppt-editability.py "$NJU_PPT_PPTX"; fi

  # 未设 DSH_TEST_RUNTIME 时测试自己打 SKIP HOST 汇总,由 t_run 计入未验证。
  if no_node; then why="缺 node"; else why=""; fi
  t_case tests/dsh-deploy.e2e.mjs "$why" node tests/dsh-deploy.e2e.mjs
  t_case tests/dsh-subagent-host.mjs "$why" node tests/dsh-subagent-host.mjs

  [ "$skipped" = 0 ] || info "SKIP $skipped 项(原因见上),不计入通过"
fi

echo
if [ "$fail" = 0 ]; then
  total_skipped=$((public_skipped + ${skipped:-0}))
  if [ "$total_skipped" != 0 ]; then
    if [ "$WITH_TESTS" = 1 ]; then scope="公开体检与行为回归"; else scope="公开体检"; fi
    echo "PASS: ${scope}通过，但 $total_skipped 项因缺前置条件 SKIP（未验证，见上）"
  elif [ "$WITH_TESTS" = 1 ]; then echo "PASS: 公开体检与行为回归全部通过"
  else echo "PASS: 公开体检通过"; fi
else echo "FAIL: 见上方 ERROR 或 FAIL 行"; fi
exit "$fail"
