#!/usr/bin/env bash
# 在隔离 HOME 里实跑 opencode-setup.sh 第 4 节(opencode.json 合并),覆盖 shell 层:
# 符号链接写穿、自动更新档位探测与询问、旧格式迁移后按 V2 模板合并。
# 引擎级断言见 tests/merge-private-preservation.py;链接写穿只有真 ln -s 的平台能验(Linux),Git Bash 自动跳过。
# 用法: bash tests/sim-opencode-config.sh [仓库目录] [dot_file 目录]   退出码 0 = 通过
set -uo pipefail
REPO="${1:-$HOME/Linewrite/skills/agent-skills}"
DOTFILE="${2:-$HOME/Linewrite/dot_file}"
fails=0
# 原生 python 不认 MSYS 的 /tmp;Windows 商店 stub 能 command -v 到但一跑就报错(与脚本的 resolve_python3 一致)
npath() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }
command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1 || python3() { python "$@"; }

check() { # $1=ok|fail $2=说明
  if [ "$1" = ok ]; then echo "   ✔ $2"; else echo "   ✘ $2"; fails=$((fails + 1)); fi
}

run_case() {
  local name="$1" mode="$2" live="$3" major="$4" want_key="$5" want_val="$6" want_prompt="$7"
  local work; work="$(mktemp -d)"
  local home="$work/home" cfg="$work/home/.config/opencode" dot="$work/dotfiles"
  mkdir -p "$cfg" "$dot"
  printf '%s\n' "$live" > "$dot/opencode.json"
  if [ "$mode" = symlink ]; then ln -s "$dot/opencode.json" "$cfg/opencode.json"
  else cp "$dot/opencode.json" "$cfg/opencode.json"; fi
  cp "$DOTFILE/opencode/opencode.json" "$work/tpl.json"
  sed -n '/^# ---- 4\. opencode\.json/,/^# ---- 4\.2 codegraph/p' "$REPO/opencode-setup.sh" | head -n -1 > "$work/sec4.sh"

  cat > "$work/run.sh" <<'EOS'
set -uo pipefail
command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1 || python3() { python "$@"; }
npath() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }
ask() { echo "ASKED:$1"; return 0; }
fill_template_placeholders() { :; }
curl() { local out=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done; cp "$TPL" "$out"; }
GW_BASE=""; K_CLAUDE=""; K_CODEX=""; K_ANTHROPIC=""; K_GEMINI=""; K_EMBED=""; K_MEM=""; MCPHUB_HOST=""
web_mcp_ready=1
oc_stage="$WORK"
cp "$MIGRATOR" "$oc_stage/migrate-config.mjs"
RAW="http://local"
bun "$MIGRATOR" --apply "$CFG/opencode.json" || exit 1
source "$WORK/sec4.sh"
EOS

  echo "=== $name ==="
  local out; out="$(HOME="$home" WORK="$work" TPL="$work/tpl.json" CFG="$cfg" OC_MAJOR="$major" MIGRATOR="$(npath "$REPO/opencode/dist/stage-v2/migrate-config.mjs")" bash "$work/run.sh" 2>&1)"
  local file; file="$([ "$mode" = symlink ] && echo "$dot/opencode.json" || echo "$cfg/opencode.json")"
  local got; got="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
v = d.get(sys.argv[2])
print("False" if v is False else v)
' "$(npath "$file")" "$want_key")"
  if [ "$got" = "$want_val" ]; then check ok "$want_key = $got"; else check fail "$want_key = $got(期望 $want_val);输出: $out"; fi
  if [ "$want_prompt" = ask ]; then
    case "$out" in *"OpenCode 当前允许自动更新"*) check ok "按预期询问一次" ;; *) check fail "没有询问(输出: $out)" ;; esac
  else
    case "$out" in *"OpenCode 当前允许自动更新"*) check fail "不该询问(输出: $out)" ;; *) check ok "没有打扰(已手动)" ;; esac
  fi
  if [ "$mode" = symlink ]; then
    if [ -L "$cfg/opencode.json" ]; then check ok "链接保留 → $(readlink "$cfg/opencode.json")"; else check fail "链接被替换成普通文件"; fi
  fi
  rm -rf "$work"
}

link_probe="$(mktemp -d)"; echo x > "$link_probe/t"; ln -s "$link_probe/t" "$link_probe/l" 2>/dev/null
if [ -L "$link_probe/l" ]; then have_symlink=1; else have_symlink=0; fi
rm -rf "$link_probe"
if [ "$have_symlink" = 1 ]; then
  run_case "A 符号链接 + v1 遗留 autoupdate:true(v2 客户端)" symlink '{"$schema":"x","autoupdate":true,"permission":{"*":"allow"}}' 2 update disable ask
else
  echo "SKIP A: 本机 ln -s 会复制文件(Git Bash),链接写穿请在 Linux 上验"
fi
run_case "B 普通文件 + v1 遗留 autoupdate:true(v2 客户端)" plain '{"$schema":"x","autoupdate":true,"permission":{"*":"allow"}}' 2 update disable ask
run_case "C 已有 update:notify" plain '{"$schema":"x","update":"notify","permission":{"*":"allow"}}' 2 update notify keep
run_case "D v1 遗留 autoupdate:false" plain '{"$schema":"x","autoupdate":false,"permission":{"*":"allow"}}' 2 update disable keep
run_case "E v2 全新配置(无档位)" plain '{"$schema":"x","permission":{"*":"allow"}}' 2 update disable keep

if [ "$fails" -ne 0 ]; then echo "FAIL: $fails 项"; exit 1; fi
echo "PASS: opencode.json 合并的 shell 层(迁移/档位探测/写穿链接)"
