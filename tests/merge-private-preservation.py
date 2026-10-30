#!/usr/bin/env python3
"""安装脚本的字段级合并必须保留本机私密值(隐私内容永不覆盖)。

规则:模板补齐缺失键;键名命中 SENSITIVE(api key/secret/token/url/host/`*_KEY` 等)
或模板值是 <占位符> 时,一律保留本地值。CLAUDE_MEM_*_MODEL 随模板更新。其余非私密键按模板更新。
另外检查占位符填空:三个 <YOUR_NEWAPI_API_KEY> 必须各归各的 provider,embedding 与 claude-mem 不能串。

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
OC_MERGE = re.compile(r'python3 - "\$CFG/opencode\.json" "\$CFG/opencode\.jsonc" "\$oc_tpl" "\$oc_cand" "\$OC_MAJOR" "\$oc_force_manual" <<\'PYEOF\'\n(.*?)\nPYEOF', re.S)
OC_UPDATE = re.compile(r"python3 - \"\$oc_target\" \"\$OC_MAJOR\" <<'PY_OC_UPDATE'\n(.*?)\nPY_OC_UPDATE", re.S)
FILL = re.compile(r'python3 - "\$1" "\$GW_BASE" "\$K_CLAUDE" "\$K_CODEX" "\$K_ANTHROPIC" "\$K_GEMINI" "\$K_EMBED" "\$K_MEM" "\$MCPHUB_HOST" <<\'PYEOF\'\n(.*?)\nPYEOF', re.S)

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
    "todowrite": {"overlay": False},
    "CLAUDE_MEM_OPENROUTER_MODEL": "deepseek-flash",
    "CLAUDE_MEM_OPENROUTER_BASE_URL": "https://local.example/v1",
    "CLAUDE_MEM_OPENROUTER_API_KEY": "sk-LOCAL-MEM",
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
    "todowrite": {"enabled": True, "overlay": False},
    "CLAUDE_MEM_OPENROUTER_MODEL": "deepseek-flash",
    "CLAUDE_MEM_OPENROUTER_BASE_URL": "https://<YOUR_GATEWAY_HOST>/v1",
    "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>",
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
    # claude-mem 已有模型、地址与 key 都保留本机。
    ("CLAUDE_MEM_OPENROUTER_MODEL", "deepseek-flash", "template"),
    ("CLAUDE_MEM_OPENROUTER_BASE_URL", "https://local.example/v1", "local"),
    ("CLAUDE_MEM_OPENROUTER_API_KEY", "sk-LOCAL-MEM", "local"),
    # magic-context 的 todowrite:老机器只有 overlay,模板必须补上 enabled
    # (enabled 默认 false,不写就没有 todo 工具和 /todos 命令)
    ("todowrite.enabled", True, "template"),
    ("todowrite.overlay", False, "template"),
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
        fill = FILL.search(text)
        if not fill:
            raise SystemExit(f"STOP: 在 {script} 里找不到占位符填空引擎")
        yield script, match.group(1), fill.group(1)


def run_engine(body, tmp):
    engine = tmp / "engine.py"
    engine.write_text(body, encoding="utf-8")
    dest, tpl, cand = tmp / "dest.json", tmp / "tpl.json", tmp / "cand.json"
    dest.write_text(json.dumps(LOCAL, indent=2), encoding="utf-8")
    tpl.write_text(json.dumps(TEMPLATE, indent=2), encoding="utf-8")
    proc = subprocess.run([sys.executable, str(engine), str(dest), str(tpl), str(cand)],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode:
        raise SystemExit(f"STOP: 合并引擎退出码 {proc.returncode}: {proc.stderr.strip()}")
    return json.loads(cand.read_text(encoding="utf-8"))


GW = "https://api.pezayo.com/v1"
KEYS = ("sk-claude", "sk-codex", "sk-anth", "sk-gemini", "sk-embed", "sk-mem")
PROVIDERS = ("claude-newapi", "codex-newapi", "anthropic-newapi", "gemini-newapi")
P_SLOT = "<YOUR_NEWAPI_API_KEY>"
BASE_SLOT = "https://<YOUR_GATEWAY_HOST>/v1"
SAMPLE_OC = {
    "provider": {p: {"options": {"baseURL": BASE_SLOT, "apiKey": P_SLOT}} for p in PROVIDERS},
    "mcp": {"mcphub-web": {"url": "https://<YOUR_MCPHUB_HOST>/mcp/web"}},
}
SAMPLE_PI = {"providers": {p: {"baseUrl": "https://<YOUR_GATEWAY_HOST>", "apiKey": P_SLOT} for p in PROVIDERS}}
SAMPLE_MC = {"embedding": {"provider": "openai-compatible", "model": "text-embedding-3-large",
                              "endpoint": BASE_SLOT, "api_key": "<YOUR_API_KEY>"}}
SAMPLE_MEM = {"CLAUDE_MEM_PROVIDER": "openrouter", "CLAUDE_MEM_OPENROUTER_BASE_URL": BASE_SLOT,
              "CLAUDE_MEM_OPENROUTER_MODEL": "deepseek-flash", "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>"}


def run_fill(body, tmp, name, data):
    engine = tmp / f"fill-{name}.py"
    engine.write_text(body, encoding="utf-8")
    target = tmp / f"target-{name}"
    target.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    proc = subprocess.run([sys.executable, str(engine), str(target), GW, *KEYS, "mcp.example.com"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode:
        raise SystemExit(f"STOP: 填空引擎退出码 {proc.returncode}: {proc.stderr.strip()}")
    return json.loads(target.read_text(encoding="utf-8"))


def check_fill(script, body, tmp):
    """6 个 key 必须各归各处(四个 newapi provider 不能串,embedding 与 claude-mem 不能串)。"""
    fails = []
    oc = run_fill(body, tmp, "opencode.json", SAMPLE_OC)
    for i, prov in enumerate(PROVIDERS):
        node = oc["provider"][prov]["options"]
        if node["apiKey"] != KEYS[i]:
            fails.append(f"{script}: opencode.json {prov} 的 apiKey = {node['apiKey']!r},期望 {KEYS[i]!r}")
        if node["baseURL"] != GW:
            fails.append(f"{script}: opencode.json {prov} 的 baseURL = {node['baseURL']!r},期望 {GW!r}")
    if oc["mcp"]["mcphub-web"]["url"] != "https://mcp.example.com/mcp/web":
        fails.append(f"{script}: mcphub url 没填上")

    pi = run_fill(body, tmp, "models.json", SAMPLE_PI)
    for i, prov in enumerate(PROVIDERS):
        if pi["providers"][prov]["apiKey"] != KEYS[i]:
            fails.append(f"{script}: models.json {prov} 的 apiKey = {pi['providers'][prov]['apiKey']!r},期望 {KEYS[i]!r}")

    mc = run_fill(body, tmp, "magic-context.json", SAMPLE_MC)
    if mc["embedding"]["api_key"] != KEYS[4]:
        fails.append(f"{script}: embedding api_key = {mc['embedding']['api_key']!r},期望 {KEYS[4]!r}")
    if mc["embedding"]["endpoint"] != GW:
        fails.append(f"{script}: embedding endpoint = {mc['embedding']['endpoint']!r},期望 {GW!r}")

    mem = run_fill(body, tmp, "claude-mem.settings.json", SAMPLE_MEM)
    if mem["CLAUDE_MEM_OPENROUTER_API_KEY"] != KEYS[5]:
        fails.append(f"{script}: claude-mem 的 key = {mem['CLAUDE_MEM_OPENROUTER_API_KEY']!r},期望 {KEYS[5]!r}")
    if mem["CLAUDE_MEM_OPENROUTER_BASE_URL"] != GW:
        fails.append(f"{script}: claude-mem 的 BASE_URL 没填上")

    # 半填状态(一个 provider 已填真值):不能再动它,也不能把它的 key 抢去填隔壁
    half = json.loads(json.dumps(SAMPLE_OC))
    half["provider"]["claude-newapi"]["options"]["apiKey"] = "sk-real-claude"
    half = run_fill(body, tmp, "half.json", half)
    if half["provider"]["claude-newapi"]["options"]["apiKey"] != "sk-real-claude":
        fails.append(f"{script}: 已填好的 claude-newapi 的 key 被改掉了")
    if half["provider"]["codex-newapi"]["options"]["apiKey"] != KEYS[1]:
        fails.append(f"{script}: 半填状态下 codex-newapi 没拿到自己的 key")
    return fails


# deprecated: mcphub-web-rename；随迁移脚本退役删除。
def check_web_migration():
    entry = {"url": "https://private.example/mcp/web", "headers": {"Authorization": "sentinel"},
             "enabled": False, "toolExposure": {"search": "deferred"}}
    for host, keys in (("pi", ["mcpServers"]), ("opencode", ["mcp"]), ("opencode", ["mcp", "servers"])):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "config.jsonc"
            config: dict = {"unrelated": {"keep": True}}
            group = config
            for key in keys:
                group = group.setdefault(key, {})
            group.update({"mcphub-web": entry, "web": {"url": "https://<YOUR_MCPHUB_HOST>/mcp/web"}})
            path.write_text("// JSONC\n" + json.dumps(config), encoding="utf-8")
            before = path.read_bytes()
            cmd = [sys.executable, str(ROOT / "migrate-web-mcp.py"), host, str(path)]
            subprocess.run(cmd, check=True, capture_output=True)
            assert path.read_bytes() == before and not list(path.parent.glob("*.bak-*"))
            subprocess.run(cmd + ["--apply"], check=True, capture_output=True)
            migrated = json.loads(path.read_text(encoding="utf-8"))
            servers = migrated
            for key in keys:
                servers = servers[key]
            assert servers == {"web": entry} and migrated["unrelated"] == config["unrelated"]
            assert next(path.parent.glob("*.bak-web-*")).read_bytes() == before
            first = path.read_bytes()
            subprocess.run(cmd + ["--apply"], check=True, capture_output=True)
            assert path.read_bytes() == first and len(list(path.parent.glob("*.bak-web-*"))) == 1
            group["web"]["url"] = "https://different.example/mcp/web"
            path.write_text(json.dumps(config), encoding="utf-8")
            before = path.read_bytes()
            result = subprocess.run(cmd + ["--apply"], capture_output=True)
            assert result.returncode != 0 and path.read_bytes() == before
    match = SCRIPT.search((ROOT / "pi-setup.sh").read_text(encoding="utf-8"))
    assert match is not None
    body = match.group(1)
    with tempfile.TemporaryDirectory() as d:
        dest, tpl, cand = [pathlib.Path(d) / name for name in ("dest.json", "tpl.json", "cand.json")]
        dest.write_text(json.dumps({"mcpServers": {"web": entry}}))
        tpl.write_text(json.dumps({"mcpServers": {"web": {"exposure": "direct", "toolExposure": {"search": "direct"}}, "codegraph": {"command": "codegraph"}}}))
        subprocess.run([sys.executable, "-", str(dest), str(tpl), str(cand)], input=body, text=True, encoding="utf-8", errors="replace", check=True, capture_output=True)
        assert json.loads(cand.read_text(encoding="utf-8"))["mcpServers"]["web"] == entry
    print("web MCP: Pi / OpenCode v1/v2，预览、备份、凭据/禁用/工具保留、幂等、冲突保留通过")


def run_oc_merge(body, tmp, live, major, force):
    engine = tmp / "oc_engine.py"
    engine.write_text(body, encoding="utf-8")
    target, jsonc, tpl, cand = tmp / "opencode.json", tmp / "opencode.jsonc", tmp / "tpl.json", tmp / "cand.json"
    target.write_text(json.dumps(live, indent=2), encoding="utf-8")
    tpl.write_text(json.dumps({"$schema": "x", "autoupdate": False, "retry": {"enabled": True}}, indent=2), encoding="utf-8")
    proc = subprocess.run(
        [sys.executable, str(engine), str(target), str(jsonc), str(tpl), str(cand), major, "1" if force else "0"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode:
        raise SystemExit(f"STOP: opencode.json 合并引擎退出码 {proc.returncode}: {proc.stderr.strip()}")
    return json.loads(cand.read_text(encoding="utf-8"))


def check_opencode_update_policy():
    match = OC_MERGE.search((ROOT / "opencode-setup.sh").read_text(encoding="utf-8"))
    assert match is not None, "opencode-setup.sh 里找不到 opencode.json 合并引擎"
    body = match.group(1)
    cases = [
        ({"update": "notify"}, "2", False, "update", "notify", "本机显式档位保留"),
        ({"update": "auto"}, "2", True, "update", "disable", "确认后改成手动"),
        ({"autoupdate": True}, "2", False, "update", "disable", "v1 遗留 auto 按默认关"),
        ({"autoupdate": True}, "2", True, "update", "disable", "v1 遗留 auto 确认后关"),
        ({}, "1", False, "autoupdate", False, "v1 首次写入默认关"),
        ({"autoupdate": True}, "1", True, "autoupdate", False, "v1 确认后关"),
    ]
    for live, major, force, key, want, why in cases:
        with tempfile.TemporaryDirectory() as d:
            merged = run_oc_merge(body, pathlib.Path(d), live, major, force)
        got = merged.get(key)
        assert got == want, f"v{major} {why}: {key} = {got!r},期望 {want!r}"
        if major == "2":
            assert "autoupdate" not in merged, f"v2 仍留着 v1 的 autoupdate: {merged.get('autoupdate')!r}"
        else:
            assert "update" not in merged, "v1 不该写入 v2 原生字段 update"
    print(f"opencode.json: 自动更新档位检查 {len(cases)} 项")


def check_opencode_update_detection():
    """档位探测:只有 auto/true 才需要询问;notify/disable/false 是本机明确选择。"""
    text = (ROOT / "opencode-setup.sh").read_text(encoding="utf-8")
    match = OC_UPDATE.search(text)
    assert match is not None, "opencode-setup.sh 里找不到自动更新档位探测片段"
    engine = match.group(1)
    cases = [
        ({"update": "auto"}, "2", "auto"),
        ({"update": "notify"}, "2", "keep"),
        ({"update": "disable"}, "2", "keep"),
        ({"autoupdate": True}, "2", "auto"),      # v2 仍带着 v1 字段
        ({"autoupdate": False}, "2", "keep"),
        ({}, "2", None),                          # 没写过档位:交给合并默认值
        ({"autoupdate": True}, "1", "auto"),
        ({"autoupdate": "notify"}, "1", "keep"),
        ({"autoupdate": False}, "1", "keep"),
    ]
    for live, major, want in cases:
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "opencode.json"
            path.write_text(json.dumps(live), encoding="utf-8")
            proc = subprocess.run([sys.executable, "-c", engine, str(path), major],
                                  capture_output=True, text=True, encoding="utf-8", errors="replace")
        got = proc.stdout.strip() or None
        assert got == want, f"v{major} {live}: 探测 = {got!r},期望 {want!r}"
    print(f"opencode.json: 档位探测检查 {len(cases)} 项")


def check_todowrite_takeover(body, tmp):
    """显式 enabled:false 也要被模板接管:分发套件要求跑完脚本就有 todo 工具。"""
    engine = tmp / "engine.py"
    engine.write_text(body, encoding="utf-8")
    dest, tpl, cand = tmp / "dest.json", tmp / "tpl.json", tmp / "cand.json"
    dest.write_text(json.dumps({"todowrite": {"enabled": False, "overlay": True}}), encoding="utf-8")
    tpl.write_text(json.dumps({"todowrite": {"enabled": True, "overlay": False}}), encoding="utf-8")
    proc = subprocess.run([sys.executable, str(engine), str(dest), str(tpl), str(cand)],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode:
        return [f"todowrite 接管检查: 引擎退出码 {proc.returncode}: {proc.stderr.strip()}"]
    got = json.loads(cand.read_text(encoding="utf-8"))["todowrite"]
    want = {"enabled": True, "overlay": False}
    return [] if got == want else [f"todowrite 接管检查: 得到 {got!r},期望 {want!r}"]


def main():
    check_web_migration()
    check_opencode_update_policy()
    check_opencode_update_detection()
    failures = []
    for script, body, fill in engines():
        with tempfile.TemporaryDirectory() as d:
            merged = run_engine(body, pathlib.Path(d))
        for path, want, side in EXPECT:
            got = dig(merged, path)
            if got != want:
                failures.append(f"{script}: {path} = {got!r},期望 {want!r}(应保留{side}侧)")
        with tempfile.TemporaryDirectory() as d:
            failures += check_fill(script, fill, pathlib.Path(d))
        with tempfile.TemporaryDirectory() as d:
            failures += check_todowrite_takeover(body, pathlib.Path(d))
        print(f"{script}: 合并检查 {len(EXPECT)} 项 + 占位符填空检查 12 项 + todowrite 接管检查")
    if failures:
        print("\n".join(f"FAIL {f}" for f in failures))
        return 1
    print("PASS: 私密键(api key/url/host/*_KEY)保留本机值,claude-mem 模型随模板,本地独有键不丢,列表键走并集,"
          "todowrite 由模板接管,6 个 key 各归各处")
    return 0


if __name__ == "__main__":
    sys.exit(main())
