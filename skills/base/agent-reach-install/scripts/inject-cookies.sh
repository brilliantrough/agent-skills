#!/usr/bin/env bash
# 把 cookie 注入 Agent Reach 的无头浏览器（不需要桌面、不需要扫码窗口）。
# 用法: bash inject-cookies.sh [cookies.json]
# 也可用环境变量 XHS_COOKIE=<路径>；默认读 ~/.config/agent-reach/xhs-cookies.json
# cookie 文件为 JSON 数组或 {"cookies":[...]}，元素含 name/value/domain/path。
# 只写入 cookie，不删除已有登录态；重复执行结果相同。
set -euo pipefail

COOKIE_FILE="${1:-${XHS_COOKIE:-$HOME/.config/agent-reach/xhs-cookies.json}}"
[ -f "$COOKIE_FILE" ] || { echo "inject-cookies: 找不到 cookie 文件 $COOKIE_FILE" >&2; exit 1; }
export PATH="$HOME/.local/bin:$PATH"
command -v agent-reach >/dev/null 2>&1 || { echo "inject-cookies: 未安装 agent-reach" >&2; exit 1; }
export no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"

# 确保 Node/OpenCLI 与无头浏览器就绪（add 只装工具，不触发登录；重复执行幂等）
agent-reach add xiaohongshu >/dev/null 2>&1 || true
agent-reach browser setup >/dev/null 2>&1 || true

PY="$HOME/.local/share/uv/tools/agent-reach/bin/python"
[ -x "$PY" ] || PY=python3
"$PY" - "$COOKIE_FILE" <<'PY'
import json
import sys
import urllib.request
from websockets.sync.client import connect

path = sys.argv[1]
data = json.load(open(path, encoding='utf-8'))
cookies = data.get('cookies') if isinstance(data, dict) else data
if not isinstance(cookies, list) or not cookies:
    sys.exit('inject-cookies: cookie 文件为空或格式不对')

cdp_cookies = []
for c in cookies:
    if not c.get('name') or c.get('value') is None:
        continue
    item = {
        'name': c['name'],
        'value': str(c['value']),
        'domain': c.get('domain', '.xiaohongshu.com'),
        'path': c.get('path', '/'),
    }
    if c.get('secure') is not None:
        item['secure'] = bool(c['secure'])
    if c.get('httpOnly') is not None:
        item['httpOnly'] = bool(c['httpOnly'])
    if c.get('sameSite'):
        item['sameSite'] = c['sameSite']
    cdp_cookies.append(item)

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
ver = json.load(opener.open('http://127.0.0.1:9222/json/version', timeout=10))
ws_url = ver['webSocketDebuggerUrl']

_id = 0
def rpc(ws, method, params=None):
    global _id
    _id += 1
    ws.send(json.dumps({'id': _id, 'method': method, 'params': params or {}}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get('id') == _id:
            if 'error' in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get('result', {})

with connect(ws_url, open_timeout=20, close_timeout=5) as ws:
    rpc(ws, 'Storage.setCookies', {'cookies': cdp_cookies})
    got = rpc(ws, 'Storage.getCookies').get('cookies', [])

domains = {}
for c in got:
    domains.setdefault(c.get('domain', ''), 0)
    domains[c.get('domain', '')] += 1
print(json.dumps({'injected': len(cdp_cookies), 'domains_in_browser': domains}, ensure_ascii=False))
PY
