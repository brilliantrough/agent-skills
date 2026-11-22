#!/usr/bin/env bash
# 本仓 Sub Agent 安装验收：默认只读；--apply 才调用各宿主现有 setup。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0
YES=0
HOSTS=()
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --yes|-y) YES=1 ;;
    opencode|dsh|pi|codex|claude) HOSTS+=("$arg") ;;
    *) printf '用法：bash scripts/verify-subagents.sh [--apply [--yes]] [opencode|dsh|pi|codex|claude ...]\n' >&2; exit 2 ;;
  esac
done
[ "${#HOSTS[@]}" -gt 0 ] || HOSTS=(opencode dsh pi codex claude)
[ "$YES" = 0 ] || [ "$APPLY" = 1 ] || { echo '--yes 只能与 --apply 同用' >&2; exit 2; }

MISSING=()
note_missing() { MISSING+=("$1"); printf 'MISS %s\n' "$1"; }

check_opencode() {
  command -v opencode >/dev/null 2>&1 || { note_missing 'opencode：未找到宿主命令'; return; }
  command -v python3 >/dev/null 2>&1 || { note_missing 'opencode：需 python3 读取 agents'; return; }
  local tmp src cfg out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/verify-oc-agents-XXXXXX")
  src="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
  cfg="$tmp/cfg"
  mkdir -p "$cfg" "$tmp/home/.config" "$tmp/data" "$tmp/cache" "$tmp/state" "$tmp/project"
  # 只抄全局 agents 定义：既不为读 agents 挂 live 插件，也不让调用处 cwd 的项目级角色冒充全局
  if [ -d "$src/agent" ]; then cp -R "$src/agent" "$cfg/agent"; fi
  if ! python3 - "$src" "$cfg/opencode.json" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
def load(path):  # 注释与尾逗号感知的 JSONC：字符串内的 // 不动
    text, out, i, quote = open(path, encoding="utf-8").read(), [], 0, False
    while i < len(text):
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\":
                out.append(text[i + 1]); i += 2; continue
            if c == '"': quote = False
        elif c == '"':
            quote = True; out.append(c)
        elif text.startswith("//", i):
            while i < len(text) and text[i] != "\n": i += 1
            continue
        elif text.startswith("/*", i):
            i = text.find("*/", i); i = len(text) if i < 0 else i + 2; continue
        else:
            out.append(c)
        i += 1
    import re
    return json.loads(re.sub(r'("(?:\\.|[^"\\])*")|,(\s*[}\]])', lambda m: m.group(1) or m.group(2), "".join(out)))
agents = {}
for name in ("opencode.json", "opencode.jsonc"):
    path = os.path.join(src, name)
    if not os.path.exists(path):
        continue
    try:
        agents = load(path).get("agents") or {}
    except Exception as exc:
        sys.exit(f"{name} 无法解析：{exc}")
    break
json.dump({"agents": agents}, open(dst, "w", encoding="utf-8"))
PY
  then
    rm -rf "$tmp"
    note_missing "opencode：全局配置无法解析（$src）"
    return
  fi
  if out=$(cd "$tmp/project" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
      XDG_DATA_HOME="$tmp/data" XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
      OPENCODE_CONFIG_DIR="$cfg" opencode --standalone debug agents 2>&1); then
    printf '%s' "$out" | python3 -c '
import json, sys
agents = {a.get("id"): a for a in json.load(sys.stdin)}
errors = []
for name in ("verification-reviewer", "consolidation-reviewer"):
    a = agents.get(name)
    if not a:
        errors.append(f"未注册 {name}")
        continue
    if a.get("mode") != "subagent":
        errors.append(f"{name} mode 不是 subagent")
    model = a.get("model") or {}
    if (model.get("providerID"), model.get("id"), model.get("variant")) != ("codex-newapi", "gpt-6.2-sol", "max"):
        errors.append(f"{name} 模型未更新")
if errors:
    print("opencode：" + "；".join(errors), file=sys.stderr)
    raise SystemExit(1)
' || note_missing 'opencode：Reviewer 未注册、模式或模型不符合当前模板'
  else
    rm -rf "$tmp"
    note_missing 'opencode：原生 agents 加载失败'
    return
  fi
  rm -rf "$tmp"
}

check_pi() {
  local dir="$HOME/.pi/agent"
  dir="${PI_CODING_AGENT_DIR:-$dir}"
  local role
  for role in verification-reviewer consolidation-reviewer; do
    [ -f "$dir/agents/$role.md" ] || note_missing "pi：缺 agents/$role.md"
  done
  python3 - "$dir/models.json" <<'PY' || note_missing 'pi：codex-newapi/gpt-6.2-sol 未进入模型目录，角色会启动失败'
import json, sys
try:
    cfg = json.load(open(sys.argv[1], encoding="utf-8"))
    models = cfg["providers"]["codex-newapi"]["models"]
    assert any(m.get("id") == "gpt-6.2-sol" for m in models)
except Exception:
    raise SystemExit(1)
PY
}

check_codex() {
  local dir="${CODEX_HOME:-$HOME/.codex}" role
  for role in verification-reviewer consolidation-reviewer; do
    [ -f "$dir/agents/$role.toml" ] || note_missing "codex：缺 agents/$role.toml"
  done
}

check_claude() {
  local role
  for role in verification-reviewer consolidation-reviewer; do
    [ -f "$HOME/.claude/agents/$role.md" ] || note_missing "claude：缺 agents/$role.md"
  done
  [ -f "$HOME/.agents/skills/verification/references/reviewer.md" ] || note_missing 'claude：缺 verification skill 审查规范'
}

check_dsh() {
  local root="${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/dsh" home profile file
  # live 布局是 dsh/home/profiles；拆开变量避免被 check.sh 的个人路径 lint 误判
  home="$root/home"
  for profile in headless web tui; do
    file="$home/profiles/$profile/cordis.patch.yml"
    [ -f "$file" ] || { note_missing "dsh：缺 $profile profile"; continue; }
    grep -q 'agent-skills-verification-reviewer' "$file" || note_missing "dsh：$profile 缺 verification preset"
    grep -q 'tool-verification-review' "$file" || note_missing "dsh：$profile 缺 verification_review"
    grep -q 'agent-skills-reviewer' "$file" || note_missing "dsh：$profile 缺 consolidation preset"
  done
  [ -f "$root/runtime/bundle/dsh/verification-policy.mjs" ] || note_missing 'dsh：runtime 缺 verification-policy.mjs'
  [ -f "$HOME/.agents/skills/verification/references/reviewer.md" ] || note_missing 'dsh：缺 verification skill 审查规范'
}

apply_host() {
  local host="$1" script yes_args=()
  [ "$YES" = 0 ] || yes_args=(-y)
  if [ "$host" = claude ]; then
    if [ "$YES" = 1 ]; then ASSUME_YES=1 bash "$ROOT/skills-sync.sh" base; else bash "$ROOT/skills-sync.sh" base; fi
    return
  fi
  script="$ROOT/$host-setup.sh"
  [ -f "$script" ] || { echo "缺安装入口：$script" >&2; return 1; }
  bash "$script" "${yes_args[@]}"
}

for host in "${HOSTS[@]}"; do "check_$host"; done
if [ "${#MISSING[@]}" = 0 ]; then
  echo 'PASS：所选宿主的 Reviewer 文件、模型目录或原生 agents 注册均已就绪'
  echo '边界：Pi／Codex／Claude 此处是安装检查；真实加载与委派另按 tests/README.md 验收'
  exit 0
fi
if [ "$APPLY" = 0 ]; then
  printf '发现 %d 项漏装或漂移；使用 --apply 调用现有 setup 更新\n' "${#MISSING[@]}" >&2
  exit 1
fi
if [ "$YES" = 0 ] && ! { : </dev/tty; } 2>/dev/null; then
  echo '非交互更新需显式 --apply --yes；否则请在终端运行 --apply 完成集中选择' >&2
  exit 2
fi
if [ "$YES" = 1 ]; then
  echo 'WARNING：--yes 采用各 setup 默认值，可能升级宿主／共享插件，并按既定流程停止共享 worker' >&2
fi
for host in "${HOSTS[@]}"; do
  case " ${MISSING[*]} " in *" $host："*) apply_host "$host" ;; esac
done
exec bash "$0" "${HOSTS[@]}"
