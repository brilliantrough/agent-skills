#!/usr/bin/env bash
# 抽出三个 setup 里真实的 merge_cfg / ensure_mem_provider(及 Pi 的 deploy_file),对符号链接配置实跑:
# 写入链接目标、链接保留、本机敏感值不被覆盖;普通文件照常合并。不联网,不动真实 HOME。
# 链接写穿只有真 ln -s 的平台能验(Linux/macOS),Git Bash 自动跳过。
# 用法: bash tests/merge-symlink-writethrough.sh   退出码 0 = 通过
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
case "$(uname -s 2>/dev/null || true)" in MINGW*|MSYS*|CYGWIN*) echo "SKIP: Git Bash 的 ln -s 默认是拷贝,无法验证链接写穿"; exit 0 ;; esac

run_one() ( # 子 shell:每个 setup 的函数互不污染
  script="$1"; rc=0
  w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
  mkdir -p "$w/dot" "$w/cfg"
  src="$(python3 - "$script" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
for n in ["npath", "rpath", "nbin", "fill_template_placeholders", "ask", "merge_cfg", "ensure_mem_provider", "deploy_file"]:
    m = re.search(r"^%s\(\)\s*\{.*?^\}\n" % n, s, re.M | re.S)
    if m:
        print(m.group(0))
    elif n != "deploy_file":  # 整文件部署只有 Pi 有
        sys.exit(f"{sys.argv[1]}: 找不到函数 {n}")
PY
)" || { echo "  FAIL: 抽取函数失败"; exit 1; }
  # 函数依赖的脚本级变量:非交互取默认、不提供网关凭据
  IS_WIN=0; ASSUME_YES=1; GW_BASE=""; K_CLAUDE=""; K_CODEX=""; K_ANTHROPIC=""; K_GEMINI=""; K_EMBED=""; K_MEM=""; MCPHUB_HOST=""
  SETTINGS="$w/none"; BUN_BIN=bun; errors=0
  warn() { echo "WARN: $*" >&2; }
  eval "$src"
  ok() { echo "  ok: $*"; }
  bad() { echo "  FAIL: $*"; rc=1; }
  printf '{"apiKey":"<YOUR_KEY>","model":"new","added":true}\n' > "$w/tpl.json"

  printf '{"apiKey":"LOCAL-SECRET","keep":1,"model":"old"}\n' > "$w/dot/a.json"
  ln -s "$w/dot/a.json" "$w/cfg/a.json"
  merge_cfg "file://$w/tpl.json" "$w/cfg/a.json" >/dev/null 2>&1
  if [ -L "$w/cfg/a.json" ]; then ok "合并后链接保留"; else bad "链接被替换成普通文件"; fi
  if python3 - "$w/dot/a.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d == {"apiKey": "LOCAL-SECRET", "keep": 1, "model": "new", "added": True}, d
PY
  then ok "链接目标已合并,本机敏感值与独有键保留"; else bad "链接目标内容不对"; fi

  ln -s "$w/dot/b.json" "$w/cfg/b.json"
  merge_cfg "file://$w/tpl.json" "$w/cfg/b.json" >/dev/null 2>&1
  if [ -L "$w/cfg/b.json" ] && [ -f "$w/dot/b.json" ]; then ok "悬空链接首次写入落在链接目标"; else bad "悬空链接首次写入未落在链接目标"; fi

  printf '{"CLAUDE_MEM_PROVIDER":"claude","x":1}\n' > "$w/dot/s.json"
  ln -s "$w/dot/s.json" "$w/cfg/s.json"
  ensure_mem_provider "$w/cfg/s.json" >/dev/null 2>&1
  if [ -L "$w/cfg/s.json" ] && grep -q '"openrouter"' "$w/dot/s.json"; then ok "provider 穿过链接更新"; else bad "provider 未写入链接目标"; fi

  printf '{"apiKey":"P","model":"old"}\n' > "$w/cfg/p.json"
  merge_cfg "file://$w/tpl.json" "$w/cfg/p.json" >/dev/null 2>&1
  if [ ! -L "$w/cfg/p.json" ] && grep -q '"new"' "$w/cfg/p.json" && grep -q '"P"' "$w/cfg/p.json"; then ok "普通文件照常合并"; else bad "普通文件合并不对"; fi

  if declare -F deploy_file >/dev/null; then
    printf 'old\n' > "$w/dot/d.md"; ln -s "$w/dot/d.md" "$w/cfg/d.md"; printf 'new\n' > "$w/d.src"
    deploy_file "file://$w/d.src" "$w/cfg/d.md" test >/dev/null 2>&1
    if [ -L "$w/cfg/d.md" ] && [ "$(cat "$w/dot/d.md")" = new ]; then ok "整文件部署写入链接目标"; else bad "整文件部署未写入链接目标"; fi
  fi
  exit "$rc"
)

fails=0
for f in pi-setup.sh opencode-setup.sh codex-setup.sh; do
  echo "== $f"
  run_one "$f" || fails=1
done
if [ "$fails" = 0 ]; then echo "PASS: 三个 setup 的配置合并都写穿符号链接"; else echo "FAIL: 见上方"; fi
exit "$fails"
