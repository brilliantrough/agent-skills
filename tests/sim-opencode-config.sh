#!/usr/bin/env bash
# 在隔离 HOME 里实跑 opencode-setup.sh 第 4 节(opencode.json 合并),覆盖 shell 层:
# 符号链接写穿、前置计划传入的自动更新档位、旧格式迁移后按 V2 模板合并。
# 引擎级断言见 tests/merge-private-preservation.py;链接写穿只有真 ln -s 的平台能验(Linux),Git Bash 自动跳过。
# 用法: bash tests/sim-opencode-config.sh [仓库目录]   退出码 0 = 通过
set -uo pipefail
REPO="${1:-$HOME/Linewrite/skills/agent-skills}"
TEMPLATES="$REPO/templates"
fails=0
# 原生 python 不认 MSYS 的 /tmp;Windows 商店 stub 能 command -v 到但一跑就报错(与脚本的 resolve_python3 一致)
npath() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }
command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1 || python3() { python "$@"; }

check() { # $1=ok|fail $2=说明
  if [ "$1" = ok ]; then echo "   ✔ $2"; else echo "   ✘ $2"; fails=$((fails + 1)); fi
}

run_case() {
  local name="$1" mode="$2" live="$3" major="$4" want_key="$5" want_val="$6" force_manual="$7"
  local work; work="$(mktemp -d)"
  local home="$work/home" cfg="$work/home/.config/opencode" dot="$work/dotfiles"
  mkdir -p "$cfg" "$dot"
  printf '%s\n' "$live" > "$dot/opencode.json"
  if [ "$mode" = symlink ]; then ln -s "$dot/opencode.json" "$cfg/opencode.json"
  else cp "$dot/opencode.json" "$cfg/opencode.json"; fi
  cp "$TEMPLATES/opencode/opencode.json" "$work/tpl.json"
  sed -n '/^rpath() {/,/^}/p' "$REPO/opencode-setup.sh" > "$work/sec4.sh"
  sed -n '/^# ---- 4\. opencode\.json/,/^fi # 完整安装/p' "$REPO/opencode-setup.sh" | head -n -1 >> "$work/sec4.sh"
  # 测试直接执行当前迁移源码；只替换它在发布目录中的位置，不改合并逻辑。
  sed -i -e 's|\$oc_stage/migrate-config\.mjs|\$MIGRATOR|g' -e 's|bun "$(npath|bun --no-install "$(npath|g' "$work/sec4.sh"

  cat > "$work/run.sh" <<'EOS'
set -uo pipefail
command -v python3 >/dev/null 2>&1 && python3 -c pass >/dev/null 2>&1 || python3() { python "$@"; }
npath() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }
ask() { echo "ASKED:$1"; return 0; }
fill_template_placeholders() { :; }
curl() { local out=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done; cp "$TPL" "$out"; }
GW_BASE=""; K_CLAUDE=""; K_CODEX=""; K_ANTHROPIC=""; K_GEMINI=""; K_EMBED=""; K_MEM=""; MCPHUB_HOST=""
web_mcp_ready=1
IS_WIN=0
export XDG_CACHE_HOME="$WORK/xdg-cache" BUN_INSTALL_CACHE_DIR="$WORK/bun-cache"
if [ "$FORCE_MANUAL" = 1 ]; then PLAN_FORCE_MANUAL=1; else PLAN_FORCE_MANUAL=0; fi
PLAN_COMPACTION=0
oc_stage="$WORK"
RAW="http://local"
bun --no-install "$MIGRATOR" --apply "$CFG/opencode.json" || exit 1
source "$WORK/sec4.sh"
EOS

  echo "=== $name ==="
  local out rc; out="$(HOME="$home" WORK="$work" TPL="$work/tpl.json" CFG="$cfg" OC_MAJOR="$major" FORCE_MANUAL="$force_manual" MIGRATOR="$(npath "$REPO/opencode/migrate-config.mjs")" bash "$work/run.sh" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    check fail "合并子进程退出 $rc；输出: $out"
    rm -rf "$work"
    return
  fi
  local file; file="$([ "$mode" = symlink ] && echo "$dot/opencode.json" || echo "$cfg/opencode.json")"
  local got; got="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
v = d.get(sys.argv[2])
print("False" if v is False else v)
' "$(npath "$file")" "$want_key")"
  if [ "$got" = "$want_val" ]; then check ok "$want_key = $got"; else check fail "$want_key = $got(期望 $want_val);输出: $out"; fi
  if python3 - "$file" "$work/tpl.json" "$dot/opencode.json" <<'PY'
import json, sys
merged = json.load(open(sys.argv[1], encoding="utf-8"))
tpl = json.load(open(sys.argv[2], encoding="utf-8"))
original = json.load(open(sys.argv[3], encoding="utf-8"))
def model_parts(value):
    if isinstance(value, str):
        provider, model = value.split("/", 1)
        model, _, variant = model.partition("#")
        return provider, model, variant or None
    return value.get("providerID"), value.get("model"), value.get("variant")
for role in ("consolidation-reviewer", "verification-reviewer"):
    assert model_parts(merged["agents"][role]["model"]) == model_parts(tpl["agents"][role]["model"]), role
verification = merged["agents"]["verification-reviewer"]
rules = {(r["action"], r["effect"]) for r in verification["permissions"]}
assert ("shell", "allow") in rules and ("edit", "deny") in rules and ("subagent", "deny") in rules
for role, old in original.get("agents", {}).items():
    if "system" in old:
        assert merged["agents"][role]["system"] == old["system"], role
    if role not in ("consolidation-reviewer", "verification-reviewer") and "model" in old:
        assert model_parts(merged["agents"][role]["model"]) == model_parts(old["model"]), role
PY
  then check ok "两种 Reviewer 模型随模板，Verification 可执行，本地提示与其它角色保留"
  else check fail "Reviewer 合并破坏模型、执行权限或本地角色字段"; fi
  case "$out" in *"OpenCode 当前允许自动更新"*) check fail "配置合并阶段恢复询问(输出: $out)" ;; *) check ok "合并只消费前置计划，没有晚问" ;; esac
  if [ "$mode" = symlink ]; then
    if [ -L "$cfg/opencode.json" ]; then check ok "链接保留 → $(readlink "$cfg/opencode.json")"; else check fail "链接被替换成普通文件"; fi
  fi
  rm -rf "$work"
}

link_probe="$(mktemp -d)"; echo x > "$link_probe/t"; ln -s "$link_probe/t" "$link_probe/l" 2>/dev/null
if [ -L "$link_probe/l" ]; then have_symlink=1; else have_symlink=0; fi
rm -rf "$link_probe"
if [ "$have_symlink" = 1 ]; then
  run_case "A 符号链接 + v1 遗留 autoupdate:true(v2 客户端)" symlink '{"$schema":"x","autoupdate":true,"permission":{"*":"allow"}}' 2 update disable 1
else
  echo "SKIP A: 本机 ln -s 会复制文件(Git Bash),链接写穿请在 Linux 上验"
fi
run_case "B 普通文件 + v1 遗留 autoupdate:true(v2 客户端)" plain '{"$schema":"x","autoupdate":true,"permission":{"*":"allow"}}' 2 update disable 1
run_case "C 已有 update:notify" plain '{"$schema":"x","update":"notify","permission":{"*":"allow"}}' 2 update notify 0
run_case "D v1 遗留 autoupdate:false" plain '{"$schema":"x","autoupdate":false,"permission":{"*":"allow"}}' 2 update disable 0
run_case "E v2 配置含本地 Reviewer 提示与自定义角色" plain '{"$schema":"x","permission":{"*":"allow"},"agents":{"verification-reviewer":{"model":"local/old","system":"local-system"},"custom":{"model":"custom/m","system":"keep"}}}' 2 update disable 0

if [ "$fails" -ne 0 ]; then echo "FAIL: $fails 项"; exit 1; fi
echo "PASS: opencode.json 合并的 shell 层(迁移/前置档位/写穿链接/双 Reviewer)"
