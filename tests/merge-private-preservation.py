#!/usr/bin/env python3
"""安装脚本的字段级合并必须保留本机私密值(隐私内容永不覆盖)。

规则:普通非敏感字段随模板，本地独有配置保留；键名命中 SENSITIVE 或模板值为 <占位符> 时保留本机值，数值 maxTokens 作为模型预算随模板。四个 newapi 与自有 MCP 按条目受管合并，模型列表按 id 保留敏感叶子。
另外检查占位符填空:三个 <YOUR_NEWAPI_API_KEY> 必须各归各的 provider,embedding 与 claude-mem 不能串；并覆盖 OpenCode 原生合并、CodeGraph 传输边界与无配置部署。

用法:python3 tests/merge-private-preservation.py   退出码 0 = 通过
"""
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = re.compile(r'python3 - "\$dest" "\$tmp" "\$cand" <<\'PYEOF\'\n(.*?)\nPYEOF', re.S)
OC_MERGE = re.compile(r'python3 - "\$CFG/opencode\.json" "\$CFG/opencode\.jsonc" "\$oc_tpl" "\$oc_cand" "\$OC_MAJOR" "\$oc_force_manual" "\$PLAN_COMPACTION" <<\'PYEOF\'\n(.*?)\nPYEOF', re.S)
FILL = re.compile(r'python3 - "\$1" "\$GW_BASE" "\$K_CLAUDE" "\$K_CODEX" "\$K_ANTHROPIC" "\$K_GEMINI" "\$K_EMBED" "\$K_MEM" "\$MCPHUB_HOST" <<\'PYEOF\'\n(.*?)\nPYEOF', re.S)
IMG = re.compile(r'python3 - "\$HOME/\.local/share/agent-skills/image-gen\.json" .*?<<\'PYEOF\'\n(.*?)\nPYEOF', re.S)

LOCAL = {
    "apiKey": "sk-LOCAL",
    "providers": {
        "gw": {"baseUrl": "https://private.example/v1", "apiKey": "sk-LOCAL2", "models": ["m1"]},
        "claude-newapi": {
            "baseUrl": "https://private.example/v1", "apiKey": "sk-LOCAL-NEWAPI",
            "models": [{"id": "shared", "maxTokens": 4096, "headers": {"Authorization": "model-secret", "X-Drop": "old"}, "stale": True},
                       {"id": "local-only", "headers": {"Authorization": "retire-non-template"}}], "stale": True,
            "headers": {"Authorization": "Bearer LOCAL", "X-Drop": "old"},
        },
        "gemini-newapi": {"apiKey": "sk-RETIRE", "models": ["retire-me"]},
    },
    "NOTIFY_INGEST_KEY": "local-ingest",
    "mcp": {"hub": {"url": "https://private.example/mcp"}},
    "mcpServers": {
        "web": {"url": "https://private.example/mcp", "headers": {"Authorization": "sentinel", "X-Drop": "old"},
                "enabled": False, "toolExposure": {"search": "deferred"}},
        "codegraph": {"command": "old-codegraph"},
    },
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
    "providers": {
        "gw": {"baseUrl": "https://<YOUR_GATEWAY_HOST>/v1", "apiKey": "TEMPLATE2", "models": ["m2", "m1"]},
        "claude-newapi": {
            "baseUrl": "https://template.example/v1", "apiKey": "TEMPLATE-NEWAPI",
            "models": [{"id": "shared", "context": 123, "maxTokens": 200000, "headers": {"X-Managed": "yes"}}], "newField": "managed",
            "headers": {"X-Managed": "yes"},
        },
    },
    "NOTIFY_INGEST_KEY": "template-ingest",
    "mcp": {"hub": {"url": "https://<YOUR_MCPHUB_HOST>/mcp/web"}},
    "mcpServers": {
        "web": {"url": "https://template.example/mcp", "enabled": True, "toolExposure": {"search": "direct"}},
    },
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
    ("providers.claude-newapi.apiKey", "sk-LOCAL-NEWAPI", "local"),
    ("providers.claude-newapi.baseUrl", "https://private.example/v1", "local"),
    ("providers.claude-newapi.models", [{"id": "shared", "context": 123, "maxTokens": 200000,
        "headers": {"Authorization": "model-secret", "X-Managed": "yes"}}], "template(受管,按 id 保留敏感值)"),
    ("providers.claude-newapi.newField", "managed", "template(受管)"),
    ("providers.claude-newapi.stale", "<missing>", "template(删除受管旧字段)"),
    ("providers.claude-newapi.headers.Authorization", "Bearer LOCAL", "local(敏感)"),
    ("providers.claude-newapi.headers.X-Drop", "<missing>", "template(删除非敏感)"),
    ("providers.claude-newapi.headers.X-Managed", "yes", "template(受管)"),
    ("providers.gemini-newapi.apiKey", "sk-RETIRE", "local(模板未列出，保留凭据)"),
    ("mcpServers.web.url", "https://private.example/mcp", "local(敏感)"),
    ("mcpServers.web.headers.Authorization", "sentinel", "local(敏感)"),
    ("mcpServers.web.headers.X-Drop", "<missing>", "template(删除非敏感)"),
    ("mcpServers.web.enabled", True, "template(受管)"),
    ("mcpServers.web.toolExposure.search", "direct", "template(受管)"),
    ("mcpServers.codegraph.command", "old-codegraph", "local(模板未列出，保留条目)"),
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


def check_jsonc_strings_and_empty_slots(body, tmp):
    engine = tmp / "engine-jsonc.py"
    engine.write_text(body, encoding="utf-8")
    dest, tpl, cand = tmp / "dest.json", tmp / "tpl.json", tmp / "cand.json"
    dest.write_text('''// string tokens must stay opaque
{"apiKey":"sentinel,]suffix","url":"https://private.example/v1?next=1,]suffix",
 "providers":{"claude-newapi":{"apiKey":"","baseUrl":null}},}
''', encoding="utf-8")
    tpl.write_text(json.dumps({"providers": {"claude-newapi": {"apiKey": P_SLOT, "baseUrl": BASE_SLOT}}}), encoding="utf-8")
    subprocess.run([sys.executable, str(engine), str(dest), str(tpl), str(cand)],
                   capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)
    merged = json.loads(cand.read_text(encoding="utf-8"))
    assert merged["apiKey"] == "sentinel,]suffix"
    assert merged["url"] == "https://private.example/v1?next=1,]suffix"
    assert merged["providers"]["claude-newapi"] == {"apiKey": P_SLOT, "baseUrl": BASE_SLOT}


GW = "https://api.pezayo.com/v1"
KEYS = ("sk-claude", "sk-codex", "sk-anth", "sk-gemini", "sk-embed", "sk-mem")
PROVIDERS = ("claude-newapi", "codex-newapi", "anthropic-newapi", "gemini-newapi")
P_SLOT = "<YOUR_NEWAPI_API_KEY>"
BASE_SLOT = "https://<YOUR_GATEWAY_HOST>/v1"
SAMPLE_OC = {
    "providers": {p: {"settings": {"baseURL": BASE_SLOT, "apiKey": P_SLOT}} for p in PROVIDERS},
    "mcp": {"servers": {"web": {"url": "https://<YOUR_MCPHUB_HOST>/mcp/web"}}},
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
        node = oc["providers"][prov]["settings"]
        if node["apiKey"] != KEYS[i]:
            fails.append(f"{script}: opencode.json {prov} 的 apiKey = {node['apiKey']!r},期望 {KEYS[i]!r}")
        if node["baseURL"] != GW:
            fails.append(f"{script}: opencode.json {prov} 的 baseURL = {node['baseURL']!r},期望 {GW!r}")
    if oc["mcp"]["servers"]["web"]["url"] != "https://mcp.example.com/mcp/web":
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
    half["providers"]["claude-newapi"]["settings"]["apiKey"] = "sk-real-claude"
    half = run_fill(body, tmp, "half.json", half)
    if half["providers"]["claude-newapi"]["settings"]["apiKey"] != "sk-real-claude":
        fails.append(f"{script}: 已填好的 claude-newapi 的 key 被改掉了")
    if half["providers"]["codex-newapi"]["settings"]["apiKey"] != KEYS[1]:
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
        managed_web = json.loads(cand.read_text(encoding="utf-8"))["mcpServers"]["web"]
        assert managed_web == {
            "url": entry["url"], "headers": {"Authorization": "sentinel"},
            "exposure": "direct", "toolExposure": {"search": "direct"},
        }
    print("web MCP: Pi / OpenCode v1/v2，预览、备份、凭据/禁用/工具保留、幂等、冲突保留通过")


def run_oc_merge(body, tmp, live, major, force, template=None, raw=None, compact=False):
    engine = tmp / "oc_engine.py"
    engine.write_text(body, encoding="utf-8")
    target, jsonc, tpl, cand = tmp / "opencode.json", tmp / "opencode.jsonc", tmp / "tpl.json", tmp / "cand.json"
    target.write_text(raw if raw is not None else json.dumps(live, indent=2), encoding="utf-8")
    tpl.write_text(json.dumps(template or {"$schema": "x", "update": "disable", "retry": {"enabled": True}}, indent=2), encoding="utf-8")
    cand.unlink(missing_ok=True)
    proc = subprocess.run(
        [sys.executable, str(engine), str(target), str(jsonc), str(tpl), str(cand), major, "1" if force else "0", "1" if compact else "0"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode:
        raise SystemExit(f"STOP: opencode.json 合并引擎退出码 {proc.returncode}: {proc.stderr.strip()}")
    return json.loads((cand if cand.exists() else target).read_text(encoding="utf-8"))


def check_opencode_update_policy():
    match = OC_MERGE.search((ROOT / "opencode-setup.sh").read_text(encoding="utf-8"))
    assert match is not None, "opencode-setup.sh 里找不到 opencode.json 合并引擎"
    body = match.group(1)
    cases = [
        ({"update": "notify"}, "2", False, "update", "notify", "本机显式档位保留"),
        ({"update": "auto"}, "2", True, "update", "disable", "确认后改成手动"),
        ({"update": "auto"}, "2", False, "update", "auto", "未确认则保留 auto"),
        ({"update": "disable"}, "2", False, "update", "disable", "本机禁用保留"),
        ({}, "2", False, "update", "disable", "首次写入默认关"),
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
    """档位探测：只有 auto/true 才进入前置选择，其它本机明确选择不动。"""
    text = (ROOT / "opencode-setup.sh").read_text(encoding="utf-8")
    match = re.search(r"if \[ \"\$PLAN_WRITE_CFG\" = 1 \] && grep -qE '([^']+)'", text)
    assert match is not None, "opencode-setup.sh 里找不到前置自动更新档位探测"
    pattern = match.group(1)
    cases = [
        ({"update": "auto"}, "auto"),
        ({"update": True}, "auto"),
        ({"update": "notify"}, "keep"),
        ({"update": "disable"}, "keep"),
        ({"autoupdate": True}, "auto"),
        ({"autoupdate": False}, "keep"),
        ({}, "keep"),
    ]
    for live, want in cases:
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "opencode.json"
            path.write_text(json.dumps(live), encoding="utf-8")
            proc = subprocess.run([
                "bash", "-c",
                'if [ "$PLAN_WRITE_CFG" = 1 ] && grep -qE "$1" "$2" "$3" 2>/dev/null; then printf auto; else printf keep; fi',
                "_", pattern, str(path), str(path) + "c",
            ], env={"PLAN_WRITE_CFG": "1"}, capture_output=True, text=True, check=True)
        assert proc.stdout == want, f"{live}: 探测 = {proc.stdout!r},期望 {want!r}"
    print(f"opencode.json: 前置档位探测检查 {len(cases)} 项")


def check_opencode_role_models():
    body = OC_MERGE.search((ROOT / "opencode-setup.sh").read_text(encoding="utf-8")).group(1)
    agents = json.loads((ROOT / "templates/opencode/opencode.json").read_text(encoding="utf-8"))["agents"]
    template = {"agents": agents}
    expected = {"general": "codex-newapi/gpt-6.2-sol", "explore": "codex-newapi/gpt-6.1-terra"}
    old = "anthropic-newapi/deepseek-flash"
    with tempfile.TemporaryDirectory() as d:
        tmp = pathlib.Path(d)
        live = {"model": "custom/primary", "agents": {role: {"model": old} for role in expected}}
        live["agents"]["general"].update(system="keep", permissions=[{"action": "edit", "effect": "ask"}])
        live["agents"]["other"] = {"model": old}
        for existing in ({}, live):
            merged = run_oc_merge(body, tmp, existing, "2", False, template)
            assert {role: merged["agents"][role]["model"] for role in expected} == expected
        assert merged["model"] == "custom/primary" and merged["agents"]["other"] == {"model": old}
        general = merged["agents"]["general"]
        assert general["system"] == "keep" and general["permissions"] == live["agents"]["general"]["permissions"]

        layer = tmp / "opencode.jsonc"
        custom = old + "#custom"
        layer.write_text(json.dumps({"agents": {"explore": {"model": custom}}}), encoding="utf-8")
        merged = run_oc_merge(body, tmp, live, "2", False, template)
        assert merged["agents"]["explore"]["model"] == custom
        layer.unlink()
        assert run_oc_merge(body, tmp, merged, "2", False, template) == merged
        assert not (tmp / "cand.json").exists(), "角色合并重跑不应写候选文件"
    print("opencode.json: 角色旧默认迁移、JSONC 自定义保留、重跑不写通过")


def check_opencode_managed_takeover():
    match = OC_MERGE.search((ROOT / "opencode-setup.sh").read_text(encoding="utf-8"))
    assert match is not None, "opencode-setup.sh 里找不到受管配置合并引擎"
    body = match.group(1)
    live = {
        "providers": {
            "claude-newapi": {
                "models": [{"id": "shared", "stale": True, "maxTokens": 4096,
                            "headers": {"Authorization": "model-local", "X-Drop": "old"}},
                           {"id": "local-only", "headers": {"Authorization": "retire-non-template"}}], "stale": True,
                "settings": {"baseURL": "https://local.example/v1", "apiKey": "sk-LOCAL", "stale": 1},
                "headers": {"Authorization": "Bearer LOCAL", "X-Drop": "old"},
            },
            "gemini-newapi": {"models": ["retire"], "settings": {"apiKey": "sk-RETIRE"}},
            "custom": {"models": ["old-custom"], "settings": {"custom": "keep"}},
        },
        "mcp": {"servers": {
            "web": {"url": "https://local.example/mcp", "enabled": False,
                    "headers": {"Authorization": "sentinel", "X-Drop": "old"}},
            "custom": {"enabled": False},
        }},
    }
    template = {
        "providers": {
            "claude-newapi": {
                "models": [{"id": "shared", "context": 123, "maxTokens": 200000, "headers": {"X-Managed": "yes"}}], "npm": "@managed/provider",
                "settings": {"baseURL": "https://template.example/v1", "apiKey": "TEMPLATE", "managed": 1},
                "headers": {"X-Managed": "yes"},
            },
            "custom": {"models": ["new-custom"], "settings": {"template": "not-taken-over"}},
        },
        "mcp": {"servers": {"web": {
            "url": "https://template.example/mcp", "enabled": True, "headers": {"X-Managed": "yes"},
        }}},
    }
    with tempfile.TemporaryDirectory() as d:
        merged = run_oc_merge(body, pathlib.Path(d), live, "2", False, template)
    managed = merged["providers"]["claude-newapi"]
    assert managed["models"] == [{"id": "shared", "context": 123, "maxTokens": 200000,
        "headers": {"Authorization": "model-local", "X-Managed": "yes"}}] and "stale" not in managed
    assert managed["npm"] == "@managed/provider"
    assert managed["settings"]["baseURL"] == "https://local.example/v1"
    assert managed["settings"]["apiKey"] == "sk-LOCAL"
    assert managed["settings"]["managed"] == 1 and "stale" not in managed["settings"]
    assert managed["headers"] == {"Authorization": "Bearer LOCAL", "X-Managed": "yes"}
    assert "gemini-newapi" in merged["providers"]
    assert merged["providers"]["custom"]["models"] == ["new-custom"]
    assert merged["providers"]["custom"]["settings"] == {"custom": "keep"}
    web = merged["mcp"]["servers"]["web"]
    assert web["url"] == "https://local.example/mcp" and web["enabled"] is True
    assert web["headers"] == {"Authorization": "sentinel", "X-Managed": "yes"}
    assert merged["mcp"]["servers"]["custom"] == {"enabled": False}
    raw = '''// keep string contents
{"apiKey":"sentinel,]suffix","url":"https://private.example/v1?next=1,]suffix",
 "providers":{"claude-newapi":{"settings":{"apiKey":null,"baseURL":""}}},}
'''
    empty_template = {"providers": {"claude-newapi": {"settings": {"apiKey": P_SLOT, "baseURL": BASE_SLOT}}}}
    with tempfile.TemporaryDirectory() as d:
        empty = run_oc_merge(body, pathlib.Path(d), {}, "2", False, empty_template, raw=raw)
    assert empty["apiKey"] == "sentinel,]suffix"
    assert empty["url"] == "https://private.example/v1?next=1,]suffix"
    assert empty["providers"]["claude-newapi"]["settings"] == {"apiKey": P_SLOT, "baseURL": BASE_SLOT}
    print("opencode.json: newapi／自有 MCP 受管合并，敏感值与自定义条目保留")



def check_codegraph_mcp_takeover():
    with tempfile.TemporaryDirectory() as d:
        tmp = pathlib.Path(d)
        home = tmp / "home"
        bindir = home / ".local/bin"
        bindir.mkdir(parents=True)
        codegraph = bindir / "codegraph"
        codegraph.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        codegraph.chmod(0o755)
        cfgdir = tmp / "xdg/opencode"
        cfgdir.mkdir(parents=True)
        cfg = cfgdir / "opencode.json"
        env = os.environ.copy() | {"HOME": str(home), "XDG_CONFIG_HOME": str(tmp / "xdg"),
                                  "PATH": f"{bindir}:{os.environ['PATH']}"}
        env.pop("OPENCODE_CONFIG_DIR", None)
        env.pop("AGENT_SKILLS_NO_CONFIG_WRITE", None)
        argv = ["bash", str(ROOT / "modules/codegraph/setup.sh"), "--host", "opencode", "--yes"]
        live = {"mcp": {"servers": {
            "codegraph": {"type": "local", "command": ["old"], "disabled": True,
                          "apiKey": "secret", "stale": True, "headers": {"Authorization": "secret", "X-Drop": "old"}},
            "custom": {"enabled": False},
        }}}
        cfg.write_text(json.dumps(live), encoding="utf-8")
        subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        merged = json.loads(cfg.read_text(encoding="utf-8"))
        entry = merged["mcp"]["servers"]["codegraph"]
        assert entry["type"] == "local" and entry["command"] == [str(codegraph), "serve", "--mcp"]
        assert entry["disabled"] is False and "stale" not in entry and entry["apiKey"] == "secret"
        assert entry["headers"] == {"Authorization": "secret"}
        assert merged["mcp"]["servers"]["custom"] == {"enabled": False}
        before = cfg.read_bytes()
        subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        assert cfg.read_bytes() == before

        remote = {"mcp": {"servers": {"codegraph": {
            "type": "remote", "url": "https://remote.example/mcp", "headers": {"Authorization": "secret"}
        }}}}
        cfg.write_text(json.dumps(remote), encoding="utf-8")
        before = cfg.read_bytes()
        backups_before = set(cfgdir.glob("*.bak-codegraph-*"))
        proc = subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        assert cfg.read_bytes() == before and "remote" in proc.stderr
        assert set(cfgdir.glob("*.bak-codegraph-*")) == backups_before

        legacy_remote = {"mcp": {"codegraph": {
            "type": "remote", "url": "https://legacy.example/mcp", "headers": {"Authorization": "secret"}
        }}}
        cfg.write_text(json.dumps(legacy_remote), encoding="utf-8")
        before = cfg.read_bytes()
        subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        assert cfg.read_bytes() == before

        jsonc = cfg.with_suffix(".jsonc")
        cfg.write_text("{}", encoding="utf-8")
        jsonc.write_text('// remote in JSONC\n{"mcp":{"codegraph":{"type":"remote","url":"https://jsonc.example/mcp",},},}\n', encoding="utf-8")
        before = (cfg.read_bytes(), jsonc.read_bytes())
        subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        assert (cfg.read_bytes(), jsonc.read_bytes()) == before

        jsonc.write_text('{"mcp":{"codegraph":{"type":"local","command":["old"]}}}', encoding="utf-8")
        before = (cfg.read_bytes(), jsonc.read_bytes())
        proc = subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        assert (cfg.read_bytes(), jsonc.read_bytes()) == before and "归一化" in proc.stderr
        jsonc.unlink()

        cfg.write_text(json.dumps({"mcp": {"codegraph": {"type": "local", "command": ["old"], "apiKey": "secret"}}}), encoding="utf-8")
        subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        merged = json.loads(cfg.read_text(encoding="utf-8"))
        assert merged["mcp"]["codegraph"]["command"] == [str(codegraph), "serve", "--mcp"]
        assert merged["mcp"]["codegraph"]["apiKey"] == "secret" and "servers" not in merged["mcp"]

        env["AGENT_SKILLS_NO_CONFIG_WRITE"] = "1"
        cfg.write_text('{"mcp":{"servers":{"custom":{"enabled":false}}}}', encoding="utf-8")
        before = cfg.read_bytes()
        subprocess.run(argv, env=env, capture_output=True, text=True, check=True)
        assert cfg.read_bytes() == before
    print("codegraph MCP：XDG／两种本地结构更新／JSON+JSONC remote 保留／拒绝配置写入均通过")


def check_dsh_gemini_catalog_migration():
    node = shutil.which("node") or str(pathlib.Path.home() / ".local/share/pi-node/current/bin/node")
    assert pathlib.Path(node).is_file(), "DSH 迁移回归需要 Node"
    script = r'''
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const { merge, migrateGeminiProvider } = await import(pathToFileURL(process.argv[2]).href);
const template = JSON.parse(readFileSync(process.argv[3], "utf8"))
  .find((row) => row.id === "llm-pi-ai").config.providers;
if (!template.google || "api" in template.google || template["gemini-newapi"]) {
  throw new Error("DSH 模板必须使用无显式 api 的 google 目录路由");
}
const providers = {
  "gemini-newapi": {
    api: "google-generative-ai",
    baseURL: "https://legacy.example/v1beta",
    apiKeyEnv: "CUSTOM_GEMINI_KEY",
    models: [{ id: "local-model" }],
  },
};
migrateGeminiProvider(providers);
const merged = merge(providers, template);
migrateGeminiProvider(merged);
if (merged["gemini-newapi"] || "api" in merged.google) throw new Error("旧 Gemini 路由或 api 残留");
if (merged.google.baseURL !== "https://legacy.example/v1beta") throw new Error("旧 URL 未保留");
if (merged.google.apiKeyEnv !== "CUSTOM_GEMINI_KEY") throw new Error("旧 apiKeyEnv 未保留");
if (!merged.google.models.some((model) => model.id === "local-model")) throw new Error("自定义模型未保留");
if (!merged.google.models.some((model) => model.id === template.google.models[0].id)) throw new Error("模板模型未合并");
let conflictRejected = false;
try {
  migrateGeminiProvider({
    "gemini-newapi": { baseURL: "https://old.example", models: [{ id: "old" }] },
    google: { baseURL: "https://new.example", models: [{ id: "new" }] },
  });
} catch { conflictRejected = true; }
if (!conflictRejected) throw new Error("双 Gemini 键必须明确拒绝，不能静默拼接");
'''
    subprocess.run([node, "--input-type=module", "-e", script, "migration-test", str(ROOT / "dsh/deploy.mjs"),
                    str(ROOT / "templates/dsh/cordis.patch.json")], capture_output=True, text=True, check=True)
    print("DSH Gemini：google 目录路由迁移，旧键／api 清理及敏感值、模型保留通过")


def check_opencode_no_config_deploy():
    spec = importlib.util.spec_from_file_location("oc_deploy_test", ROOT / "opencode/deploy.py")
    deploy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(deploy)
    with tempfile.TemporaryDirectory() as d:
        tmp = pathlib.Path(d)
        root, cfg = tmp / "release", tmp / "config"
        (root / "v2").mkdir(parents=True)
        cfg.mkdir()
        asset = root / "v2/plugin.js"
        asset.write_text("export const ok = true;\n", encoding="utf-8")
        (root / "MANIFEST.json").write_text(json.dumps({
            "major": 2, "version": "test", "install": ["v2"],
            "files": {"v2/plugin.js": hashlib.sha256(asset.read_bytes()).hexdigest()},
        }), encoding="utf-8")
        originals = {}
        for name, content in (("opencode.json", '{"plugins":[],"provider":{"keep":"value"}}\n'),
                              ("opencode.jsonc", '{"theme":"local"}\n'), ("cli.json", '{"plugin":[]}\n')):
            (cfg / name).write_text(content, encoding="utf-8")
            originals[name] = (cfg / name).read_bytes()
        caches = {}
        for name in ("magic-context", "ponytail"):
            cache = tmp / "cache" / name
            cache.mkdir(parents=True)
            (cache / "package.json").write_text('{"name":"cached"}', encoding="utf-8")
            caches[name] = cache
        chmod_calls = []
        deploy.npm_caches = lambda name: [caches["magic-context" if name == deploy.MC else "ponytail"]]
        deploy.writable_cache = lambda path: chmod_calls.append(path)
        deploy.install(root, cfg, 2, refresh_mc=True, refresh_ponytail=True, write_config=False)
        assert all((cfg / name).read_bytes() == content for name, content in originals.items())
        assert (cfg / "v2/plugin.js").read_bytes() == asset.read_bytes()
        assert not list(cfg.glob("*.migrated-*.bak"))
        assert not chmod_calls and all(cache.exists() for cache in caches.values())
    print("OpenCode 无配置部署：仅更新资产，配置／JSONC／CLI／缓存不动")


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


def check_image_gen(tmp):
    """画图凭据:只补缺失字段,已有 base_url/api_key 必须保留;占位符不当真;无可用 key 时不建文件。"""
    bodies = {}
    for script in ("pi-setup.sh", "opencode-setup.sh"):
        match = IMG.search((ROOT / script).read_text(encoding="utf-8"))
        if not match:
            raise SystemExit(f"STOP: 在 {script} 里找不到 image-gen 凭据步骤")
        bodies[script] = match.group(1)
    if len(set(bodies.values())) != 1:
        return ["image-gen 凭据步骤:两个脚本的实现不一致(必须逐字节相同)"]
    body = bodies["pi-setup.sh"]
    engine = tmp / "image-gen.py"
    engine.write_text(body, encoding="utf-8")
    cfg, models = tmp / "image-gen.json", tmp / "models.json"
    failures = []

    def run(gw="", key=""):
        proc = subprocess.run([sys.executable, str(engine), str(cfg), gw, key, str(models)],
                              capture_output=True, text=True, encoding="utf-8", errors="replace")
        if proc.returncode:
            raise SystemExit(f"STOP: image-gen 凭据步骤退出码 {proc.returncode}: {proc.stderr.strip()}")
        return json.loads(cfg.read_text(encoding="utf-8")) if cfg.exists() else None

    if run("https://gw.example/v1", ""):
        failures.append("image-gen: 无任何 key 时不应建文件")
    got = run("https://gw.example/v1", "sk-ENV")
    if got != {"base_url": "https://gw.example/v1", "api_key": "sk-ENV", "model": "gpt-image-2.5-flare"}:
        failures.append(f"image-gen: 新建设置不对 {got!r}")
    if (cfg.stat().st_mode & 0o777) != 0o600:
        failures.append(f"image-gen: 权限应为 600,实际 {oct(cfg.stat().st_mode & 0o777)}")
    before = cfg.read_bytes()
    run("https://other.example/v1", "sk-OVERWRITE")
    if cfg.read_bytes() != before:
        failures.append("image-gen: 已配置时被改写(私密值必须保留)")
    cfg.write_text(json.dumps({"base_url": "https://keep.example/v1", "model": "gpt-image-2"}), encoding="utf-8")
    models.write_text(json.dumps({"providers": {"a": {"api": "openai-responses", "baseUrl": "https://det.example/v1", "apiKey": "sk-DET"}}}), encoding="utf-8")
    got = run()
    if got != {"base_url": "https://keep.example/v1", "api_key": "sk-DET", "model": "gpt-image-2"}:
        failures.append(f"image-gen: 缺 api_key 时应保留 base_url/model 并从 models.json 补 key,得到 {got!r}")
    return failures


def main():
    check_web_migration()
    check_opencode_update_policy()
    check_opencode_role_models()
    check_opencode_managed_takeover()
    check_codegraph_mcp_takeover()
    check_dsh_gemini_catalog_migration()
    check_opencode_no_config_deploy()
    check_opencode_update_detection()
    failures = []
    for script, body, fill in engines():
        with tempfile.TemporaryDirectory() as d:
            merged = run_engine(body, pathlib.Path(d))
        with tempfile.TemporaryDirectory() as d:
            check_jsonc_strings_and_empty_slots(body, pathlib.Path(d))
        for path, want, side in EXPECT:
            got = dig(merged, path)
            if got != want:
                failures.append(f"{script}: {path} = {got!r},期望 {want!r}(应保留{side}侧)")
        with tempfile.TemporaryDirectory() as d:
            failures += check_fill(script, fill, pathlib.Path(d))
        with tempfile.TemporaryDirectory() as d:
            failures += check_todowrite_takeover(body, pathlib.Path(d))
        print(f"{script}: 合并检查 {len(EXPECT)} 项 + 占位符填空检查 12 项 + todowrite 接管检查")
    with tempfile.TemporaryDirectory() as d:
        failures += check_image_gen(pathlib.Path(d))
    print("image-gen 凭据检查: 保留本机值 / 只补缺失 / 600 权限 / 无 key 不建文件")
    if failures:
        print("\n".join(f"FAIL {f}" for f in failures))
        return 1
    print("PASS: 私密键(api key/url/host/*_KEY)保留本机值,claude-mem 模型随模板,本地独有键不丢,列表键走并集,"
          "todowrite 由模板接管,6 个 key 各归各处")
    return 0


if __name__ == "__main__":
    sys.exit(main())
