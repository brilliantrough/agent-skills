#!/usr/bin/env bash
# module: light-science
# desc: 固定版文献检索与数据图（需 research 组；含非商业许可资源，不装整包）
# default: N
# hosts: any
set -euo pipefail

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) shift 2 ;;
    *) echo "用法: $0 [--host pi|opencode|codex|dsh]" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT/skills-external.sh" --light-science
