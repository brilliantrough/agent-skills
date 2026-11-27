#!/usr/bin/env bash
# runtime-deps.sh — Node 24 / Bun(>=1.1.31) / uv 公共探测与安装，及旧 pi-node 就地升级
set -euo pipefail

# ---- 与 pi-setup / opencode-setup / codex-setup 逐字节同步的只读探测（LOCKED）----
node_ver_ge() { # $1=node 路径(空则 PATH 中 node) $2=主版本(默认 24) $3=次版本(默认 15)
  local bin="${1:-}" req_maj="${2:-24}" req_min="${3:-15}" raw maj min
  [ -n "$bin" ] || bin="$(command -v node 2>/dev/null || true)"
  [ -n "$bin" ] && [ -x "$bin" ] || return 1
  raw="$("$bin" -v 2>/dev/null | head -1 | tr -d '\r' || true)"
  raw="${raw#v}"
  case "$raw" in
    [0-9]*.[0-9]*) ;;
    *) return 1 ;;
  esac
  maj="${raw%%.*}"
  min="${raw#*.}"; min="${min%%.*}"; min="${min%%-*}"
  case "$maj" in ''|*[!0-9]*) return 1 ;; esac
  case "$min" in ''|*[!0-9]*) return 1 ;; esac
  [ "$maj" -gt "$req_maj" ] && return 0
  [ "$maj" -eq "$req_maj" ] && [ "$min" -ge "$req_min" ]
}

runtime_activate_fnm() { # 发现并激活已有 fnm；若已装 v24.15+ 则在当前会话切过去（不改 default）
  local fnm_bin="" fnm_dir="" best=""
  fnm_bin="$(command -v fnm 2>/dev/null || true)"
  if [ -z "$fnm_bin" ]; then
    for fnm_dir in "${FNM_DIR:-}" "${XDG_DATA_HOME:-$HOME/.local/share}/fnm" "$HOME/.local/share/fnm" "$HOME/.fnm" "$HOME/Library/Application Support/fnm"; do
      if [ -n "$fnm_dir" ] && [ -x "$fnm_dir/fnm${BIN_EXT:-}" ]; then
        fnm_bin="$fnm_dir/fnm${BIN_EXT:-}"
        break
      fi
    done
    if [ -z "$fnm_bin" ] && [ "${IS_WIN:-0}" = 1 ] && [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
      fnm_dir="$(cygpath -u "$LOCALAPPDATA")/fnm"
      [ -x "$fnm_dir/fnm${BIN_EXT:-}" ] && fnm_bin="$fnm_dir/fnm${BIN_EXT:-}"
    fi
  fi
  [ -n "$fnm_bin" ] && [ -x "$fnm_bin" ] || return 1
  fnm_dir="$(dirname "$fnm_bin")"
  case ":$PATH:" in
    *":$fnm_dir:"*) ;;
    *) export PATH="$fnm_dir:$PATH" ;;
  esac
  eval "$(fnm env --shell bash 2>/dev/null)" || true
  if ! command -v npx >/dev/null 2>&1 || ! node_ver_ge "" 24 15; then
    best="$(fnm list 2>/dev/null | tr -d '\r' | awk '
      {
        n = split($0, f)
        for (k = 1; k <= n; k++) {
          v = f[k]
          if (v ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) {
            s = substr(v, 2); split(s, p, ".")
            maj = p[1] + 0; min = p[2] + 0; pat = p[3] + 0
            if (maj > 24 || (maj == 24 && min >= 15)) {
              if (maj == 24) {
                if (!has24 || min > b24min || (min == b24min && pat > b24pat)) {
                  has24 = 1; b24min = min; b24pat = pat; best24 = v
                }
              } else {
                if (!hasgt || maj > bgtmaj || (maj == bgtmaj && min > bgtmin) || (maj == bgtmaj && min == bgtmin && pat > bgtpat)) {
                  hasgt = 1; bgtmaj = maj; bgtmin = min; bgtpat = pat; bestgt = v
                }
              }
            }
            break
          }
        }
      }
      END { if (has24) print best24; else if (hasgt) print bestgt }
    ')"
    if [ -n "$best" ]; then
      fnm use "$best" >/dev/null 2>&1 || true
    fi
  fi
  return 0
}

bun_probe_state() { # 0=就绪(>=1.1.31 且 bun:sqlite 可用) 1=缺失 2=版本过低 3=sqlite 不可用
  local bin raw maj min pat
  PROBE_BUN_BIN=""; PROBE_BUN_VER=""
  if [ "${IS_WIN:-0}" = 1 ] && [ -n "${BUN_INSTALL:-}" ] && command -v cygpath >/dev/null 2>&1; then
    BUN_INSTALL="$(cygpath -u "$BUN_INSTALL")"; export BUN_INSTALL
  fi
  bin="$(command -v bun 2>/dev/null || true)"
  if [ -z "$bin" ] && [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun${BIN_EXT:-}" ]; then
    bin="${BUN_INSTALL:-$HOME/.bun}/bin/bun${BIN_EXT:-}"
  fi
  [ -n "$bin" ] && [ -x "$bin" ] || return 1
  PROBE_BUN_BIN="$bin"
  raw="$("$bin" --version 2>/dev/null | head -1 | tr -d '\r' || true)"
  PROBE_BUN_VER="$raw"
  raw="${raw#v}"
  raw="${raw%%[-+]*}"
  case "$raw" in
    [0-9]*.[0-9]*.[0-9]*)
      maj="${raw%%.*}"
      pat="${raw#*.}"; min="${pat%%.*}"; pat="${pat#*.}"
      ;;
    [0-9]*.[0-9]*)
      maj="${raw%%.*}"
      min="${raw#*.}"; pat=0
      ;;
    *) return 2 ;;
  esac
  case "$maj" in ''|*[!0-9]*) return 2 ;; esac
  case "$min" in ''|*[!0-9]*) return 2 ;; esac
  case "$pat" in ''|*[!0-9]*) return 2 ;; esac
  if [ "$maj" -lt 1 ] || { [ "$maj" -eq 1 ] && [ "$min" -lt 1 ]; } || { [ "$maj" -eq 1 ] && [ "$min" -eq 1 ] && [ "$pat" -lt 31 ]; }; then
    return 2
  fi
  "$bin" -e 'const {Database}=require("bun:sqlite"); const db=new Database(":memory:"); if(db.query("SELECT 1 AS ok").get().ok!==1) process.exit(1); db.close();' >/dev/null 2>&1 || return 3
  return 0
}

# ---- 统一前置计划与执行 ----
runtime_plan_collect() { # $1=need_node(0/1) $2=need_bun(0/1) $3=need_uv(0/1)
  local need_node="${1:-0}" need_bun="${2:-0}" need_uv="${3:-0}"
  local cur_node="" bun_rc=0 uvp uv_cur uv_latest uvcfg uv_bin

  RUNTIME_NEED_NODE="$need_node"; RUNTIME_NEED_BUN="$need_bun"; RUNTIME_NEED_UV="$need_uv"
  PLAN_NODE=0; PLAN_BUN=0; PLAN_UV_INSTALL=0; PLAN_UV_UPGRADE=0; PLAN_UV_MIRROR=0

  if [ "$need_node" = 1 ]; then
    if ! command -v npx >/dev/null 2>&1 || ! node_ver_ge "" 24 15; then
      runtime_activate_fnm || true
    fi
    if ! command -v npx >/dev/null 2>&1 || ! node_ver_ge "" 24 15; then
      cur_node="$(node -v 2>/dev/null || true)"
      if command -v fnm >/dev/null 2>&1; then
        ask "当前 Node(${cur_node:-缺失}) 低于 24.15 或缺 npx；用 fnm 安装并启用 Node 24？" Y SHARED_NODE && PLAN_NODE=1
      elif [ -n "$cur_node" ]; then
        ask "当前 Node($cur_node) 低于 24.15 或缺 npx；安装 fnm + Node 24？" Y SHARED_NODE && PLAN_NODE=1
      else
        ask "未检测到 Node >=24.15 / npx；安装 fnm + Node 24？" Y SHARED_NODE && PLAN_NODE=1
      fi
    fi
  fi

  if [ "$need_bun" = 1 ]; then
    bun_probe_state || bun_rc=$?
    case "$bun_rc" in
      0) ;;
      1) ask "是否安装 bun（>=1.1.31，claude-mem / OpenCode / context-mode 所需）？" Y SHARED_BUN && PLAN_BUN=1 ;;
      2) ask "检测到 bun(${PROBE_BUN_VER:-未知}) 低于 1.1.31；执行 bun upgrade？" Y SHARED_BUN && PLAN_BUN=2 ;;
      3) echo "WARN: 检测到 bun(${PROBE_BUN_VER:-未知}) 的 bun:sqlite 不可用；执行阶段将中止，请先修复 Bun" >&2
         PLAN_BUN=3 ;;
    esac
  fi

  if [ "$need_uv" = 1 ]; then
    uvp="$HOME/.local/bin/uv${BIN_EXT:-}"
    if ! command -v uv >/dev/null 2>&1 && [ ! -x "$uvp" ]; then
      ask "未检测到 uv,安装 uv(astral.sh 官方脚本,装到 ~/.local/bin)?" Y SHARED_UV_INSTALL && PLAN_UV_INSTALL=1
    fi
    if command -v uv >/dev/null 2>&1 || [ -x "$uvp" ]; then
      uv_bin="$(command -v uv 2>/dev/null || echo "$uvp")"
      uv_cur="$("$uv_bin" --version 2>/dev/null | awk '{print $2}' || true)"
      uv_latest="$(curl -fsSL --connect-timeout 5 -m 8 https://api.github.com/repos/astral-sh/uv/releases/latest 2>/dev/null \
        | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
      if [ -z "$uv_latest" ]; then
        echo "跳过 uv 自升级:查不到最新版本(检查网络/代理)"
      elif [ "$uv_latest" != "$uv_cur" ]; then
        if [ "${IS_WIN:-0}" = 1 ] && [[ "$uv_bin" == */Python*/Scripts/uv* ]]; then
          echo "uv 由 Python 环境安装(${uv_cur:-未知}),请用原安装方式升级;跳过 uv self update"
        else
          ask "uv ${uv_cur:-未知} → $uv_latest,升级(uv self update)?" Y SHARED_UV_UPGRADE && PLAN_UV_UPGRADE=1
        fi
      else
        echo "uv 已是最新(${uv_cur:-未知})"
      fi
    fi
    if command -v uv >/dev/null 2>&1 || [ -x "$uvp" ] || [ "$PLAN_UV_INSTALL" = 1 ]; then
      uvcfg="$HOME/.config/uv/uv.toml"
      if [ "${IS_WIN:-0}" = 1 ] && [ -n "${APPDATA:-}" ]; then uvcfg="$(cygpath -u "$APPDATA")/uv/uv.toml"; fi
      if grep -q 'pypi.tuna' "$uvcfg" 2>/dev/null; then
        echo "uv PyPI 镜像已配置(清华),跳过"
      elif [ -f "$uvcfg" ]; then
        echo "跳过 uv 镜像:$uvcfg 已存在(非本脚本写入),不覆盖"
      else
        ask "配置 uv 用清华 PyPI 镜像($uvcfg)?" Y SHARED_UV_MIRROR && PLAN_UV_MIRROR=1
      fi
    fi
  fi
}

_runtime_find_fnm() {
  local d=""
  FNM_BIN="$(command -v fnm 2>/dev/null || true)"
  [ -n "$FNM_BIN" ] && [ -x "$FNM_BIN" ] && return 0
  FNM_BIN=""
  for d in "${FNM_DIR:-}" "${XDG_DATA_HOME:-$HOME/.local/share}/fnm" "$HOME/.local/share/fnm" "$HOME/.fnm" "$HOME/Library/Application Support/fnm"; do
    if [ -n "$d" ] && [ -x "$d/fnm${BIN_EXT:-}" ]; then
      FNM_BIN="$d/fnm${BIN_EXT:-}"
      return 0
    fi
  done
  if [ "${IS_WIN:-0}" = 1 ] && [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
    d="$(cygpath -u "$LOCALAPPDATA")/fnm"
    if [ -x "$d/fnm${BIN_EXT:-}" ]; then
      FNM_BIN="$d/fnm${BIN_EXT:-}"
      return 0
    fi
  fi
  return 1
}

runtime_apply_node() { # $1=plan_node(0/1)
  local plan_node="${1:-0}" FNM_BIN="" fnm_dir="" fnm_sh="" rc_file="" skip_shell="" best=""
  if ! command -v npx >/dev/null 2>&1 || ! node_ver_ge "" 24 15; then
    runtime_activate_fnm || true
  fi
  if [ "$plan_node" = 1 ]; then
    if ! _runtime_find_fnm; then
      if [ "${IS_WIN:-0}" = 1 ]; then
        skip_shell="--skip-shell"
      else
        case "$(basename "${SHELL:-sh}")" in
          zsh) rc_file="${ZDOTDIR:-$HOME}/.zshrc" ;;
          fish) rc_file="$HOME/.config/fish/conf.d/fnm.fish" ;;
          bash) [ "$(uname -s 2>/dev/null || true)" = Darwin ] && rc_file="$HOME/.profile" || rc_file="$HOME/.bashrc" ;;
          *) rc_file="$HOME/.profile" ;;
        esac
        if [ -f "$rc_file" ] && grep -q 'fnm env' "$rc_file" 2>/dev/null; then
          skip_shell="--skip-shell"
        fi
      fi
      fnm_sh="$(mktemp)" || return 1
      if curl -fsSL --connect-timeout 8 -m 60 -o "$fnm_sh" https://fnm.vercel.app/install; then
        bash "$fnm_sh" ${skip_shell:+"$skip_shell"} || { rm -f "$fnm_sh"; echo "ERROR: fnm 安装失败" >&2; return 1; }
      else
        rm -f "$fnm_sh"; echo "ERROR: fnm 安装脚本下载失败(检查代理)" >&2; return 1
      fi
      rm -f "$fnm_sh"
      _runtime_find_fnm || true
    fi
    [ -n "$FNM_BIN" ] && [ -x "$FNM_BIN" ] || { echo "ERROR: 安装后仍未找到 fnm" >&2; return 1; }
    fnm_dir="$(dirname "$FNM_BIN")"
    case ":$PATH:" in
      *":$fnm_dir:"*) ;;
      *) export PATH="$fnm_dir:$PATH" ;;
    esac
    eval "$(fnm env --shell bash)"
    fnm install 24 || { echo "ERROR: fnm install 24 失败" >&2; return 1; }
    best="$(fnm list 2>/dev/null | tr -d '\r' | awk '
      {
        n = split($0, f)
        for (k = 1; k <= n; k++) {
          v = f[k]
          if (v ~ /^v24\.[0-9]+\.[0-9]+$/) {
            s = substr(v, 2); split(s, p, ".")
            min = p[2] + 0; pat = p[3] + 0
            if (min >= 15 && (!has || min > bmin || (min == bmin && pat > bpat))) {
              has = 1; bmin = min; bpat = pat; best = v
            }
            break
          }
        }
      }
      END { if (has) print best }
    ')"
    [ -n "$best" ] || { echo "ERROR: fnm install 24 后未找到 Node >=24.15" >&2; return 1; }
    fnm default "$best" || return 1
    fnm use "$best" || return 1
    eval "$(fnm env --shell bash)"
    if ! command -v npx >/dev/null 2>&1 || ! node_ver_ge "" 24 15; then
      if [ "${IS_WIN:-0}" = 1 ]; then
        echo "ERROR: 安装后 npx 或 Node >=24.15 仍不可用。可改用 winget install OpenJS.NodeJS.LTS 装 Node,重开 Git Bash 后重跑本脚本。" >&2
      else
        echo "ERROR: 安装后 npx 或 Node >=24.15 仍不可用,请重开终端后重跑本脚本" >&2
      fi
      return 1
    fi
    echo "Node $(node --version) 就绪"
  elif ! command -v npx >/dev/null 2>&1 || ! node_ver_ge "" 24 15; then
    echo "跳过 Node >=24.15(claude-mem、外部 skills 与 context-mode v2 可能不可用)"
  fi
}

runtime_apply_bun() { # $1=plan_bun(0=跳过/已就绪,1=安装,2=升级,3=sqlite损坏)
  local plan_bun="${1:-0}" bun_sh="" bun_bin="" rc=0
  if [ "${IS_WIN:-0}" = 1 ] && [ -n "${BUN_INSTALL:-}" ] && command -v cygpath >/dev/null 2>&1; then
    BUN_INSTALL="$(cygpath -u "$BUN_INSTALL")"; export BUN_INSTALL
  fi
  if [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun${BIN_EXT:-}" ]; then
    export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
  fi
  if [ "$plan_bun" = 1 ]; then
    bun_sh="$(mktemp)" || return 1
    if curl -fsSL --connect-timeout 8 -m 60 -o "$bun_sh" https://bun.sh/install; then
      bash "$bun_sh" || { rm -f "$bun_sh"; echo "ERROR: bun 安装失败" >&2; return 1; }
    else
      rm -f "$bun_sh"; echo "ERROR: bun 安装脚本下载失败(检查代理)" >&2; return 1
    fi
    rm -f "$bun_sh"
    export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
  elif [ "$plan_bun" = 2 ]; then
    bun_bin="$(command -v bun 2>/dev/null || true)"
    [ -n "$bun_bin" ] || bun_bin="${BUN_INSTALL:-$HOME/.bun}/bin/bun${BIN_EXT:-}"
    if [ -x "$bun_bin" ]; then
      "$bun_bin" upgrade || { echo "WARN: bun upgrade 失败" >&2; return 1; }
    fi
  fi
  bun_probe_state || rc=$?
  if [ "$rc" = 0 ]; then
    BUN_BIN="$PROBE_BUN_BIN"; export BUN_BIN
    "$BUN_BIN" --version
    return 0
  elif [ "$rc" = 3 ] || [ "$plan_bun" != 0 ]; then
    echo "ERROR: Bun 不可用、版本低于 1.1.31 或 bun:sqlite 不可用;请修复 Bun 后重跑" >&2
    return 1
  else
    BUN_BIN="${PROBE_BUN_BIN:-bun}"
    echo "跳过 bun；相关依赖由官方安装器检查。"
  fi
}

runtime_apply_uv() { # $1=install(0/1) $2=upgrade(0/1) $3=mirror(0/1)
  local plan_install="${1:-0}" plan_upgrade="${2:-0}" plan_mirror="${3:-0}"
  local uvp uv_sh uv_bin uvcfg uv_cur
  uvp="$HOME/.local/bin/uv${BIN_EXT:-}"
  if ! command -v uv >/dev/null 2>&1 && [ ! -x "$uvp" ]; then
    if [ "$plan_install" = 1 ]; then
      uv_sh="$(mktemp)" || return 1
      if curl -fsSL --connect-timeout 8 -m 60 -o "$uv_sh" https://astral.sh/uv/install.sh; then
        UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$uv_sh" \
          || echo "WARN: uv 安装脚本退出码非 0,请看上方输出" >&2
      else
        echo "WARN: uv 安装脚本下载失败(检查代理)" >&2
      fi
      rm -f "$uv_sh"
    fi
  fi
  uv_bin="$(command -v uv 2>/dev/null || echo "$uvp")"
  if [ -x "$uv_bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
    if [ "$plan_upgrade" = 1 ]; then
      uv_cur="$("$uv_bin" --version 2>/dev/null | awk '{print $2}' || true)"
      if [ "${IS_WIN:-0}" = 1 ] && [[ "$uv_bin" == */Python*/Scripts/uv* ]]; then
        echo "uv 由 Python 环境安装(${uv_cur:-未知}),请用原安装方式升级;跳过 uv self update"
      else
        "$uv_bin" self update || echo "WARN: uv 自升级失败(系统包管理器装的请用系统方式升级)" >&2
      fi
    fi
    uvcfg="$HOME/.config/uv/uv.toml"
    if [ "${IS_WIN:-0}" = 1 ] && [ -n "${APPDATA:-}" ]; then uvcfg="$(cygpath -u "$APPDATA")/uv/uv.toml"; fi
    if [ "$plan_mirror" = 1 ]; then
      if grep -q 'pypi.tuna' "$uvcfg" 2>/dev/null; then
        echo "uv PyPI 镜像已配置(清华),跳过"
      elif [ -f "$uvcfg" ]; then
        echo "跳过 uv 镜像:$uvcfg 已存在(非本脚本写入),不覆盖"
      else
        mkdir -p "$(dirname "$uvcfg")"
        printf '%s\n' 'index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"' > "$uvcfg"
        echo "wrote: $uvcfg"
      fi
    fi
  else
    echo "提示: 未检测到 uv;strictdoc 模块会跳过安装(.sdoc 校验依赖),装好 uv 后重跑本脚本即可"
  fi
}

runtime_apply() {
  if [ "${RUNTIME_NEED_NODE:-0}" = 1 ]; then
    runtime_apply_node "${PLAN_NODE:-0}" || return 1
  fi
  if [ "${RUNTIME_NEED_BUN:-0}" = 1 ]; then
    runtime_apply_bun "${PLAN_BUN:-0}" || return 1
  fi
  if [ "${RUNTIME_NEED_UV:-0}" = 1 ]; then
    runtime_apply_uv "${PLAN_UV_INSTALL:-0}" "${PLAN_UV_UPGRADE:-0}" "${PLAN_UV_MIRROR:-0}" || return 1
  fi
  if [ "${RUNTIME_NEED_NODE:-0}" = 1 ] && [ "${RUNTIME_NEED_BUN:-0}" = 1 ] && [ "${RUNTIME_NEED_UV:-0}" = 1 ]; then
    export AGENT_SKILLS_RUNTIME_DONE=1
  fi
}

runtime_upgrade_pi_node24() { # 将旧 pi-node/current(<24.15) 安全就地升到 Node 24；保留旧 22 回滚并重装全局包
  [ "${IS_WIN:-0}" != 1 ] || return 0
  local pi_node_dir current old_target old_node platform dist_base tmp_dir=""
  local shasum_line expected_sha tar_file extract_dir node_name dest_dir rc had_pi=0 pkg_line
  local pkgs=()
  pi_node_dir="${PI_NODE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/pi-node}"
  if [ -z "${PI_NODE_DIR:-}" ] && [ ! -e "$pi_node_dir/current" ] && [ ! -L "$pi_node_dir/current" ] && [ -e "$HOME/.local/share/pi-node/current" ]; then
    pi_node_dir="$HOME/.local/share/pi-node"
  fi
  current="$pi_node_dir/current"
  if [ ! -e "$current" ] && [ ! -L "$current" ]; then
    return 0
  fi
  if [ ! -L "$current" ]; then
    echo "WARN: $current 不是符号链接，拒绝自动升级；请手工升级或迁移" >&2
    return 1
  fi
  old_target="$(readlink "$current")" || return 1
  old_node="$current/bin/node"
  if [ ! -x "$old_node" ]; then
    echo "WARN: $old_node 不可执行，拒绝自动升级 pi-node" >&2
    return 1
  fi
  if node_ver_ge "$old_node" 24 15; then
    return 0
  fi

  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64|Linux-amd64) platform=linux-x64 ;;
    Linux-aarch64|Linux-arm64) platform=linux-arm64 ;;
    Darwin-x86_64) platform=darwin-x64 ;;
    Darwin-arm64) platform=darwin-arm64 ;;
    *) echo "ERROR: 不支持的平台 $(uname -s)-$(uname -m)，无法自动升级 pi-node" >&2; return 1 ;;
  esac

  [ -x "$current/bin/pi" ] && had_pi=1
  if [ -d "$current/lib/node_modules" ]; then
    while IFS= read -r pkg_line; do
      [ -n "$pkg_line" ] && pkgs+=("$pkg_line")
    done < <(python3 - "$current/lib/node_modules" <<'PYEOF'
import json, os, sys
root = sys.argv[1]
skip = {"npm", "corepack"}
def emit(pkg_dir):
    pj = os.path.join(pkg_dir, "package.json")
    if not os.path.isfile(pj):
        return
    try:
        data = json.load(open(pj, encoding="utf-8"))
    except Exception:
        return
    name, ver = data.get("name"), data.get("version")
    if isinstance(name, str) and name and isinstance(ver, str) and ver:
        print(f"{name}@{ver}")
for entry in sorted(os.listdir(root)):
    if entry.startswith(".") or entry in skip:
        continue
    full = os.path.join(root, entry)
    if not os.path.isdir(full):
        continue
    if entry.startswith("@"):
        for sub in sorted(os.listdir(full)):
            if not sub.startswith("."):
                sub_full = os.path.join(full, sub)
                if os.path.isdir(sub_full):
                    emit(sub_full)
    else:
        emit(full)
PYEOF
)
  fi

  dist_base="${PI_NODE_DIST_BASE:-https://nodejs.org/dist/latest-v24.x}"
  dist_base="${dist_base%/}"
  tmp_dir="$(mktemp -d "$pi_node_dir/.upgrade-tmp-XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 8 -m 60 "$dist_base/SHASUMS256.txt" -o "$tmp_dir/SHASUMS256.txt"; then
    rm -rf "$tmp_dir"; echo "ERROR: 下载 Node 24 校验清单失败($dist_base/SHASUMS256.txt)" >&2; return 1
  fi
  shasum_line="$(awk -v suffix="-$platform.tar.gz" '
    NF >= 2 && $2 ~ /^node-v24\.[0-9]+\.[0-9]+-/ && length($2) >= length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix {
      print $1 " " $2; exit
    }
  ' "$tmp_dir/SHASUMS256.txt")"
  if [ -z "$shasum_line" ]; then
    rm -rf "$tmp_dir"; echo "ERROR: SHASUMS256.txt 中找不到 -$platform.tar.gz 的 Node 24 包" >&2; return 1
  fi
  expected_sha="${shasum_line%% *}"
  tar_file="${shasum_line#* }"
  case "$tar_file" in
    ""|*/*|*..*) rm -rf "$tmp_dir"; echo "ERROR: 非法 Node 压缩包名: $tar_file" >&2; return 1 ;;
  esac
  if ! curl -fsSL --connect-timeout 8 -m 180 "$dist_base/$tar_file" -o "$tmp_dir/$tar_file"; then
    rm -rf "$tmp_dir"; echo "ERROR: 下载 $tar_file 失败" >&2; return 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$tmp_dir" && printf '%s  %s\n' "$expected_sha" "$tar_file" | sha256sum -c - >/dev/null) || {
      rm -rf "$tmp_dir"; echo "ERROR: $tar_file SHA256 校验失败" >&2; return 1; }
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$tmp_dir" && printf '%s  %s\n' "$expected_sha" "$tar_file" | shasum -a 256 -c - >/dev/null) || {
      rm -rf "$tmp_dir"; echo "ERROR: $tar_file SHA256 校验失败" >&2; return 1; }
  else
    python3 - "$tmp_dir/$tar_file" "$expected_sha" <<'PYEOF' || { rm -rf "$tmp_dir"; echo "ERROR: $tar_file SHA256 校验失败" >&2; return 1; }
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(65536), b""):
        h.update(chunk)
sys.exit(0 if h.hexdigest().lower() == sys.argv[2].lower() else 1)
PYEOF
  fi

  extract_dir="$tmp_dir/extract"
  mkdir -p "$extract_dir"
  if ! tar -xzf "$tmp_dir/$tar_file" -C "$extract_dir" --strip-components=1; then
    rm -rf "$tmp_dir"; echo "ERROR: 解包 $tar_file 失败" >&2; return 1
  fi
  if ! node_ver_ge "$extract_dir/bin/node" 24 15; then
    rm -rf "$tmp_dir"; echo "ERROR: 解包后的 Node 版本低于 24.15" >&2; return 1
  fi

  if [ "${#pkgs[@]}" -gt 0 ]; then
    echo "重装原 pi-node 全局包到 Node 24: ${pkgs[*]}"
    if ! PATH="$extract_dir/bin:$PATH" "$extract_dir/bin/npm" install -g --prefix "$extract_dir" --ignore-scripts --no-audit --no-fund "${pkgs[@]}"; then
      rm -rf "$tmp_dir"; echo "ERROR: 全局包重装失败，保留原 pi-node/current ($old_target)" >&2; return 1
    fi
  fi
  if [ "$had_pi" = 1 ]; then
    if [ ! -x "$extract_dir/bin/pi" ] || ! PATH="$extract_dir/bin:$PATH" "$extract_dir/bin/pi" --version >/dev/null 2>&1; then
      rm -rf "$tmp_dir"; echo "ERROR: 新 pi-node 中 pi 验证失败，保留原 pi-node/current ($old_target)" >&2; return 1
    fi
  fi

  node_name="${tar_file%.tar.gz}"
  dest_dir="$pi_node_dir/$node_name"
  if [ -e "$dest_dir" ]; then
    mv "$dest_dir" "$dest_dir.bak-$(date +%Y%m%d%H%M%S)-$$" || { rm -rf "$tmp_dir"; return 1; }
  fi
  if ! mv "$extract_dir" "$dest_dir"; then
    rm -rf "$tmp_dir"; echo "ERROR: 移动新 pi-node 目录失败，保留原 current ($old_target)" >&2; return 1
  fi
  rm -rf "$tmp_dir"
  if ! ln -sfn "$dest_dir" "$current"; then
    echo "ERROR: 切换 $current 软链失败；旧版本仍在 $old_target" >&2
    return 1
  fi
  export PATH="$current/bin:$PATH"
  echo "pi-node 已升级到 $node_name (回滚: ln -sfn \"$old_target\" \"$current\")"
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] && grep -q 'pi-node/node-v22' "$rc" 2>/dev/null; then
      echo "WARN: $rc 硬编码了旧版 pi-node/node-v22 路径，建议改为 $current/bin" >&2
    fi
  done
}
