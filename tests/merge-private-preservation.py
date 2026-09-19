#!/usr/bin/env python3
"""安装脚本的字段级合并必须保留本机私密值(隐私内容永不覆盖)。

规则:模板只补本地没有的键;键名命中 SENSITIVE(api key/secret/token/url/host/`*_KEY` 等)
或模板值是 <占位符> 时,一律保留本地值。其余非私密键按模板更新。

用法:python3 tests/merge-private-preservation.py   退出码 0 = 通过
"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = re.compile(r'python3 - "\$dest" "\$tmp" "\$cand" <<\'PYEOF\'\n(.*?)\nPYEOF', re.S)

LOCAL = {
    "apiKey": "sk-LOCAL",
    "providers": {"gw": {"baseUrl": "https://private.example/v1", "apiKey": "sk-LOCAL2", "models": ["m1"]}},
    "NOTIFY_INGEST_KEY": "local-ingest",
    "mcp": {"hub": {"url": "https://private.example/mcp"}},
    "defaultModel": "old-model",
    "localOnly": {"keep": True},
    "nested": {"retry": {"baseDelayMs": 1000, "enabled": False}},
    "packages": ["npm:a", "npm:local-only"],
    "enabledModels": ["m1"],
}
TEMPLATE = {
    "apiKey": "TEMPLATE-KEY",
    "providers": {"gw": {"baseUrl": "https://<YOUR_GATEWAY_HOST>/v1", "apiKey": "TEMPLATE2", "models": ["m2", "m1"]}},
    "NOTIFY_INGEST_KEY": "template-ingest",
    "mcp": {"hub": {"url": "https://<YOUR_MCPHUB_HOST>/mcp/web"}},
    "defaultModel": "deepseek-flash",
    "nested": {"retry": {"baseDelayMs": 4000, "enabled": True}},
    "newKey": "from-template",
    "packages": ["npm:a", "npm:b"],
    "enabledModels": ["m1", "m2"],
}
# (路径, 期望值, 期待来自哪一侧)
EXPECT = [
    ("apiKey", "sk-LOCAL", "local"),
    ("providers.gw.baseUrl", "https://private.example/v1", "local"),
    ("providers.gw.apiKey", "sk-LOCAL2", "local"),
    ("NOTIFY_INGEST_KEY", "local-ingest", "local"),
    ("mcp.hub.url", "https://private.example/mcp", "local"),
    ("localOnly.keep", True, "local"),
    ("defaultModel", "deepseek-flash", "template"),
    ("nested.retry.baseDelayMs", 4000, "template"),
    ("newKey", "from-template", "template"),
    # 列表键走并集:本地顺序保留,模板新增追加上去(不能整表替换掉本机装过的包)
    ("packages", ["npm:a", "npm:local-only", "npm:b"], "template(并集)"),
    ("enabledModels", ["m1", "m2"], "template(并集)"),
]


def dig(node, path):
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return "<missing>"
        node = node[part]
    return node


def engines():
    for script in ("pi-setup.sh", "opencode-setup.sh", "codex-setup.sh"):
        text = (ROOT / script).read_text(encoding="utf-8")
        match = SCRIPT.search(text)
        if not match:
            raise SystemExit(f"STOP: 在 {script} 里找不到合并引擎")
        yield script, match.group(1)


def run_engine(body, tmp):
    engine = tmp / "engine.py"
    engine.write_text(body, encoding="utf-8")
    dest, tpl, cand = tmp / "dest.json", tmp / "tpl.json", tmp / "cand.json"
    dest.write_text(json.dumps(LOCAL, indent=2), encoding="utf-8")
    tpl.write_text(json.dumps(TEMPLATE, indent=2), encoding="utf-8")
    proc = subprocess.run([sys.executable, str(engine), str(dest), str(tpl), str(cand)],
                          capture_output=True, text=True)
    if proc.returncode:
        raise SystemExit(f"STOP: 合并引擎退出码 {proc.returncode}: {proc.stderr.strip()}")
    return json.loads(cand.read_text(encoding="utf-8"))


def main():
    failures = []
    for script, body in engines():
        with tempfile.TemporaryDirectory() as d:
            merged = run_engine(body, pathlib.Path(d))
        for path, want, side in EXPECT:
            got = dig(merged, path)
            if got != want:
                failures.append(f"{script}: {path} = {got!r},期望 {want!r}(应保留{side}侧)")
        print(f"{script}: 检查 {len(EXPECT)} 项")
    if failures:
        print("\n".join(f"FAIL {f}" for f in failures))
        return 1
    print("PASS: 私密键(api key/url/host/*_KEY)保留本机值,非私密键随模板更新,本地独有键不丢,列表键走并集")
    return 0


if __name__ == "__main__":
    sys.exit(main())
