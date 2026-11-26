#!/usr/bin/env python3
"""安装流程回归：选择前置、已有占位符免询问、模块选择无副作用。"""
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETUPS = ("pi-setup.sh", "opencode-setup.sh", "codex-setup.sh", "dsh-setup.sh")


def function(path, name):
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if re.match(rf"^\s*{re.escape(name)}\(\)\s*\{{", line)), None)
    assert start is not None, f"{path.name}: 缺函数 {name}"
    indent = re.match(r"^(\s*)", lines[start]).group(1)
    end = None
    heredoc = None
    for i in range(start + 1, len(lines)):
        stripped = lines[i].strip()
        if heredoc:
            if stripped == heredoc:
                heredoc = None
            continue
        marker = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)", lines[i])
        if marker:
            heredoc = marker.group(1)
            continue
        if lines[i].rstrip("\n") == indent + "}":
            end = i
            break
    assert end is not None, f"{path.name}: 函数 {name} 未闭合"
    return "".join(lines[start:end + 1]), start, end


def check_no_late_questions():
    for name in SETUPS:
        path = ROOT / name
        text = path.read_text(encoding="utf-8")
        _, start, end = function(path, "collect_setup_plan")
        plan = "".join(text.splitlines(keepends=True)[start:end + 1])
        assert "collect_gateway_values" in plan or name == "dsh-setup.sh", f"{name}: 凭据未纳入前置计划"
        assert "--select" in plan, f"{name}: 模块未在前置阶段选择"
        suffix = text[sum(len(line) for line in text.splitlines(keepends=True)[:end + 1]):]
        call = re.search(r"(?m)^collect_setup_plan\s*$", suffix)
        assert call, f"{name}: 找不到前置计划调用"
        execution = suffix[call.end():]
        executable = "\n".join(line for line in execution.splitlines() if not line.lstrip().startswith("#"))
        late = re.findall(r"\b(?:ask|ask_value)\s+[\"']", executable)
        assert not late, f"{name}: 执行阶段仍有 {len(late)} 处人工提问"
        assert "--selected" in execution, f"{name}: 模块未使用预选名单执行"
    for name in SETUPS[:3]:
        body, _, _ = function(ROOT / name, "resolve_python3")
        assert not re.search(r"(?m)^\s*ask\s", body), f"{name}: Python 兜底仍会晚问"
        assert "PLAN_PYTHON_UV" in body, f"{name}: Python 兜底未消费前置选择"
    print("前置流程：四个入口执行段无人工提问，模块均先选后装")


def credential_script(name, tmp):
    path = ROOT / name
    parts = []
    for fn in ("config_probe", "has_provider_config", "has_embedding_config", "has_mem_config",
               "has_gateway_config", "has_mcp_config", "needs_gateway_fill", "needs_mcphub_fill", "collect_gateway_values"):
        try:
            body, _, _ = function(path, fn)
        except AssertionError:
            if name == "codex-setup.sh" and fn in ("config_probe", "has_provider_config", "has_embedding_config", "has_mem_config", "has_gateway_config", "has_mcp_config", "needs_mcphub_fill"):
                continue
            raise
        parts.append(body)
    parts.append(r'''
npath() { printf '%s' "$1"; }
ask_value() { printf '%s\n' "$2" >> "$LOG"; printf -v "$2" '%s' filled; }
: > "$LOG"
collect_gateway_values
''')
    script = tmp / f"{name}.sh"
    node_bin = shutil.which("node") or str(pathlib.Path.home() / ".local/share/pi-node/current/bin/node")
    probe_bin = tmp / ".local/share/pi-node/current/bin"
    probe_bin.mkdir(parents=True, exist_ok=True)
    if not (probe_bin / "node").exists():
        os.symlink(node_bin, probe_bin / "node")
    script.write_text("\n".join(parts), encoding="utf-8")
    env = os.environ.copy()
    env.update({
        "HOME": str(tmp), "LOG": str(tmp / "calls"), "CFG": str(tmp / "oc"),
        "MODELS": str(tmp / "models.json"), "SETTINGS": str(tmp / "settings.json"),
        "MC_SETTINGS": str(tmp / "mem.json"), "MCP_CONFIG": str(tmp / "mcp.json"),
        "AUTH": str(tmp / "auth.json"), "MC_CFG": str(tmp / "magic.jsonc"),
        "GW_BASE": "", "MCPHUB_HOST": "", "K_CLAUDE": "", "K_CODEX": "",
        "K_ANTHROPIC": "", "K_GEMINI": "", "K_EMBED": "", "K_MEM": "",
        "DEFAULT_GW": "https://api.pezayo.com/v1",
    })
    return script, env


def run_credentials(name, tmp):
    script, env = credential_script(name, tmp)
    proc = subprocess.run(["bash", str(script)], env=env, capture_output=True, text=True)
    assert proc.returncode == 0, f"{name}: 凭据函数失败：{proc.stderr}\n{proc.stdout}"
    calls = (tmp / "calls").read_text().splitlines()
    (tmp / "calls").write_text("")
    return calls


def check_existing_credentials():
    for name in SETUPS[:3]:
        with tempfile.TemporaryDirectory(prefix="setup-credentials-") as d:
            tmp = pathlib.Path(d)
            (tmp / "oc").mkdir()
            providers = ("claude-newapi", "codex-newapi", "anthropic-newapi", "gemini-newapi")
            (tmp / "models.json").write_text(json.dumps({"providers": {
                p: {"baseUrl": "https://<YOUR_GATEWAY_HOST>", "apiKey": "<YOUR_NEWAPI_API_KEY>"} for p in providers
            }}))
            (tmp / "settings.json").write_text(json.dumps({
                "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>",
                "CLAUDE_MEM_OPENROUTER_BASE_URL": "https://<YOUR_GATEWAY_HOST>/v1",
            }))
            (tmp / "mem.json").write_text(json.dumps({
                "CLAUDE_MEM_OPENROUTER_API_KEY": "<YOUR_API_KEY>",
                "CLAUDE_MEM_OPENROUTER_BASE_URL": "https://<YOUR_GATEWAY_HOST>/v1",
            }))
            (tmp / "auth.json").write_text('{"zai-coding-cn":{"type":"api_key","key":"<YOUR_ZAI_API_KEY>"}}')
            (tmp / "magic.jsonc").write_text('{"embedding":{"api_key":"<YOUR_API_KEY>","endpoint":"https://<YOUR_GATEWAY_HOST>/v1"}}')
            (tmp / "mcp.json").write_text('{"mcpServers":{"web":{"url":"<YOUR_MCPHUB_HOST>"}}}')
            (tmp / "oc/opencode.json").write_text(json.dumps({
                "providers": {p: {"settings": {"baseURL": "https://<YOUR_GATEWAY_HOST>/v1", "apiKey": "<YOUR_NEWAPI_API_KEY>"}} for p in providers},
                "mcp": {"servers": {"web": {"url": "<YOUR_MCPHUB_HOST>"}}},
            }))
            calls = run_credentials(name, tmp)
            assert calls == [], f"{name}: 已有占位符仍询问 {calls}"
            if name == "codex-setup.sh":
                continue
            config_path = tmp / ("models.json" if name == "pi-setup.sh" else "oc/opencode.json")
            config = json.loads(config_path.read_text())
            if name == "opencode-setup.sh":
                claude = config["providers"]["claude-newapi"]
                base = claude["settings"].pop("baseURL")
                claude["options"] = {"baseURL": base}
                config_path.write_text(json.dumps(config))
                assert run_credentials(name, tmp) == [], "旧 options.baseURL 未按有效网关识别"
                claude["settings"]["baseURL"] = claude.pop("options")["baseURL"]
            config["providers"]["claude-newapi"] = ({"baseUrl": "https://<YOUR_GATEWAY_HOST>", "models": [{"headers": {"Authorization": "model-only"}}]} if name == "pi-setup.sh"
                                                       else {"settings": {"baseURL": "https://<YOUR_GATEWAY_HOST>/v1"}, "models": [{"headers": {"Authorization": "model-only"}}]})
            config_path.write_text(json.dumps(config))
            calls = run_credentials(name, tmp)
            assert calls == ["K_CLAUDE"], f"{name}: 无 key 的 provider 被误判：{calls}"
            config["providers"]["claude-newapi"] = ({"baseUrl": "https://<YOUR_GATEWAY_HOST>", "apiKey": "<YOUR_NEWAPI_API_KEY>"}
                                                       if name == "pi-setup.sh" else
                                                       {"settings": {"baseURL": "https://<YOUR_GATEWAY_HOST>/v1", "apiKey": "<YOUR_NEWAPI_API_KEY>"}})
            if name == "pi-setup.sh":
                (tmp / "mcp.json").write_text('{"agents":{"web":{}}}')
            else:
                config["mcp"] = {"web": {"url": "<YOUR_MCPHUB_HOST>"}}
                config_path.write_text(json.dumps(config))
                assert run_credentials(name, tmp) == [], "旧 mcp.web 未按有效配置识别"
                config.pop("mcp", None)
                config["agents"] = {"web": {}}
            config_path.write_text(json.dumps(config))
            calls = run_credentials(name, tmp)
            assert calls == ["MCPHUB_HOST"], f"{name}: 同名 agent 被误判为 MCP：{calls}"
            if name == "pi-setup.sh":
                legacy = tmp / ".agents/mcp.json"
                legacy.parent.mkdir()
                legacy.write_text('{"mcpServers":{"web":{"url":"<YOUR_MCPHUB_HOST>"}}}')
                calls = run_credentials(name, tmp)
                assert calls == ["MCPHUB_HOST"], "旧共享 MCP 被误算为原生已配置"
                (tmp / "mcp.json").write_text('{"mcpServers":{"web":{"url":"<YOUR_MCPHUB_HOST>"}}}')
            else:
                config.pop("agents", None)
                config["mcp"] = {"servers": {"web": {"url": "<YOUR_MCPHUB_HOST>"}}}
                config_path.write_text(json.dumps(config))
                (tmp / "oc/opencode.jsonc").write_text('{"providers":{"claude-newapi":{"settings":{"apiKey":null}}}}')
                calls = run_credentials(name, tmp)
                assert calls == ["K_CLAUDE"], f"JSONC 空值未覆盖 JSON 凭据：{calls}"
                (tmp / "oc/opencode.jsonc").unlink()
                config_path.write_text("{}")
                (tmp / "oc/opencode.jsonc").write_text("// " + json.dumps(config).replace("\n", "\n// "))
                calls = run_credentials(name, tmp)
                assert "K_CLAUDE" in calls and "MCPHUB_HOST" in calls, "注释中的配置被误判为实配置"
                (tmp / "oc/opencode.jsonc").unlink()
                config_path.write_text(json.dumps(config))
            for file in ("models.json", "settings.json", "mem.json", "auth.json", "magic.jsonc", "oc/opencode.json"):
                (tmp / file).write_text("{}")
            if name == "opencode-setup.sh":
                (tmp / "oc/opencode.json").write_text('{"mcp":{"servers":{"web":{"url":"<YOUR_MCPHUB_HOST>"}}}}')
            calls = run_credentials(name, tmp)
            assert "K_CLAUDE" in calls and "MCPHUB_HOST" not in calls, f"{name}: 凭据／MCP 未分别判断：{calls}"
            script, env = credential_script(name, tmp)
            (tmp / ".local/share/pi-node/current/bin/node").unlink()
            env["PATH"] = str(tmp / "no-node")
            proc = subprocess.run([shutil.which("bash"), str(script)], env=env, capture_output=True, text=True)
            assert proc.returncode == 0, proc.stderr + proc.stdout
            assert not (tmp / "calls").read_text(), "无法读取配置时不应伪装成缺项并追问"
            assert "无法" in proc.stderr
    print("凭据检测：有效配置合并、真实槽位、JSONC 覆盖、无 Node 分支均通过")


def check_module_selection():
    with tempfile.TemporaryDirectory(prefix="setup-modules-") as d:
        tmp = pathlib.Path(d)
        modules = tmp / "modules"
        modules.mkdir()
        runner = modules / "run.sh"
        runner.write_text((ROOT / "modules/run.sh").read_text(encoding="utf-8"))
        log = tmp / "executed"
        for name in ("alpha", "beta"):
            directory = modules / name
            directory.mkdir()
            (directory / "setup.sh").write_text(
                f"#!/usr/bin/env bash\n# module: {name}\n# desc: test\n# default: Y\n# hosts: any\n"
                f"printf '%s\\n' {name} >> \"$SETUP_TEST_LOG\"\n")
        env = os.environ.copy() | {"SETUP_TEST_LOG": str(log)}
        selected = subprocess.run(["bash", str(runner), "--host", "pi", "--select", "--yes"],
                                  env=env, capture_output=True, text=True, check=True).stdout.splitlines()
        assert selected == ["alpha", "beta"], selected
        assert not log.exists(), "--select 产生了安装副作用"
        without_tty = subprocess.run(["bash", str(runner), "--host", "pi", "--select"],
                                     env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                     start_new_session=True, check=True).stdout.splitlines()
        assert without_tty == selected, "无 tty 未采用模块默认值"
        assert not log.exists(), "无 tty 的选择阶段产生了安装副作用"
        subprocess.run(["bash", str(runner), "--host", "pi", "--selected", "\n".join(selected)],
                       env=env, capture_output=True, text=True, check=True)
        assert log.read_text().splitlines() == ["alpha", "beta"]
        (modules / 'alpha/setup.sh').write_text('# hosts: pi,opencode,dsh\nexit 23\n')
        env.update(AGENT_SKILLS_HOST_ONLY='1', _AMOD=str(runner), MODULE_RUN=str(runner),
                   PLAN_MOD_PATH=str(runner), PLAN_WRITE_CFG='0', MODULE_SELECTION='alpha', PLAN_MODULES='alpha')
        for host, start in [('pi', 'if [ -n "${_AMOD:-}" ]; then'), ('opencode', 'if [ -n "$MODULE_RUN" ] &&'),
                            ('dsh', 'if [[ -f "$PLAN_MOD_PATH" ]]; then')]:
            text = (ROOT / f'{host}-setup.sh').read_text()
            block = text[text.rindex(start):].split('\nfi\n', 1)[0] + '\nfi\necho completed\n'
            p = subprocess.run(['bash', '-c', block], env=env, capture_output=True, text=True)
            assert p.returncode == 1 and 'completed' not in p.stdout and 'alpha' in p.stderr, (host, p.stderr)
    print("模块选择：--select 零安装，--selected 按名单顺序执行")


def check_dsh_existing_credentials():
    parts = [function(ROOT / "dsh-setup.sh", name)[0] for name in
             ("have_tty", "pi_value", "pi_auth_key", "config_value_usable", "validate_gateway_url", "validate_collected_gateway_urls", "dsh_saved_query", "collect_credentials")]
    with tempfile.TemporaryDirectory(prefix="setup-dsh-credentials-") as d:
        tmp = pathlib.Path(d)
        agent = tmp / ".pi/agent"
        agent.mkdir(parents=True)
        routes = ("claude-newapi", "codex-newapi", "anthropic-newapi", "gemini-newapi")
        (agent / "models.json").write_text(json.dumps({"providers": {
            route: {"baseUrl": "https://gateway.example/v1", "apiKey": f"test-{route}-key"} for route in routes
        }}))
        (agent / "auth.json").write_text(json.dumps({
            "zai-coding-cn": {"type": "api_key", "key": "test-zai-key"},
            "kimi-coding": {"type": "api_key", "key": "test-kimi-key"},
        }))
        runner = tmp / "run.sh"
        node_bin = shutil.which("node") or str(pathlib.Path.home() / ".local/share/pi-node/current/bin/node")
        assert pathlib.Path(node_bin).is_file(), "DSH 凭据测试需要可用 Node"
        runner.write_text(f'''
HOME={tmp}; ROOT={tmp}; DSH_HOME_DIR={tmp}/dsh; JSON_NODE={node_bin}; NODE=; YES=0; CALL_LOG={tmp}/calls
ask() {{ printf ask >> "$CALL_LOG"; return 1; }}
{chr(10).join(parts)}
collect_credentials
validate_collected_gateway_urls
printf '%s|%s|%s\n' "$CLAUDE_NEWAPI_BASE_URL" "$CLAUDE_NEWAPI_API_KEY" "$ZAI_CODING_CN_API_KEY"
''')
        env = os.environ.copy()
        for key in list(env):
            if key.startswith(("CLAUDE_NEWAPI_", "CODEX_NEWAPI_", "ANTHROPIC_NEWAPI_", "GEMINI_NEWAPI_", "ZAI_CODING_CN_", "KIMI_CODING_")):
                env.pop(key)
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, proc.stderr + proc.stdout
        assert proc.stdout.strip().splitlines()[-1] == "https://gateway.example/v1|test-claude-newapi-key|test-zai-key", proc.stdout
        assert not (tmp / "calls").exists(), "已有真实配置仍触发 DSH 输入"
        providers = {route: {"baseUrl": "https://gateway.example/v1", "apiKey": f"test-{route}-key"} for route in routes}
        output = tmp / "output"
        env["HOME"] = str(tmp)
        env.pop("DSH_HOME", None)
        env["XDG_DATA_HOME"] = str(output)
        for field, placeholder in (("baseUrl", "https://<YOUR_GATEWAY_HOST>"), ("apiKey", "  <YOUR_NEWAPI_API_KEY>  ")):
            invalid = json.loads(json.dumps(providers))
            invalid["claude-newapi"][field] = placeholder
            (agent / "models.json").write_text(json.dumps({"providers": invalid}))
            rejected = subprocess.run(["bash", str(ROOT / "dsh-setup.sh"), "-y"], env=env, stdin=subprocess.DEVNULL,
                                      capture_output=True, text=True, start_new_session=True)
            assert rejected.returncode != 0
            assert "占位符" in rejected.stdout + rejected.stderr
            assert not output.exists(), "占位符在拒绝前已经写入 DSH 目录"
        invalid = json.loads(json.dumps(providers))
        env["PATH"] = str(pathlib.Path(node_bin).parent) + os.pathsep + env["PATH"]
        for bad_url in ("https://example.invalid:99999", "http://256.1.1.1", "http://0x100.1.1.1", "http://example.1", "https://exa%mple.invalid"):
            invalid["claude-newapi"]["baseUrl"] = bad_url
            (agent / "models.json").write_text(json.dumps({"providers": invalid}))
            rejected = subprocess.run(["bash", str(ROOT / "dsh-setup.sh"), "-y"], env=env, stdin=subprocess.DEVNULL,
                                      capture_output=True, text=True, start_new_session=True)
            assert rejected.returncode != 0 and "有效的 http(s)" in rejected.stdout + rejected.stderr, bad_url
            assert not output.exists(), f"非法 URL 在拒绝前已经写入 DSH 目录：{bad_url}"
        whitespace = json.loads(json.dumps(providers))
        whitespace["claude-newapi"]["apiKey"] = " \t "
        (agent / "models.json").write_text(json.dumps({"providers": whitespace}))
        rejected = subprocess.run(["bash", str(ROOT / "dsh-setup.sh"), "-y"], env=env, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, start_new_session=True)
        error_output = rejected.stdout + rejected.stderr
        assert rejected.returncode != 0 and "claude-newapi" in error_output and "apiKeyEnv" in error_output, error_output
        assert not output.exists(), "空白 key 在拒绝前已经创建正式 ROOT"
        missing = json.loads(json.dumps(providers))
        missing["claude-newapi"] = {"baseUrl": "", "apiKey": ""}
        (agent / "models.json").write_text(json.dumps({"providers": missing}))
        rejected = subprocess.run(["bash", str(ROOT / "dsh-setup.sh"), "-y"], env=env, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, start_new_session=True)
        assert rejected.returncode != 0 and "CLAUDE_NEWAPI_BASE_URL" in rejected.stdout + rejected.stderr, rejected.stdout + rejected.stderr
        assert "/dev/tty" not in rejected.stdout + rejected.stderr
        assert not output.exists()
        (agent / "models.json").write_text(json.dumps({"providers": providers}))
        dsh_home = tmp / "dsh"
        patch = dsh_home / "profiles/headless/cordis.patch.yml"
        patch.parent.mkdir(parents=True)
        (dsh_home / ".credentials.yaml").write_text("version: 1\n")
        def write_patch(claude_url, gemini_key="gemini-newapi"):
            patch.write_text("- id: llm-pi-ai\n  config:\n    providers:\n" + "".join(
                f"      {gemini_key if route == 'gemini-newapi' else route}:\n        \"baseURL\": \"{claude_url if route == 'claude-newapi' else 'https://gateway.example/v1'}\" # gateway\n"
                for route in routes))
        write_patch("https://gateway.example/v1", "google")
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, proc.stderr + proc.stdout
        auth = {"zai-coding-cn": {"type": "api_key", "key": "test-zai-key"},
                "kimi-coding": {"type": "api_key", "key": "test-kimi-key"},
                "claude-newapi": {"type": "api_key", "key": "test-auth-claude"}}
        (agent / "auth.json").write_text(json.dumps(auth))
        placeholder_models = json.loads(json.dumps(providers))
        placeholder_models["claude-newapi"]["apiKey"] = ""
        (agent / "models.json").write_text(json.dumps({"providers": placeholder_models}))
        env["CLAUDE_NEWAPI_API_KEY"] = "<YOUR_CLAUDE_KEY>"
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0 and proc.stdout.strip().splitlines()[-1].split("|")[1] == "test-auth-claude", proc.stdout + proc.stderr
        env.pop("CLAUDE_NEWAPI_API_KEY")
        (agent / "models.json").write_text(json.dumps({"providers": providers}))
        (agent / "auth.json").write_text(json.dumps({key: value for key, value in auth.items() if key != "claude-newapi"}))
        valid_patch = patch.read_text()
        write_patch("https://example.invalid:99999", "google")
        patch.write_text(patch.read_text() + "\n" + valid_patch)
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, "未按宿主使用最后一个 llm-pi-ai 条目：" + proc.stderr + proc.stdout
        expression_patch = "- id: llm-pi-ai\n  config:\n    providers:\n" + "".join(
            f"      {'google' if route == 'gemini-newapi' else route}:\n"
            f"        baseURL: !!js '\"https://gateway.example/v1\"'\n"
            f"        apiKeyEnv: !!js '\"{route.upper().replace('-', '_')}_API_KEY\"'\n"
            for route in routes)
        patch.write_text(expression_patch)
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, "合法 !!js 槽位被前置误拒：" + proc.stderr + proc.stdout
        provider_object = {
            ("google" if route == "gemini-newapi" else route): {
                "baseURL": "https://gateway.example/v1",
                "apiKeyEnv": route.upper().replace("-", "_") + "_API_KEY",
            } for route in routes
        }
        for expression_path in ("config", "providers"):
            if expression_path == "config":
                body = f"- id: llm-pi-ai\n  config: !!js '{json.dumps({'providers': provider_object})}'\n"
            else:
                body = f"- id: llm-pi-ai\n  config:\n    providers: !!js '{json.dumps(provider_object)}'\n"
            patch.write_text(body)
            proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                                  text=True, start_new_session=True)
            assert proc.returncode == 0, f"合法 {expression_path} !!js 被前置误拒：" + proc.stderr + proc.stdout
        (dsh_home / "cordis.patch.yml").write_text(json.dumps([{"id": "llm-pi-ai", "config": {"providers": provider_object}}]), encoding="utf-8")
        write_patch("https://example.invalid:99999", "google")
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, "home 已覆盖旧非法 URL，前置仍提前拒绝：" + proc.stderr + proc.stdout
        (dsh_home / "cordis.patch.yml").unlink()
        disabled_env = env.copy()
        for route in routes:
            prefix = route.upper().replace("-", "_")
            disabled_env.pop(prefix + "_BASE_URL", None)
            disabled_env.pop(prefix + "_API_KEY", None)
        (agent / "models.json").write_text(json.dumps({"providers": {}}))
        for disabled in ("true", "1", "!!js true"):
            patch.write_text(f"- id: llm-pi-ai\n  disabled: {disabled}\n  config:\n    providers: {{}}\n- id: llm-deepseek\n  disabled: {disabled}\n", encoding="utf-8")
            proc = subprocess.run(["bash", str(runner)], env=disabled_env, stdin=subprocess.DEVNULL, capture_output=True,
                                  text=True, start_new_session=True)
            assert proc.returncode == 0, f"禁用状态 {disabled} 仍强制要求凭据：" + proc.stderr + proc.stdout
        (agent / "models.json").write_text(json.dumps({"providers": providers}))
        patch.write_text(valid_patch)
        write_patch("http://192.0.2.1.", "google")
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0 and proc.stdout.strip().splitlines()[-1].startswith("http://192.0.2.1.|"), proc.stdout + proc.stderr
        write_patch("https://gateway.example/v1", "google")
        only_ref = patch.read_text().replace('        "baseURL": "https://gateway.example/v1" # gateway\n', '', 1)
        only_ref = only_ref.replace('      claude-newapi:\n', '      claude-newapi:\n        "apiKeyEnv": "LOCAL_CLAUDE"\n')
        patch.write_text(only_ref)
        env["CLAUDE_NEWAPI_BASE_URL"] = "https://env.example/v1"
        env["LOCAL_CLAUDE"] = "test-local-claude"
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, proc.stderr + proc.stdout
        assert proc.stdout.strip().splitlines()[-1].startswith("https://env.example/v1|"), proc.stdout
        env.pop("CLAUDE_NEWAPI_BASE_URL"); env.pop("LOCAL_CLAUDE")
        write_patch("https://gateway.example/v1", "google")
        custom = json.loads(json.dumps(providers))
        custom["gemini-newapi"]["apiKey"] = ""
        (agent / "models.json").write_text(json.dumps({"providers": custom}))
        patch.write_text(patch.read_text().replace('      google:\n', '      google:\n        "apiKeyEnv": "CUSTOM_GEMINI_KEY"\n'))
        env["GEMINI_NEWAPI_API_KEY"] = "test-default-key"
        rejected = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, start_new_session=True)
        error_output = rejected.stdout + rejected.stderr
        assert rejected.returncode != 0 and ("google" in error_output or "gemini-newapi" in error_output) and "apiKeyEnv" in error_output and "CUSTOM_GEMINI_KEY" not in error_output, error_output
        env["CUSTOM_GEMINI_KEY"] = "test-custom-key"
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, proc.stderr + proc.stdout
        env.pop("CUSTOM_GEMINI_KEY")
        (dsh_home / ".credentials.yaml").write_text("version: 1\nrefs: {CUSTOM_GEMINI_KEY: test-custom-key}\n")
        proc = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, start_new_session=True)
        assert proc.returncode == 0, proc.stderr + proc.stdout
        for bad_value in ("<YOUR_API_KEY>", "null"):
            (dsh_home / ".credentials.yaml").write_text(f"version: 1\nrefs:\n  CUSTOM_GEMINI_KEY: {bad_value}\n")
            rejected = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL,
                                      capture_output=True, text=True, start_new_session=True)
            error_output = rejected.stdout + rejected.stderr
            assert rejected.returncode != 0 and ("google" in error_output or "gemini-newapi" in error_output) and "引用" in error_output and "CUSTOM_GEMINI_KEY" not in error_output, error_output
        (dsh_home / ".credentials.yaml").write_text("version: 1\n")
        (agent / "models.json").write_text(json.dumps({"providers": providers}))
        env.pop("GEMINI_NEWAPI_API_KEY")
        write_patch("https://<YOUR_GATEWAY_HOST>")
        rejected = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, start_new_session=True)
        assert rejected.returncode != 0 and "占位符" in rejected.stdout + rejected.stderr
        write_patch("https://example.invalid:99999")
        rejected = subprocess.run(["bash", str(runner)], env=env, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, start_new_session=True)
        assert rejected.returncode != 0 and "有效的 http(s)" in rejected.stdout + rejected.stderr
    print("DSH 凭据：真实 YAML／末行／表达式通过；占位符、非法 URL、空白或缺值在写入前拒绝")


def check_dsh_cold_node_url():
    with tempfile.TemporaryDirectory(prefix="setup-dsh-cold-node-") as d:
        tmp = pathlib.Path(d)
        bindir = tmp / "bin"
        bindir.mkdir()
        for name in ("bash", "tar", "python3", "uname", "mkdir", "mv", "dirname", "cp", "rm", "date",
                     "tr", "cat", "chmod", "ln", "grep", "sort", "mktemp", "readlink", "sed", "awk", "basename", "head", "gzip", "cut", "xargs"):
            source = shutil.which(name)
            if source:
                os.symlink(source, bindir / name)
        node_bin = shutil.which("node") or str(pathlib.Path.home() / ".local/share/pi-node/current/bin/node")
        node_dist = tmp / "node-dist/bin"
        node_dist.mkdir(parents=True)
        wrapper = node_dist / "node"
        wrapper.write_text(f'#!/bin/sh\nexec "{node_bin}" "$@"\n')
        wrapper.chmod(0o755)
        archive = tmp / "node.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(node_dist.parent, arcname=".")
        curl = bindir / "curl"
        curl.write_text('''#!/bin/bash
case "$*" in
  *nodejs.org*)
    out=""
    while [ $# -gt 0 ]; do
      if [ "$1" = -o ]; then out="$2"; shift 2; else shift; fi
    done
    cp "$FAKE_NODE_TAR" "$out"
    ;;
  *) printf '%s\\n' "$*" >> "$UNEXPECTED_CURL"; exit 1 ;;
esac
''')
        curl.chmod(0o755)
        agent = tmp / ".pi/agent"
        agent.mkdir(parents=True)
        routes = ("claude-newapi", "codex-newapi", "anthropic-newapi", "gemini-newapi")
        (agent / "models.json").write_text(json.dumps({"providers": {
            route: {"baseUrl": "https://exa%mple.invalid", "apiKey": f"test-{route}"} for route in routes
        }}))
        (agent / "auth.json").write_text("{}")
        output = tmp / "output"
        env = {"HOME": str(tmp), "PATH": str(bindir), "XDG_DATA_HOME": str(output),
               "FAKE_NODE_TAR": str(archive), "UNEXPECTED_CURL": str(tmp / "unexpected-curl")}
        proc = subprocess.run([shutil.which("bash"), str(ROOT / "dsh-setup.sh"), "-y"], env=env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, start_new_session=True)
        assert proc.returncode != 0 and "有效的 http(s)" in proc.stdout + proc.stderr, proc.stdout + proc.stderr
        assert not output.exists(), "冷机非法 URL 在 Node 校验前已创建正式 ROOT"
        assert not (tmp / "unexpected-curl").exists(), "非法 URL 后仍继续下载套件"
    print("DSH 冷机：无系统 Node 时仅用暂存 Node 校验，非法 URL 不创建 ROOT")


def check_dsh_python_versions():
    body = function(ROOT / "dsh-setup.sh", "resolve_python3")[0]
    with tempfile.TemporaryDirectory(prefix="setup-dsh-python-") as d:
        tmp = pathlib.Path(d)
        bindir = tmp / "bin"
        bindir.mkdir()
        stub = '''#!/bin/sh
case "$MODE:$2" in
  3.10:*) exit 0 ;;
  3.9:*"(3, 10)"*) exit 1 ;;
  3.9:*) exit 0 ;;
  *) exit 1 ;;
esac
'''
        for name in ("python3", "python"):
            candidate = bindir / name
            candidate.write_text(stub)
            candidate.chmod(0o755)
        runner = tmp / "run.sh"
        runner.write_text(body + '\nresolve_python3 "$1"\n')
        env = {"PATH": str(bindir), "HOME": str(tmp)}
        for mode, minimum, expected in (("2.7", "6", 1), ("3.9", "6", 0), ("3.9", "10", 1), ("3.10", "10", 0)):
            env["MODE"] = mode
            proc = subprocess.run([shutil.which("bash"), str(runner), minimum], env=env,
                                  capture_output=True, text=True)
            assert proc.returncode == expected, (mode, minimum, proc.stderr)
    print("DSH Python：拒绝 Python 2；AGENTS 可用 3.9，PPT 前置要求 3.10+")


def check_codex_disabled_with_python_fallback():
    parts = [function(ROOT / "codex-setup.sh", name)[0] for name in
             ("resolve_python3", "value", "pval", "mem_disabled")]
    with tempfile.TemporaryDirectory(prefix="setup-codex-disabled-") as d:
        tmp = pathlib.Path(d)
        bin_dir = tmp / "bin"
        bin_dir.mkdir()
        python = bin_dir / "python"
        python.write_text(f'#!/bin/bash\nexec "{sys.executable}" "$@"\n')
        python.chmod(0o755)
        config = tmp / "config.toml"
        config.write_text('[plugins."claude-mem@claude-mem-local"]\nenabled = false\n')
        runner = tmp / "run.sh"
        runner.write_text(f'''
HOME={tmp}; BIN_EXT=""; IS_WIN=0; CONFIG={config}; PLAN_PYTHON_UV=0
{chr(10).join(parts)}
resolve_python3 || exit 1
if mem_disabled; then printf 'MEM=0\n'; else printf 'MEM=1\n'; fi
''')
        proc = subprocess.run([shutil.which("bash"), str(runner)], env={"PATH": str(bin_dir), "HOME": str(tmp)},
                              capture_output=True, text=True)
        assert proc.returncode == 0 and proc.stdout.strip() == "MEM=0", proc.stderr + proc.stdout
        codex = (ROOT / "codex-setup.sh").read_text(encoding="utf-8")
        assert "elif mem_disabled" in codex
        assert "无可用 Python，无法核对 Codex TOML" in codex
        assert "elif ! command -v python3" in codex
    print("Codex：仅有 python 也能识别显式禁用，执行前再次核对；无解释器保守跳过")


def check_python_fallback():
    body, _, _ = function(ROOT / "pi-setup.sh", "resolve_python3")
    with tempfile.TemporaryDirectory(prefix="setup-python-") as d:
        tmp = pathlib.Path(d)
        bin_dir = tmp / "bin"
        bin_dir.mkdir()
        os.symlink(shutil.which("bash"), bin_dir / "bash")
        uv = bin_dir / "uv"
        uv.write_text('#!/bin/bash\nif [ "$1 $2" = "python install" ]; then printf install >> "$UV_LOG"; exit 0; fi\nif [ "$1 $2" = "python find" ]; then printf "%s" "$FAKE_PY"; exit 0; fi\nexit 1\n')
        fake = bin_dir / "fake-python"
        fake.write_text("#!/bin/bash\nexit 0\n")
        uv.chmod(0o755)
        fake.chmod(0o755)
        runner = tmp / "run.sh"
        env = os.environ.copy() | {"PATH": str(bin_dir), "HOME": str(tmp), "UV_LOG": str(tmp / "uv.log"), "FAKE_PY": str(fake)}
        runner.write_text(f'BIN_EXT=""; IS_WIN=0; PLAN_PYTHON_UV=0\n{body}\nresolve_python3\n')
        refused = subprocess.run([str(bin_dir / "bash"), str(runner)], env=env, capture_output=True, text=True)
        assert refused.returncode != 0 and not (tmp / "uv.log").exists(), "拒绝后仍调用 uv"
        runner.write_text(f'BIN_EXT=""; IS_WIN=0; PLAN_PYTHON_UV=1\n{body}\nresolve_python3 && bash --noprofile --norc -c \'python3 -c pass\'\n')
        subprocess.run([str(bin_dir / "bash"), str(runner)], env=env, capture_output=True, text=True, check=True)
        assert (tmp / "uv.log").read_text() == "install"
    print("Python 兜底：拒绝零安装，允许后子 Bash 继承解释器")


def check_cold_windows_plan():
    body, _, _ = function(ROOT / "pi-setup.sh", "collect_setup_plan")
    with tempfile.TemporaryDirectory(prefix="setup-cold-win-") as d:
        tmp = pathlib.Path(d)
        bin_dir = tmp / "bin"
        bin_dir.mkdir()
        for name in ("bash", "grep", "sed", "head", "awk", "cut", "basename", "dirname", "mktemp", "rm", "cp", "mv", "mkdir", "uname", "date", "chmod", "tar", "tr"):
            source = shutil.which(name)
            if source:
                os.symlink(source, bin_dir / name)
        (tmp / "modules").mkdir()
        (tmp / "modules/run.sh").write_text((ROOT / "modules/run.sh").read_text(encoding="utf-8"))
        runner = tmp / "plan.sh"
        runner.write_text(f'''
IS_WIN=1; BIN_EXT=.exe; ASSUME_YES=1
HOME={tmp}; AGENT_DIR={tmp}/.pi/agent
SETTINGS={tmp}/settings.json; OC_MC_CACHE={tmp}/oc-cache; SELF_RAW=https://invalid.example
SKILLS_EXTERNAL=skip; AGENTS_TAIL=0
ask() {{ [ "${{2:-N}}" = Y ]; }}
net_ok() {{ return 0; }}
curl() {{ return 1; }}
_pkg_registered() {{ return 1; }}
cm_vendor_in_settings() {{ return 1; }}
cm_conflicts_in_settings() {{ return 0; }}
acquire_source() {{ SOURCE_ROOT=/nonexistent; return 0; }}
collect_gateway_values() {{ return 0; }}
{body}
collect_setup_plan
printf '%s %s %s %s %s %s\n' "$PLAN_NODE" "$PLAN_PI_INSTALL" "$PLAN_PI_PKGS" "$PLAN_CM_GROUP" "$PLAN_MEM_RUNTIME" "$PLAN_SKILLS_EXTERNAL$PLAN_AGENTS_TAIL"
''')
        env = os.environ.copy() | {"PATH": str(bin_dir), "HOME": str(tmp)}
        proc = subprocess.run([str(bin_dir / "bash"), str(runner)], env=env, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, start_new_session=True)
        assert proc.returncode == 0, proc.stderr + proc.stdout
        assert proc.stdout.strip().splitlines()[-1] == "1 1 1 1 1 00", proc.stdout
    print("冷启动计划：无 Node/Python 仍选装 Pi 与配套包，环境预答不被覆盖")


def check_write_refusal():
    parts = []
    for name in ("prune_legacy_ui_packages", "ensure_image_gen", "ensure_mem_provider", "ensure_mem_worker_keys"):
        body, _, _ = function(ROOT / "pi-setup.sh", name)
        parts.append(body)
    script = "\n".join(parts) + '\nPLAN_WRITE_CFG=0\nprune_legacy_ui_packages\nensure_image_gen\nensure_mem_provider /nonexistent\nensure_mem_worker_keys /nonexistent\n'
    proc = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    assert "`pi install" not in (ROOT / "pi-setup.sh").read_text(encoding="utf-8")
    pi = (ROOT / "pi-setup.sh").read_text(encoding="utf-8")
    for needle in (
        'elif [ "${PLAN_PI_PKGS:-0}" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then',
        '[ "$mcp_ready" = 1 ] && [ "$mcp_needed" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]',
        'elif [ "${PLAN_MEM_RUNTIME:-0}" = 1 ] && [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then',
        'if [ "${PLAN_WRITE_CFG:-1}" = 1 ]; then chmod 600 "$MODELS"',
        '[ "${PLAN_WRITE_CFG:-1}" != 1 ] || [ ! -f "$AUTH" ] || chmod 600 "$AUTH"',
    ):
        assert needle in pi, f"Pi 写入门缺失：{needle}"
    oc = (ROOT / "opencode-setup.sh").read_text(encoding="utf-8")
    assert 'if [ "$PLAN_WRITE_CFG" = 1 ]; then chmod 600 "$SETTINGS"' in oc
    assert 'if [ "$PLAN_WRITE_CFG" = 1 ]; then\n    echo "Ponytail 已登记' in oc
    codex = (ROOT / "codex-setup.sh").read_text(encoding="utf-8")
    assert 'if [ "$PLAN_MEM" = 1 ] && [ "$PLAN_WRITE_CFG" = 1 ]; then\n    collect_gateway_values' in codex
    print("拒绝配置写入：辅助修复、安装登记、MCP、官方安装器与权限修改均受同一门控")


def check_pi_magic_guard():
    pi_text = (ROOT / "pi-setup.sh").read_text(encoding="utf-8")
    plan = pi_text[pi_text.index("local oc_pinned_plan"):pi_text.index("if _pkg_registered npm:@cortexkit/pi-magic-context")]
    assert "npm view @cortexkit/pi-magic-context version 2>/dev/null || true" not in plan and 'if [ "$pi_plan_query_ok" != 1 ]' in plan
    assert "mc_cache_version" in plan, "计划阶段未用与执行共享的缓存版本探测"
    # 计划与执行共用同一探测:V2 的 npm/<代次>/ 布局必须被读到,否则会误判为"没有缓存"而放行
    helper = "\n".join(function(ROOT / "pi-setup.sh", name)[0] for name in ("mc_cache_state", "mc_cache_version"))
    guard = function(ROOT / "pi-setup.sh", "mc_guard")[0]
    with tempfile.TemporaryDirectory(prefix="setup-pi-mc-guard-") as d:
        tmp = pathlib.Path(d)
        cache = tmp / "cache"
        cache.mkdir()
        (cache / "package.json").write_text('{"dependencies":{"@cortexkit/opencode-magic-context":"1.0.0"}}')
        bindir = tmp / "bin"
        bindir.mkdir()
        os.symlink(shutil.which("python3"), bindir / "python3")
        os.symlink(shutil.which("bash"), bindir / "bash")
        npm = bindir / "npm"
        npm.write_text('#!/bin/sh\nprintf "%s\\n" "${NPM_VERSION:-}"\n[ "${NPM_FAIL:-0}" != 1 ] || exit 1\n')
        npm.chmod(0o755)
        def run_guard(oc_cache, npm_cache="", **extra):
            env = dict(os.environ, **{"PATH": str(bindir), "NPM_FAIL": "0"})
            env.update({k: str(v) for k, v in extra.items()})
            script = (f'OC_MC_CACHE={oc_cache}; OC_NPM_CACHE={npm_cache}; PLAN_MC_BLOCKED=1; PLAN_OC_CACHE_CLEAN=0\n'
                      f'{helper}\n{guard}\nmc_guard >/dev/null 2>&1\nprintf "%s" "$mc_blocked"\n')
            return subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, check=True)
        for version, fail, expected in (("", True, "1"), ("1.0.0", True, "1"), ("1.0.0", False, "0"), ("2.0.0", False, "1")):
            proc = run_guard(cache, NPM_VERSION=version, NPM_FAIL="1" if fail else "0")
            assert proc.stdout == expected, (version, fail, proc.stdout, proc.stderr)
        (cache / "package.json").write_text("{invalid")
        assert run_guard(cache).stdout == "1", "清单损坏时解除了已确认阻断"
        (cache / "package.json").unlink()
        assert run_guard(cache).stdout == "1", "清单缺失但缓存仍在时解除了已确认阻断"
        cache.rmdir()
        assert run_guard(cache).stdout == "0", "缓存确实移除后仍保持阻断"

        # 原样复现 opencode V2 布局:npm/<数字代次>/node_modules/…/package.json,没有 packages/ 清单。
        # 只按旧 packages/ 探测会把它当成"没有缓存"而放行;共享探测必须取最新代次的版本。
        v2 = tmp / "npm/@cortexkit/opencode-magic-context@latest"
        for gen, ver in (("1700000000000", "0.49.75"), ("1700000000001", "0.49.76")):
            pkg = v2 / gen / "node_modules/@cortexkit/opencode-magic-context"
            pkg.mkdir(parents=True)
            (pkg / "package.json").write_text(json.dumps({"name": "@cortexkit/opencode-magic-context", "version": ver}))
        (v2 / "1700000000000/package.json").write_text('{"dependencies":{"@cortexkit/opencode-magic-context":"0.49.75"}}')
        assert run_guard(tmp / "no-old-layout", v2, NPM_VERSION="0.49.76").stdout == "0", "V2 与 Pi 版本一致却仍阻断"
        assert run_guard(tmp / "no-old-layout", v2, NPM_VERSION="0.49.77").stdout == "1", "V2 版本不一致被当成没有缓存而放行"
        assert run_guard(tmp / "no-old-layout", v2, NPM_VERSION="").stdout == "1", "无法核实 Pi 版本时放行了 V2 缓存"
        assert run_guard(tmp / "no-old-layout", tmp / "empty-npm").stdout == "0", "两处都没有缓存时仍阻断（应沿用旧行为放行）"
        (v2 / "1700000000001/node_modules/@cortexkit/opencode-magic-context/package.json").write_text("{invalid")
        cache.mkdir(); (cache / 'package.json').write_text('{"dependencies":{"@cortexkit/opencode-magic-context":"0.49.75"}}')
        assert run_guard(cache, v2, NPM_VERSION='0.49.75').stdout == '1', '最新代次损坏不可回退到碰巧匹配的旧版本'
        assert run_guard(tmp / "no-old-layout", v2, NPM_VERSION="0.49.76").stdout == "1", "V2 最新代次清单损坏仍放行"
        if hasattr(os, "geteuid") and os.geteuid() != 0:
            locked = tmp / "locked"
            locked_cache = locked / "cache"
            locked_cache.mkdir(parents=True)
            (locked_cache / "package.json").write_text("{invalid")
            locked.chmod(0)
            try:
                assert run_guard(locked_cache).stdout == "1", "父目录不可遍历被当成缓存已移除"
            finally:
                locked.chmod(0o755)
        broken = tmp / "broken-cache"
        broken.symlink_to(tmp / "missing-target", target_is_directory=True)
        assert run_guard(broken).stdout == "1", "不可解析的缓存链接被当成已移除"
        broken_parent = tmp / "broken-parent"
        broken_parent.symlink_to(tmp / "missing-parent", target_is_directory=True)
        parent_cache = broken_parent / "cache"
        assert run_guard(parent_cache).stdout == "1", "父级链接断开被当成缓存不存在"
    print("Pi magic-context：复查失败保持阻断；仅版本一致或缓存移除才解除")


def check_context_mode_conflicts():
    parts = [function(ROOT / "pi-setup.sh", name)[0] for name in
             ("pkg_installed", "cm_registered", "cm_package_entries", "cm_vendor_in_settings", "cm_conflicts_in_settings")]
    with tempfile.TemporaryDirectory(prefix="setup-cm-conflicts-") as d:
        tmp = pathlib.Path(d)
        agent_dir = tmp / "agent"
        settings = tmp / "settings.json"
        settings.write_text('{"packages":[{"source":"vendor/context-mode"},{"source":"npm:context-mode"}]}')
        script = "\n".join(parts) + f'\nSETTINGS={settings}\nAGENT_DIR={agent_dir}\ncm_vendor_in_settings\npkg_installed npm:context-mode\ncm_registered\ncm_conflicts_in_settings\n'
        proc = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=True)
        assert "npm:context-mode" in proc.stdout, proc.stdout
        settings.write_text('{"packages":["vendor/context-mode"]}')
        proc = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=True)
        assert proc.stdout.strip() == "", proc.stdout

        agent_dir = tmp / "agent"
        for relative in ("../context-mode-old", "../context-mode old", "vendor/context-mode-old", "../renamed-plugin"):
            package_dir = pathlib.Path(os.path.normpath(agent_dir / relative))
            package_dir.mkdir(parents=True, exist_ok=True)
            (package_dir / "package.json").write_text('{"name":"context-mode"}')
        unrelated = agent_dir / "../context-mode-unrelated"
        unrelated.mkdir(parents=True, exist_ok=True)
        (unrelated / "package.json").write_text('{"name":"other-package"}')
        settings.write_text(json.dumps({"packages": [
            {"source": "../context-mode-old"}, {"source": "../context-mode old"},
            {"source": "vendor/context-mode-old"}, {"source": "../renamed-plugin"},
            {"source": "npm:context-mode"}, {"source": "npm:context-mode@1.0.169"},
            "git:github.com/mksglu/context-mode", "https://github.com/mksglu/context-mode.git", {"source": "vendor/context-mode"},
            "npm:@fixture/context-mode-indicator", "git:github.com/example/context-mode",
            "../context-mode-unrelated",
        ], "description": "npm:context-mode"}))
        proc = subprocess.run(["bash", "-c", "\n".join(parts) + f'\nSETTINGS={settings}\nAGENT_DIR={agent_dir}\ncm_conflicts_in_settings\n'],
                              capture_output=True, text=True, check=True)
        assert [json.loads(line) for line in proc.stdout.splitlines()] == [
            "../context-mode-old", "../context-mode old", "vendor/context-mode-old", "../renamed-plugin",
            "npm:context-mode", "npm:context-mode@1.0.169", "git:github.com/mksglu/context-mode",
            "https://github.com/mksglu/context-mode.git",
        ], proc.stdout
        other_vendor = tmp / "other/vendor/context-mode"
        other_vendor.mkdir(parents=True)
        (other_vendor / "package.json").write_text('{"name":"context-mode"}')
        for packages, managed in (([str(other_vendor)], "no"), (["vendor/context-mode", str(other_vendor)], "yes")):
            settings.write_text(json.dumps({"packages": packages}))
            script = "\n".join(parts) + f'\nSETTINGS={settings}\nAGENT_DIR={agent_dir}\nif cm_vendor_in_settings; then echo managed=yes; else echo managed=no; fi\ncm_conflicts_in_settings\n'
            proc = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=True)
            assert proc.stdout.splitlines() == [f"managed={managed}", json.dumps(str(other_vendor))], proc.stdout

        text = (ROOT / "pi-setup.sh").read_text(encoding="utf-8")
        loop = re.search(r'  while IFS= read -r s; do\n.*?  done <<< "\$cm_stale"', text, re.S)
        assert loop is not None
        fake_pi = tmp / "pi"
        fake_pi.write_text('#!/bin/bash\nprintf "%s\\n" "$2" >> "$PI_LOG"\n')
        fake_pi.chmod(0o755)
        log = tmp / "remove.log"
        env = os.environ.copy() | {"PI_LOG": str(log)}
        script = loop.group(0) + '\n'
        env_script = f'PI_BIN={fake_pi}; PLAN_CM_GROUP=1; PLAN_WRITE_CFG=1; cm_stale=$\'/tmp/context-mode old\\nnpm:context-mode@1.0.169\'\n'
        subprocess.run(["bash", "-c", env_script + script], env=env, capture_output=True, text=True, check=True)
        assert log.read_text().splitlines() == ["/tmp/context-mode old", "npm:context-mode@1.0.169"]

        prune = function(ROOT / "pi-setup.sh", "prune_legacy_ui_packages")[0]
        settings.write_text('{"packages":[{"source":"npm:pi-zentui"},{"source":"npm:other"}]}')
        proc = subprocess.run(["bash", "-c", prune + f'\nPLAN_WRITE_CFG=1\nSETTINGS={settings}\nprune_legacy_ui_packages\n'],
                              capture_output=True, text=True, check=True)
        assert json.loads(settings.read_text())["packages"] == [{"source": "npm:other"}]
    print("context-mode／Pi 包对象：精确冲突识别、旧路径清理与相似包保留均通过")


def check_external_skip_filter():
    text = (ROOT / "skills-external.sh").read_text(encoding="utf-8")
    match = re.search(r"names=\(\)\nfor name in \$third; do\n.*?^done", text, re.S | re.M)
    assert match is not None
    script = f'''
DESIGN_SKILLS="ui-ux-pro-max huashu-design design-taste-frontend"
third="$DESIGN_SKILLS other-third"
with_design=0
claude_safe() {{ return 0; }}
{match.group(0)}
printf '%s\n' "${{names[@]}}"
'''
    proc = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=True)
    assert proc.stdout.splitlines()[-1] == "other-third", proc.stdout
    assert "skills@latest update -g -y" in text, "通用 update 未启用跳过删除确认的非交互模式"
    print("外部依赖：skip 排除设计项；通用 update 非交互且不删除未选项")


def check_codex_codegraph_exact_name():
    text = (ROOT / "modules/codegraph/setup.sh").read_text(encoding="utf-8")
    match = re.search(r'  codex\)\n(.*?)\n    ;;', text, re.S)
    assert match is not None
    with tempfile.TemporaryDirectory(prefix="setup-codex-codegraph-") as d:
        tmp = pathlib.Path(d)
        log = tmp / "add.log"
        script = f'''
cg=/tmp/codegraph
native() {{ printf '%s' "$1"; }}
codex() {{
  if [ "$1 $2" = "mcp list" ]; then printf '%s\\n' "$LIST_OUT"; return 0; fi
  if [ "$1 $2" = "mcp add" ]; then printf '%s\\n' "$3" >> "$ADD_LOG"; return 0; fi
  return 1
}}
{match.group(1)}
'''
        env = os.environ.copy() | {"ADD_LOG": str(log), "LIST_OUT": "codegraph-extra: remote"}
        subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, check=True)
        assert log.read_text().splitlines() == ["codegraph"]
        log.unlink()
        env["LIST_OUT"] = "codegraph: local"
        subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, check=True)
        assert not log.exists(), "已有完整 codegraph 名称时不应重复注册"
    print("Codex CodeGraph：仅完整名称视为已登记，相似名称不误判")


def check_opencode_compaction_plan():
    text = (ROOT / "opencode-setup.sh").read_text(encoding="utf-8")
    merge = re.search(r'oc_out=.*?<<\'PYEOF\'\n(.*?)\nPYEOF', text, re.S)
    assert merge is not None, "找不到 OpenCode 实际配置合并"
    with tempfile.TemporaryDirectory(prefix="setup-oc-compaction-") as d:
        tmp = pathlib.Path(d)
        target, jsonc, tpl, cand = (tmp / name for name in ("opencode.json", "opencode.jsonc", "template.json", "candidate.json"))
        cases = [
            ({}, False, "0", None),
            ({}, False, "1", {"auto": False}),
            ({"compaction": {"prune": False}}, False, "1", {"prune": False}),
            ({"compaction": {"auto": True}}, False, "1", {"auto": True}),
            ({"compaction": {"prune": False}}, True, "1", {"prune": False}),
        ]
        for existing, use_jsonc, plan, expected in cases:
            target.write_text("{}" if use_jsonc else json.dumps(existing), encoding="utf-8")
            if use_jsonc: jsonc.write_text(json.dumps(existing), encoding="utf-8")
            elif jsonc.exists(): jsonc.unlink()
            tpl.write_text('{"compaction":{"auto":false},"other":1}', encoding="utf-8")
            cand.unlink(missing_ok=True)
            subprocess.run([sys.executable, "-c", merge.group(1), str(target), str(jsonc), str(tpl), str(cand), "2", "0", plan],
                           capture_output=True, text=True, check=True)
            data = json.loads(cand.read_text())
            assert data["other"] == 1
            if expected is None: assert "compaction" not in data, data
            else: assert data["compaction"] == expected, data
        fallback = re.search(r'# ---- 5\.1 compaction.*?<<\'PYEOF\'\n(.*?)\nPYEOF', text, re.S)
        assert fallback is not None and 'grep -qs' not in fallback.group(0)
        cfg = pathlib.Path(d) / "opencode.json"
        jsonc.unlink(missing_ok=True)
        cfg.write_text('{"nested":{"compaction":{"auto":true}}}', encoding="utf-8")
        subprocess.run([sys.executable, "-c", fallback.group(1), str(cfg), str(jsonc)], check=True)
        data = json.loads(cfg.read_text())
        assert data["compaction"] == {"auto": False} and data["nested"]["compaction"]["auto"] is True
        data["compaction"] = {"auto": True}
        cfg.write_text(json.dumps(data), encoding="utf-8")
        subprocess.run([sys.executable, "-c", fallback.group(1), str(cfg), str(jsonc)], check=True)
        assert json.loads(cfg.read_text())["compaction"] == {"auto": True}
        cfg.unlink()
        jsonc.write_text('{"text":"sentinel,]suffix", // comment\n "compaction":{"prune":false},}', encoding="utf-8")
        subprocess.run([sys.executable, "-c", fallback.group(1), str(cfg), str(jsonc)], check=True)
        assert not cfg.exists(), "JSONC 已有 compaction，兜底仍新建 auto:false"
    print("OpenCode compaction：计划变量一致；模板过滤与顶层／嵌套键判断通过")


def check_opencode_readonly_plans():
    pony = function(ROOT / "opencode-setup.sh", "plan_pony_default")[0]
    collect = function(ROOT / "opencode-setup.sh", "collect_setup_plan")[0]
    with tempfile.TemporaryDirectory(prefix="setup-oc-readonly-") as d:
        tmp = pathlib.Path(d)
        cfg = tmp / "oc"
        cfg.mkdir()
        config = cfg / "opencode.json"
        runner = tmp / "pony.sh"
        runner.write_text(f'''
{pony}
curl() {{ [ -n "$LATEST" ] || return 1; printf '{{"version":"%s"}}\n' "$LATEST"; }}
plan_pony_default
''')
        env = os.environ.copy() | {"CFG": str(cfg), "HOME": str(tmp), "XDG_CACHE_HOME": str(tmp / "cache"), "LATEST": "9.9.9"}
        config.write_text("{}")
        result = subprocess.run(["bash", str(runner)], env=env, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == "N", "无缓存不应要求刷新"
        package = tmp / "cache/opencode/npm/@dietrichgebert/ponytail@latest/0/node_modules/@dietrichgebert/ponytail/package.json"
        package.parent.mkdir(parents=True)
        package.write_text('{"version":"1.0.0"}')
        legacy_package = tmp / "cache/opencode/packages/@dietrichgebert/ponytail@latest/0/node_modules/@dietrichgebert/ponytail/package.json"
        legacy_package.parent.mkdir(parents=True)
        legacy_package.write_text('{"version":"0.0.1"}')
        for entry in ('@dietrichgebert/ponytail@1.2.3', 'file:///tmp/ponytail-custom'):
            config.write_text(json.dumps({"plugins": [entry]}))
            result = subprocess.run(["bash", str(runner)], env=env, capture_output=True, text=True, check=True)
            assert result.stdout.strip() == "N", f"钉版／本地路径被误判：{entry}"
        config.write_text('{"plugins":["@dietrichgebert/ponytail@latest"]}')
        for local, latest, expected in (("1.2.3", "1.2.3", "N"), ("2.0.0", "1.2.3", "N"),
                                        ("1.0.0", "2.0.0", "Y"), ("1.0.0", "", "N")):
            package.write_text(json.dumps({"version": local}))
            env["LATEST"] = latest
            result = subprocess.run(["bash", str(runner)], env=env, capture_output=True, text=True, check=True)
            assert result.stdout.strip() == expected, (local, latest, result.stdout, result.stderr)

        check_runner = tmp / "check.sh"
        check_runner.write_text(f'''
CHECK_ONLY=1
ask() {{ exit 9; }}
net_ok() {{ exit 9; }}
plan_pony_default() {{ exit 9; }}
acquire_source() {{ SOURCE_ROOT={tmp}; return 0; }}
{collect}
collect_setup_plan
printf 'WRITE=%s|EXTERNAL=%s|PONY=%s\n' "$PLAN_WRITE_CFG" "$PLAN_SKILLS_EXTERNAL" "$PLAN_PONYTAIL"
''')
        result = subprocess.run(["bash", str(check_runner)], capture_output=True, text=True)
        assert result.returncode == 0 and result.stdout.strip() == "WRITE=0|EXTERNAL=skip|PONY=0", result.stderr + result.stdout
        dsh_plan = function(ROOT / "dsh-setup.sh", "collect_setup_plan")[0]
        assert "cordis.patch.yml" not in dsh_plan, "已有 DSH patch 仍包住安装选择"
    print("OpenCode 只读计划：Ponytail 各档位与 --check 零询问；DSH 重跑选择不被 patch 包裹")


def check_mem_search_setup():
    """Run each setup's actual discovery step without invoking a shared worker installer."""
    for host, choice in [('pi', 'PLAN_MEM_RUNTIME'), ('opencode', 'PLAN_CLAUDE_MEM')]:
        source = (ROOT / f'{host}-setup.sh').read_text()
        call = source.index('"$(npath "$SOURCE_ROOT/scripts/link-mem-search.mjs')
        begin = source.rindex('\nif ', 0, call)
        assert source.index(f'install --ide {host}') < begin < source.index('_ss="$SOURCE_ROOT/skills-sync.sh"')
        if host == 'opencode':
            assert call < source.index('if [ "$PLUGINS_ONLY" = 1 ]; then', call)
        body = 'set -eu\nnpath() { printf %s "$1"; }\n'
        if host == 'opencode':
            body += 'unset SOURCE_ROOT\nfile_url() { printf "file://%s" "$1"; }\n' + function(ROOT / 'opencode-setup.sh', 'acquire_source')[0] + '\n'
        body += source[begin:source.index('\nfi\n', call)+4]
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp)
            skill = home / 'custom config/plugins/marketplaces/thedotmack/plugin/skills/mem-search'
            dest = home / '.agents/skills/mem-search'
            plugin = home / ('pi/extensions/claude-mem/index.js' if host == 'pi' else 'plugins/claude-mem.js')
            env = dict(os.environ, HOME=tmp, SOURCE_ROOT=str(ROOT), AGENT_SKILLS_SOURCE=str(ROOT), CLAUDE_CONFIG_DIR=str(home/'custom config'),
                       AGENT_DIR=str(home/'pi'), CLAUDE_PLUGIN=str(plugin), PLAN_WRITE_CFG='1')
            def run(selected='0', write='1'):
                return subprocess.run(['bash', '-c', body], env=dict(env, **{choice:selected, 'PLAN_WRITE_CFG':write}), capture_output=True)
            assert run().returncode == 0 and not dest.exists()
            assert run('1').returncode != 0 and not dest.exists()
            plugin.parent.mkdir(parents=True); plugin.touch()
            assert run('1').returncode != 0 and not dest.exists()
            skill.mkdir(parents=True); (skill/'SKILL.md').write_text('official')
            assert run('1','0').returncode == 0 and not dest.exists()
            assert run('1').returncode == 0 and (dest/'SKILL.md').samefile(skill/'SKILL.md')
            assert b'unchanged:' in run().stdout
            (skill/'SKILL.md').write_text('updated'); assert (dest/'SKILL.md').read_text() == 'updated'
            if os.name == 'nt': dest.rmdir()  # junction, not its target
            else: dest.unlink()
            dest.mkdir(); (dest/'SKILL.md').write_text('mine')
            assert run().returncode != 0 and (dest/'SKILL.md').read_text() == 'mine'
    print('mem-search：Pi/OpenCode setup 正式接线、冷机、重跑、冲突与只读模式通过')


# 公共块写入宿主用户级文件:被测函数按 HOME 和宿主目录变量定位目标,
# 回归必须把这些全部收进临时目录,否则会改写本机 live 指令文件。
AGENT_ENV_KEYS = ("PI_CODING_AGENT_DIR", "OPENCODE_CONFIG_DIR", "CLAUDE_CONFIG_DIR", "CODEX_HOME",
                  "DSH_HOME", "DSH_AGENTS_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
                  "AGENTS_TAIL", "AGENTS_TAIL_HOST")


def agents_env(home, **extra):
    env = os.environ.copy()
    for key in AGENT_ENV_KEYS:
        env.pop(key, None)
    env.update({"HOME": str(home), "XDG_DATA_HOME": str(home / ".local/share")})
    env.update(extra)
    return env


def agents_runner(tmp, project):
    body, _, _ = function(ROOT / "skills-sync.sh", "inject_agents_md")
    runner = tmp / "run.sh"
    runner.write_text(f"set -eu\nsource_root={ROOT}\nAGENTS_TAIL=${{AGENTS_TAIL:-1}}\n{body}\ninject_agents_md\n")
    return lambda env: subprocess.run(["bash", str(runner)], env=env, cwd=project,
                                      capture_output=True, text=True, stdin=subprocess.DEVNULL)


def check_agents_tail():
    with tempfile.TemporaryDirectory(prefix="setup-agents-") as d:
        tmp = pathlib.Path(d)
        home = tmp / "home"
        hosts = {"pi": home / ".pi/agent", "opencode": home / ".config/opencode",
                 "codex": home / ".codex", "claude": home / ".claude",
                 "dsh": home / ".local/share/agent-skills/dsh/home"}
        for root in hosts.values():
            root.mkdir(parents=True)
        project = tmp / "project"
        project.mkdir()
        (project / "AGENTS.md").write_text("PROJECT-OWN-TEXT\n")
        run = agents_runner(tmp, project)
        files = {host: root / ("CLAUDE.md" if host == "claude" else "AGENTS.md")
                 for host, root in hosts.items()}

        assert run(agents_env(home)).returncode == 0
        first = {host: path.read_bytes() for host, path in files.items()}
        for host, data in first.items():
            assert data.count(b"<!-- memory-system:start -->") == 1, host
        assert run(agents_env(home)).returncode == 0
        assert {host: path.read_bytes() for host, path in files.items()} == first, "重跑改动了用户级文件"
        assert (project / "AGENTS.md").read_text() == "PROJECT-OWN-TEXT\n", "项目 AGENTS.md 被改动"

        # AGENTS_TAIL=0 不写任何用户级文件
        off = agents_env(tmp / "off", AGENTS_TAIL="0")
        assert run(off).returncode == 0
        assert not any((tmp / "off").rglob("AGENTS.md")) and not (tmp / "off/.claude/CLAUDE.md").exists()

        # 显式宿主:目录不存在也按安装目标创建,其他宿主不碰
        explicit = agents_env(tmp / "explicit", AGENTS_TAIL_HOST="pi")
        assert run(explicit).returncode == 0
        assert (tmp / "explicit/.pi/agent/AGENTS.md").is_file()
        assert not (tmp / "explicit/.codex").exists()

        # Codex 非空 override 优先:告警失败,改写与新建都不得发生
        override_home = tmp / "override"
        (override_home / ".codex").mkdir(parents=True)
        (override_home / ".codex/AGENTS.override.md").write_text("KEEP-OVERRIDE\n")
        override = agents_env(override_home)
        assert run(override).returncode != 0
        assert (override_home / ".codex/AGENTS.override.md").read_text() == "KEEP-OVERRIDE\n"
        assert not (override_home / ".codex/AGENTS.md").exists()

        # Pi 已有全局规则文件时复用它,不另建 AGENTS.md
        pi_home = tmp / "pi-override"
        (pi_home / ".pi/agent").mkdir(parents=True)
        (pi_home / ".pi/agent/AGENTS.override.md").write_text("PI-KEEP\n")
        assert run(agents_env(pi_home)).returncode == 0
        assert "PI-KEEP" in (pi_home / ".pi/agent/AGENTS.override.md").read_text()
        assert not (pi_home / ".pi/agent/AGENTS.md").exists()

        # 残缺标记:原样保留并失败
        broken_home = tmp / "broken"
        broken = broken_home / ".pi/agent/AGENTS.md"
        broken.parent.mkdir(parents=True)
        malformed = "before\n<!-- memory-system:start -->\nPROJECT-MUST-SURVIVE\n"
        broken.write_text(malformed)
        assert run(agents_env(broken_home, AGENTS_TAIL_HOST="pi")).returncode != 0
        assert broken.read_text() == malformed
    print("AGENTS.tail：写入已安装宿主用户级文件并幂等，项目与覆盖文件不被改写")


def check_multi_agent_auto_trigger():
    """用户未点名时也有主动发现入口，但无合格分支或缺 skill 时不委派。"""
    def managed_block(text):
        start = text.index("<!-- memory-system:start -->")
        end = text.index("<!-- memory-system:end -->", start) + len("<!-- memory-system:end -->")
        return text[start:end]

    tail = managed_block((ROOT / "AGENTS.tail.md").read_text(encoding="utf-8"))
    steady = (ROOT / "skills/base/steady-do/SKILL.md").read_text(encoding="utf-8")
    skill = (ROOT / "skills/base/multi-agent/SKILL.md").read_text(encoding="utf-8")
    frontmatter = skill.split("---", 2)[1]
    description = next(line for line in frontmatter.splitlines() if line.startswith("description:"))
    trigger = ("When substantial lines of inquiry can start independently, draw on distinct evidence, "
               "and each inform a decision, load `multi-agent` before dispatching and follow its guide")
    assert trigger in tail
    assert "if it is unavailable, keep implementation single-agent" in tail
    assert "For two or more substantial independent branches or an explicit multi-agent request, use [multi-agent](../multi-agent/SKILL.md)" in steady
    assert "or when independent branches each change the deliverable" in description
    assert "Two substantial independent branches are a reason to use this skill" in skill
    assert "Default to one Agent when no branch qualifies" in skill
    assert "`quick-do` keeps implementation in one session" in skill
    assert "standard-quality `verification-reviewer` is independent review" in skill
    assert "Read the complete [task decomposition and optional worktree guide](references/guide.md) before launching workers" in skill
    assert "Development changes default to standard quality" in tail
    assert "load `unslop-changes`" in tail and "load the `verification` skill" in tail
    assert "separately inspect the task's authorized diff as a cleanup pass" in tail
    assert "native `verification-reviewer`" in tail
    assert "Tests run before Unslop do not replace the post-Unslop real behavior check" in tail
    assert "Users may explicitly select light quality for a low-risk task" in tail
    assert "Light is not a risk waiver" in tail and "symlink-escape fix is a security boundary" in tail
    assert "Never modify files the user explicitly excluded" in tail
    quick = (ROOT / "skills/base/quick-do/SKILL.md").read_text(encoding="utf-8")
    assert all("New features in either tier need a minimal executable regression" in s for s in (quick, steady))

    # 用户在原会话点名执行时，从可发现的 skill 进入执行段，而不是被送去新会话。
    plan = (ROOT / "skills/base/plan-brief/SKILL.md").read_text(encoding="utf-8")
    assert "按计划执行" in plan.split("---", 2)[1] and "Swarm" in description
    execution = plan.partition("\n## Execute an agreed plan\n")[2].partition("\n## ")[0]
    assert "../steady-do/SKILL.md" in execution and "../multi-agent/SKILL.md" in execution

    # 两个主宿主必须部署同一份工作流规则。
    with tempfile.TemporaryDirectory(prefix="multi-agent-trigger-") as d:
        tmp = pathlib.Path(d)
        home = tmp / "home"
        (home / ".config/opencode").mkdir(parents=True)
        (home / ".pi/agent").mkdir(parents=True)
        project = tmp / "project"
        project.mkdir()
        run = agents_runner(tmp, project)
        result = run(agents_env(home))
        assert result.returncode == 0, result.stdout + result.stderr
        for rel in (".config/opencode/AGENTS.md", ".pi/agent/AGENTS.md"):
            assert managed_block((home / rel).read_text(encoding="utf-8")) == tail, rel
    print("Multi-agent：独立任务无需用户点名即可发现；无合格分支或缺 skill 时保持单会话")


def check_agents_tail_old_cache():
    """新 setup 遇到旧缓存 skills-sync.sh 时不得把 AGENTS_TAIL=1 传下去写回当前项目。

    四个 setup 的守卫是同构的；这里跑 pi 的真实代码块，其余三个由
    tests/source-bench.py 的静态契约核对。"""
    with tempfile.TemporaryDirectory(prefix="agents-old-sync-") as d:
        tmp = pathlib.Path(d)
        src = tmp / "source"
        src.mkdir()
        # 旧缓存版本:支持 AGENTS_TAIL,但仍把块写进 $PWD/AGENTS.md
        (src / "skills-sync.sh").write_text(
            "#!/usr/bin/env bash\n"
            'printf "%s\\n" "${AGENTS_TAIL:-unset}" >> "$SYNC_LOG"\n'
            '[ "${AGENTS_TAIL:-0}" = 1 ] && printf "OLD-WRITE\\n" >> "$PWD/AGENTS.md"\n'
            "exit 0\n", encoding="utf-8")
        text = (ROOT / "pi-setup.sh").read_text(encoding="utf-8")
        block = text.split('# ---- 7. skills 本体 ----', 1)[1].split('# ---- 可选模块:', 1)[0]
        project = tmp / "project"
        project.mkdir()
        log = tmp / "sync.log"
        runner = tmp / "run.sh"
        runner.write_text(
            f"set -o pipefail\nexport SYNC_LOG={log}\nSOURCE_ROOT={src}\nPLAN_AGENTS_TAIL=1\nSKILL_GROUPS=(base)\n"
            f"PLAN_SKILLS_EXTERNAL=0\nASSUME_YES=0\nAGENT_DIR={tmp}/pi-agent\n"
            f"{block}\n[ \"${{tail_sync_failed:-0}}\" = 0 ] || exit 1\n", encoding="utf-8")
        subprocess.run(["bash", "-n", str(runner)], check=True)
        proc = subprocess.run(["bash", str(runner)], cwd=project, capture_output=True, text=True,
                              env=agents_env(tmp / "home"), stdin=subprocess.DEVNULL)
        assert proc.returncode == 1, ("旧缓存 skills-sync 未被拒绝", proc.stdout, proc.stderr)
        assert not (project / "AGENTS.md").exists(), "旧缓存 skills-sync 仍被允许写回当前项目"
        assert log.read_text().strip() == "0", "AGENTS_TAIL 仍以 1 传给旧写回逻辑"
        assert "ERROR" in proc.stdout + proc.stderr, proc.stdout + proc.stderr
    print("AGENTS.tail：旧缓存源码树被拒绝，AGENTS_TAIL 不传给旧的项目写回逻辑")


def git_fixture(repo, env, *args):
    subprocess.run(["git", "-C", str(repo), *args], env=env, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def check_agents_tail_migration():
    with tempfile.TemporaryDirectory(prefix="agents-migrate-") as d:
        tmp = pathlib.Path(d)
        src = tmp / "repo"
        (src / "scripts").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/migrate-agents-tail.py", src / "scripts/migrate-agents-tail.py")
        git_env = agents_env(tmp / "git-home", GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
                             GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
        git_fixture(src, git_env, "init", "-q")
        old_block = "<!-- memory-system:start -->\nOLD-RELEASE\n<!-- memory-system:end -->"
        (src / "AGENTS.tail.md").write_text(old_block + "\n", encoding="utf-8")
        git_fixture(src, git_env, "add", "-A")
        git_fixture(src, git_env, "commit", "-qm", "old")
        (src / "AGENTS.tail.md").write_text((ROOT / "AGENTS.tail.md").read_text(encoding="utf-8"), encoding="utf-8")
        git_fixture(src, git_env, "add", "-A")
        git_fixture(src, git_env, "commit", "-qm", "current")

        own = tmp / "own"
        own.mkdir()
        (own / "AGENTS.md").write_text("PROJECT-RULES\n\n" + old_block + "\n", encoding="utf-8")
        shell = tmp / "only"
        shell.mkdir()
        (shell / "AGENTS.md").write_text(old_block + "\n", encoding="utf-8")
        custom = tmp / "custom"
        custom.mkdir()
        (custom / "AGENTS.md").write_text("MINE\n\n" + old_block.replace("OLD-RELEASE", "EDITED") + "\n",
                                          encoding="utf-8")
        before = {p: (p / "AGENTS.md").read_bytes() for p in (own, shell, custom)}

        def migrate(home, *args):
            return subprocess.run(["python3", str(src / "scripts/migrate-agents-tail.py"), *map(str, args)],
                                  env=agents_env(home), capture_output=True, text=True,
                                  stdin=subprocess.DEVNULL)

        # 默认只预览:文件不动、不产生备份
        result = migrate(tmp / "preview", own, shell)
        assert result.returncode == 0, result.stdout + result.stderr
        assert {p: (p / "AGENTS.md").read_bytes() for p in (own, shell)} == {p: before[p] for p in (own, shell)}
        assert not list(own.glob("*.bak-*")) and not list(shell.glob("*.bak-*"))

        # 没有已识别宿主时 --apply 不得先删项目块
        refused = migrate(tmp / "no-host", own, shell, "--apply")
        assert refused.returncode != 0 and "未检测到宿主配置目录" in refused.stdout
        assert {p: (p / "AGENTS.md").read_bytes() for p in (own, shell)} == {p: before[p] for p in (own, shell)}

        # 有宿主时先保障用户级规则存在,再清掉与发行历史完全匹配的块并留备份;
        # 用户级文件缺失时项目块必须原地保留。
        deploy_home = tmp / "deploy"
        (deploy_home / ".pi/agent").mkdir(parents=True)
        applied = migrate(deploy_home, own, shell, custom, "--apply")
        deployed = deploy_home / ".pi/agent/AGENTS.md"
        assert applied.returncode != 0, "定制块应失败而不是静默跳过"
        assert not deployed.exists(), "用户级规则未部署就删了项目块"
        assert (own / "AGENTS.md").read_bytes() == before[own]
        assert (shell / "AGENTS.md").read_bytes() == before[shell]
        assert (custom / "AGENTS.md").read_bytes() == before[custom]

        # 用户级规则已就位后,精确匹配的块被清掉并留备份,定制块原样保留
        synced = migrate(deploy_home, "--sync-global")
        assert synced.returncode == 0, synced.stdout + synced.stderr
        assert deployed.read_text().count("<!-- memory-system:start -->") == 1
        applied = migrate(deploy_home, own, shell, custom, "--apply")
        assert applied.returncode != 0 and "定制" in applied.stderr
        assert (own / "AGENTS.md").read_text() == "PROJECT-RULES\n\n\n"
        assert not (shell / "AGENTS.md").exists(), "只剩受管块的项目文件应移除"
        assert (custom / "AGENTS.md").read_bytes() == before[custom]
        assert any("PROJECT-RULES" in p.read_text(encoding="utf-8") for p in own.glob("AGENTS.md.bak-*"))
        assert any("OLD-RELEASE" in p.read_text(encoding="utf-8") for p in shell.glob("AGENTS.md.bak-*"))
    print("AGENTS.tail 迁移：默认预览、无宿主拒绝清除、精确匹配才清理并备份，定制块保留")


def check_opencode_source_assets():
    oc = (ROOT / "opencode-setup.sh").read_text(encoding="utf-8")
    assert "$SOURCE_ROOT/migrate-web-mcp.py" in oc, "web MCP 迁移未从本地源码树取脚本"
    assert "$SELF_RAW/migrate-web-mcp.py" not in oc, "web MCP 迁移仍走 raw 下载"
    plan, _, _ = function(ROOT / "opencode-setup.sh", "collect_setup_plan")
    assert plan.count("acquire_source") >= 2, "精简模式(--plugins-only)未解析源码树"
    run = (ROOT / "modules/run.sh").read_text(encoding="utf-8")
    assert "archive/refs/heads" not in run and "m.tgz" not in run, "modules/run.sh 仍回退下载 tarball"
    print("OpenCode 源码资产：迁移脚本与模块统一来自 SOURCE_ROOT，无 raw/tarball 旁路")


def check_modules_local_only():
    with tempfile.TemporaryDirectory(prefix="setup-modules-local-") as d:
        tmp = pathlib.Path(d)
        modules = tmp / "modules"
        modules.mkdir()
        (modules / "run.sh").write_text((ROOT / "modules/run.sh").read_text(encoding="utf-8"))
        bin_dir = tmp / "bin"
        bin_dir.mkdir()
        log = tmp / "curl-called"
        curl = bin_dir / "curl"
        curl.write_text(f"#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> {log}\nexit 1\n")
        curl.chmod(0o755)
        env = os.environ.copy() | {"PATH": f"{bin_dir}:{os.environ['PATH']}"}
        empty = subprocess.run(["bash", str(modules / "run.sh"), "--host", "pi", "--list"],
                               env=env, capture_output=True, text=True)
        assert empty.returncode == 0, empty.stderr + empty.stdout
        assert not log.exists(), "没有模块目录时仍尝试下载 tarball"
        log.unlink(missing_ok=True)
        alpha = modules / "alpha"
        alpha.mkdir()
        (alpha / "setup.sh").write_text(
            "#!/usr/bin/env bash\n# module: alpha\n# desc: test\n# default: Y\n# hosts: any\nexit 0\n")
        ran = subprocess.run(["bash", str(modules / "run.sh"), "--host", "pi", "--selected", "alpha"],
                            env=env, capture_output=True, text=True)
        assert ran.returncode == 0, ran.stderr + ran.stdout
        assert not log.exists(), "本地模块执行仍尝试下载"
    print("模块分发：仅本地源码树取模块，缺模块不下载")


def check_setup_preferences():
    shared = {}
    for fn in ("preference_get", "preference_put", "preferences_init", "ask", "preferences_filter_modules", "preferences_lock", "preferences_commit_locked", "preferences_commit"):
        bodies = [function(ROOT / name, fn)[0] for name in SETUPS]
        assert len(set(bodies)) == 1, f"四宿主偏好函数漂移: {fn}"
        shared[fn] = bodies[0]
    write_keys = {"pi-setup.sh": "PI_WRITE_CFG", "opencode-setup.sh": "OC_WRITE_CFG",
                  "codex-setup.sh": "CODEX_WRITE_CFG", "dsh-setup.sh": ""}
    constants = []
    risky_constants = []
    for name in SETUPS:
        text = (ROOT / name).read_text(encoding="utf-8")
        match = re.search(r'PREF_KNOWN_KEYS="(.*?)"\nPREF_RISKY_KEYS=', text, re.S)
        assert match, f"{name}: 缺偏好键白名单"
        allowed = frozenset(match.group(1).replace("\\\n", " ").split())
        used = set(re.findall(r'\bask\s+[^\n;]*?\s+(?:Y|N|"\$def")\s+([A-Z][A-Z0-9_]+)', text))
        assert used <= allowed, f"{name}: 未登记偏好键 {sorted(used - allowed)}"
        constants.append((allowed, len(used)))
        risky = re.search(r'^PREF_RISKY_KEYS="([^"]+)"', text, re.M)
        assert risky, f"{name}: 缺高风险偏好键集合"
        risky_constants.append(frozenset(risky.group(1).split()))
    assert len({item[0] for item in constants}) == 1, "四宿主偏好键白名单漂移"
    assert len(set(risky_constants)) == 1 and "OC_UPGRADE" in risky_constants[0], "高风险偏好键集合漂移"
    assert all(count >= 7 for _, count in constants), f"偏好键覆盖异常: {constants}"
    oc = (ROOT / "opencode-setup.sh").read_text(encoding="utf-8")
    collect_at = oc.rindex("\ncollect_setup_plan\n")
    proxy_at = oc.index('"$PLAN_PROXY" = 1', collect_at)
    commit_at = oc.index("\npreferences_commit\n", collect_at)
    assert collect_at < proxy_at < commit_at, "OpenCode 取消检查先于偏好保存的边界被破坏"
    for name in SETUPS:
        text = (ROOT / name).read_text(encoding="utf-8")
        assert 'mod_env=("PATH=$PATH")' in text or 'sel_env=("PATH=$PATH")' in text, f"{name}: 空 env 数组未消除"
    module_keys = {"pi-setup.sh": "PI_MODULES", "opencode-setup.sh": "OC_MODULES",
                   "codex-setup.sh": "CODEX_MODULES", "dsh-setup.sh": "DSH_MODULES"}
    for name in SETUPS:
        path = ROOT / name
        module_key = module_keys[name]
        other_module_key = "OC_MODULES" if module_key == "PI_MODULES" else "PI_MODULES"
        source = path.read_text(encoding="utf-8")
        assert f"preference_get {module_key}" in source and f"preference_put {module_key}" in source
        assert f"preference_get {module_key}_KNOWN" in source and f"preference_put {module_key}_KNOWN" in source
        with tempfile.TemporaryDirectory(prefix="setup-preferences-") as d:
            tmp = pathlib.Path(d)
            pref = tmp / "config" / "agent-skills" / "preferences.conf"
            parts = [function(path, "have_tty")[0]] if name == "dsh-setup.sh" else []
            constants_block = re.search(r"(?ms)^PREF_FILE=.*?^PREF_RISKY_KEYS=[^\n]*$", source).group(0)
            parts.append(constants_block)
            parts.extend([function(path, "ask_builtin")[0], *shared.values()])
            original = function(path, "ask_builtin")[0].replace("ask_builtin()", "ask_builtin_original()", 1)
            parts.append(original)
            write_key = write_keys[name]
            driver = f'''
set -e
export AGENT_SKILLS_PREFERENCES={shlex.quote(str(pref))}
export SOURCE_ROOT={shlex.quote(str(ROOT))}
HOME={shlex.quote(str(tmp))}
ASSUME_YES=""; YES=0; CHOOSE=0; CHECK_ONLY=0; PLUGINS_ONLY=0
chmod 755 .
preferences_init
ask 'research' Y SHARED_RESEARCH
! ask 'ppt' N SHARED_PPT
preference_put {module_key} 'strictdoc,codegraph'
preference_put {module_key}_KNOWN 'strictdoc,codegraph'
'''
            if write_key:
                driver += f"ask 'write config' Y {write_key}\n"
            driver += f'''
preferences_commit
grep -q '^SHARED_RESEARCH=1$' "$AGENT_SKILLS_PREFERENCES"
grep -q '^SHARED_PPT=0$' "$AGENT_SKILLS_PREFERENCES"
[ "$(stat -c %a "$AGENT_SKILLS_PREFERENCES")" = 600 ]
[ "$(stat -c %a .)" = 755 ]
[ "$(stat -c %a "$(dirname "$AGENT_SKILLS_PREFERENCES")")" = 700 ]
before=$(sha256sum "$AGENT_SKILLS_PREFERENCES")
ask_builtin() {{ return 1; }}
preferences_init
[ "$PREF_REUSE" = 0 ]
ask_builtin() {{ ask_builtin_original "$@"; }}
: > prompts
ask_builtin() {{ printf '%s\n' "$1" >> prompts; ask_builtin_original "$@"; }}
ASSUME_YES=""; YES=0
preferences_init > summary-accepted
[ "$PREF_REUSE" = 1 ]
[ "$(wc -l < prompts)" = 1 ]
ask 'research' N SHARED_RESEARCH
! ask 'ppt' Y SHARED_PPT
'''
            if write_key:
                driver += f"ask 'write config' N {write_key}\n"
            driver += f'''
[ "$(wc -l < prompts)" = 1 ]
preferences_commit
[ "$(sha256sum "$AGENT_SKILLS_PREFERENCES")" = "$before" ]
ASSUME_YES=1; YES=1
preferences_init
ask 'research' N SHARED_RESEARCH
! ask 'ppt' Y SHARED_PPT
preferences_commit
[ "$(sha256sum "$AGENT_SKILLS_PREFERENCES")" = "$before" ]
CHOOSE=1
preferences_init
[ -z "$ASSUME_YES" ] && [ "$YES" = 0 ]
ask 'ppt' Y SHARED_PPT
preferences_commit
grep -q '^SHARED_PPT=1$' "$AGENT_SKILLS_PREFERENCES"
CHOOSE=0
printf '%s\n' 'SHARED_RESEARCH=1;echo SECRET_SENTINEL' 'UNKNOWN_KEY=1' 'BAD LINE' >> "$AGENT_SKILLS_PREFERENCES"
cp "$AGENT_SKILLS_PREFERENCES" before-check
CHECK_ONLY=1
preferences_init > check-output 2>warnings
[ ! -s check-output ]
cmp -s "$AGENT_SKILLS_PREFERENCES" before-check
if grep -q 'SECRET_SENTINEL' warnings; then echo 'FAIL: 非法行被回显' >&2; exit 1; fi
[ ! -e SECRET_SENTINEL ]
grep -q '忽略安装偏好' warnings
CHECK_ONLY=0
'''
            if write_key:
                driver += f'''
sed -i 's/^{write_key}=1$/{write_key}=0/' "$AGENT_SKILLS_PREFERENCES"
cp "$AGENT_SKILLS_PREFERENCES" before-no-write
ASSUME_YES=1; YES=1
preferences_init
! ask 'write config' Y {write_key}
preference_put SHARED_RESEARCH 0
preferences_commit
cmp -s "$AGENT_SKILLS_PREFERENCES" before-no-write
'''
            else:
                driver += '''
cp "$AGENT_SKILLS_PREFERENCES" before-read-only
PLUGINS_ONLY=1
preferences_init
preference_put SHARED_RESEARCH 0
preferences_commit
cmp -s "$AGENT_SKILLS_PREFERENCES" before-read-only
'''
            driver += f'''
printf 'SHARED_RESEARCH=1\\r\\nSHARED_PPT=0\\r\\n' > "$AGENT_SKILLS_PREFERENCES"
CHOOSE=0; CHECK_ONLY=0; PLUGINS_ONLY=0; ASSUME_YES=1; YES=1
preferences_init
ask 'research' N SHARED_RESEARCH
! ask 'ppt' Y SHARED_PPT
ask_builtin() {{ printf '%s\n' "$1" >> prompts; [ "$2" = Y ]; }}
: > prompts
ask 'ordinary-missing' Y PI_UPDATE
[ ! -s prompts ]
ask 'risky-missing' Y OC_UPGRADE
grep -q 'risky-missing' prompts
ask_builtin() {{ ask_builtin_original "$@"; }}
preferences_init
printf 'OC_UPGRADE=1\n' >> "$AGENT_SKILLS_PREFERENCES"
preference_put SHARED_RESEARCH 0
preferences_commit
grep -q '^OC_UPGRADE=1$' "$AGENT_SKILLS_PREFERENCES"
grep -q '^SHARED_RESEARCH=1' "$AGENT_SKILLS_PREFERENCES"
printf '%s\n' 'SHARED_RESEARCH=1' '{module_key}=secretmodulevalue,codegraph' 'PI_UNDECLARED_MODULES=codegraph' > "$AGENT_SKILLS_PREFERENCES"
ASSUME_YES=""; YES=0; CHOOSE=0; CHECK_ONLY=0; PLUGINS_ONLY=0
preferences_init > summary 2>warnings
if grep -q 'secretmodulevalue' summary; then echo 'FAIL: 模块原值进入摘要' >&2; exit 1; fi
if grep -q 'PI_UNDECLARED_MODULES' summary; then echo 'FAIL: 未声明键进入摘要' >&2; exit 1; fi
grep -q '<待当前源码校验>' summary
cp "$AGENT_SKILLS_PREFERENCES" before-invalid
valid_source_root="$SOURCE_ROOT"
SOURCE_ROOT=/nonexistent
preferences_commit
cmp -s "$AGENT_SKILLS_PREFERENCES" before-invalid
SOURCE_ROOT="$valid_source_root"
preferences_commit
grep -q '^{module_key}=codegraph$' "$AGENT_SKILLS_PREFERENCES"
if grep -q 'secretmodulevalue' "$AGENT_SKILLS_PREFERENCES"; then echo 'FAIL: 模块原值被写回' >&2; exit 1; fi
if grep -q 'PI_UNDECLARED_MODULES' "$AGENT_SKILLS_PREFERENCES"; then echo 'FAIL: 未声明键被写回' >&2; exit 1; fi
grep -q '^SHARED_RESEARCH=1$' "$AGENT_SKILLS_PREFERENCES"
rm -f "$AGENT_SKILLS_PREFERENCES"
mkdir "$AGENT_SKILLS_PREFERENCES"
preferences_init
preference_put SHARED_RESEARCH 1
preferences_commit > directory-target 2>&1
if grep -q '已保存' directory-target; then echo 'FAIL: 目录目标伪报保存' >&2; exit 1; fi
[ -d "$AGENT_SKILLS_PREFERENCES" ]
rmdir "$AGENT_SKILLS_PREFERENCES"
printf 'SHARED_RESEARCH=1\n' > link-target
ln -s "$PWD/link-target" "$AGENT_SKILLS_PREFERENCES"
preferences_init > symlink-target 2>&1
if grep -q 'SHARED_RESEARCH=1' symlink-target; then echo 'FAIL: 读取了符号链接目标' >&2; exit 1; fi
preference_put SHARED_PPT 1
preferences_commit >> symlink-target 2>&1
[ -L "$AGENT_SKILLS_PREFERENCES" ]
[ "$(cat link-target)" = 'SHARED_RESEARCH=1' ]
if grep -q '已保存' symlink-target; then echo 'FAIL: 符号链接被替换' >&2; exit 1; fi
rm "$AGENT_SKILLS_PREFERENCES"
ln -s missing-target "$AGENT_SKILLS_PREFERENCES"
preferences_init > broken-link 2>&1
preferences_commit >> broken-link 2>&1
[ -L "$AGENT_SKILLS_PREFERENCES" ]
if grep -q '已保存' broken-link; then echo 'FAIL: 断链被替换' >&2; exit 1; fi
rm "$AGENT_SKILLS_PREFERENCES"
printf 'SHARED_RESEARCH=1\n' > "$AGENT_SKILLS_PREFERENCES"
preferences_init
preference_put SHARED_PPT 1
mkdir "$AGENT_SKILLS_PREFERENCES.lock"
printf '%s\n' "$$" > "$AGENT_SKILLS_PREFERENCES.lock/pid"
cp "$AGENT_SKILLS_PREFERENCES" before-active-lock
preferences_commit > active-lock 2>&1
cmp -s "$AGENT_SKILLS_PREFERENCES" before-active-lock
if grep -q '已保存' active-lock; then echo 'FAIL: 活动锁被忽略' >&2; exit 1; fi
rm "$AGENT_SKILLS_PREFERENCES.lock/pid"
rmdir "$AGENT_SKILLS_PREFERENCES.lock"
mkdir "$AGENT_SKILLS_PREFERENCES.lock"
cp "$AGENT_SKILLS_PREFERENCES" before-orphan-lock
preferences_commit > orphan-lock 2>&1
cmp -s "$AGENT_SKILLS_PREFERENCES" before-orphan-lock
grep -q '人工删除' orphan-lock
rmdir "$AGENT_SKILLS_PREFERENCES.lock"
preferences_commit > recovered-lock
grep -q '已保存' recovered-lock
# 某些 mkdir 实现遇到并发 EEXIST 仍返回成功，锁不能依赖其退出码。
mkdir() {{
  if [ "${{1:-}}" = "$AGENT_SKILLS_PREFERENCES.lock" ]; then
    command mkdir "$@" 2>/dev/null || :
  else
    command mkdir "$@"
  fi
}}
preferences_lock
[ "$(stat -c %a "$AGENT_SKILLS_PREFERENCES.lock")" = 600 ]
if preferences_lock; then echo 'FAIL: 锁被重复获取' >&2; exit 1; fi
rm "$AGENT_SKILLS_PREFERENCES.lock"
unset -f mkdir
ln -s "$PWD/link-target" "$AGENT_SKILLS_PREFERENCES.lock"
if preferences_lock 2>/dev/null; then echo 'FAIL: 符号链接锁被获取' >&2; exit 1; fi
[ "$(cat link-target)" = 'SHARED_RESEARCH=1' ]
rm "$AGENT_SKILLS_PREFERENCES.lock"
ln -s missing-lock "$AGENT_SKILLS_PREFERENCES.lock"
if preferences_lock 2>/dev/null; then echo 'FAIL: 断链锁被获取' >&2; exit 1; fi
[ ! -e missing-lock ]
rm "$AGENT_SKILLS_PREFERENCES.lock"
ln -s /dev/null "$AGENT_SKILLS_PREFERENCES.lock"
if preferences_lock 2>/dev/null; then echo 'FAIL: 设备符号链接锁被获取' >&2; exit 1; fi
rm "$AGENT_SKILLS_PREFERENCES.lock"
mkfifo "$AGENT_SKILLS_PREFERENCES.lock"
cat "$AGENT_SKILLS_PREFERENCES.lock" > fifo-data & fifo_reader=$!
if preferences_lock 2>/dev/null; then
  wait "$fifo_reader" || true
  echo 'FAIL: FIFO 锁被获取' >&2; exit 1
fi
kill "$fifo_reader" 2>/dev/null || true
wait "$fifo_reader" 2>/dev/null || true
[ -p "$AGENT_SKILLS_PREFERENCES.lock" ]
rm "$AGENT_SKILLS_PREFERENCES.lock"
link() {{ return 0; }}
if preferences_lock 2>/dev/null; then echo 'FAIL: 未创建锁却报成功' >&2; exit 1; fi
unset -f link
link() {{ return 1; }}
cp "$AGENT_SKILLS_PREFERENCES" before-no-link
preferences_init
preference_put SHARED_PPT 0
preferences_commit > no-link 2>&1
cmp -s "$AGENT_SKILLS_PREFERENCES" before-no-link
grep -q '文件系统支持硬链接' no-link
unset -f link
printf 'SHARED_RESEARCH=1\n' > "$AGENT_SKILLS_PREFERENCES"
rm -f ready-a ready-b race-a race-b
(
  ASSUME_YES=1; YES=1; preferences_init
  touch ready-a
  while [ ! -f ready-b ]; do sleep 0.01; done
  preference_put '{module_key}' codegraph
  preferences_commit > race-a 2>&1
) & race_a=$!
(
  ASSUME_YES=1; YES=1; preferences_init
  touch ready-b
  while [ ! -f ready-a ]; do sleep 0.01; done
  preference_put {other_module_key} strictdoc
  preferences_commit > race-b 2>&1
) & race_b=$!
wait "$race_a"; wait "$race_b"
[ "$(grep -l '已保存' race-a race-b | wc -l)" = 1 ]
if grep -q '^{module_key}=codegraph$' "$AGENT_SKILLS_PREFERENCES"; then
  if grep -q '^{other_module_key}=strictdoc$' "$AGENT_SKILLS_PREFERENCES"; then echo 'FAIL: 并发写入覆盖先写者' >&2; exit 1; fi
else
  grep -q '^{other_module_key}=strictdoc$' "$AGENT_SKILLS_PREFERENCES"
fi
[ ! -e "$AGENT_SKILLS_PREFERENCES.lock" ]
'''
            driver += "! find . -name '.preferences.*' -print -quit | grep -q .\n"
            script = tmp / "check.sh"
            script.write_text("\n".join(parts) + driver, encoding="utf-8")
            proc = subprocess.run(["bash", str(script)], cwd=tmp, env=os.environ.copy(),
                                  capture_output=True, text=True)
            assert proc.returncode == 0, f"{name}: 偏好回归失败\n{proc.stdout}\n{proc.stderr}"
    with tempfile.TemporaryDirectory(prefix="setup-module-preferences-") as d:
        listed = subprocess.run(["bash", str(ROOT / "modules/run.sh"), "--host", "pi", "--list"],
                                capture_output=True, text=True, check=True).stdout
        known = ",".join(line.split()[0] for line in listed.splitlines() if line.strip())
        dsh_listed = subprocess.run(["bash", str(ROOT / "modules/run.sh"), "--host", "dsh", "--list"],
                                    capture_output=True, text=True, check=True).stdout
        assert "codegraph" not in {line.split()[0] for line in dsh_listed.splitlines() if line.strip()}
        all_listed = subprocess.run(["bash", str(ROOT / "modules/run.sh"), "--list"],
                                    capture_output=True, text=True, check=True).stdout
        assert "codegraph" in {line.split()[0] for line in all_listed.splitlines() if line.strip()}
        env = os.environ.copy() | {"AGENT_SKILLS_MODULE_SELECTION": "strictdoc,codegraph,not-a-module",
                                  "AGENT_SKILLS_MODULE_KNOWN": known}
        proc = subprocess.run(["bash", str(ROOT / "modules/run.sh"), "--host", "pi", "--select", "--yes"],
                              cwd=d, env=env, capture_output=True, text=True)
        assert proc.returncode == 0, proc.stderr
        assert proc.stdout.splitlines() == ["codegraph", "strictdoc"], proc.stdout
        env["AGENT_SKILLS_MODULE_SELECTION"] = ""
        empty = subprocess.run(["bash", str(ROOT / "modules/run.sh"), "--host", "pi", "--select", "--yes"],
                               cwd=d, env=env, capture_output=True, text=True)
        assert empty.returncode == 0 and empty.stdout == "", empty.stdout + empty.stderr
        modules = pathlib.Path(d) / "modules"
        modules.mkdir()
        (modules / "run.sh").write_text((ROOT / "modules/run.sh").read_text(encoding="utf-8"))
        for name, default in (("alpha", "Y"), ("beta", "N")):
            (modules / name).mkdir()
            (modules / name / "setup.sh").write_text(
                f"#!/usr/bin/env bash\n# module: {name}\n# desc: test\n# default: {default}\n# hosts: any\nexit 0\n")
        fresh_env = os.environ.copy() | {"AGENT_SKILLS_MODULE_SELECTION": "", "AGENT_SKILLS_MODULE_KNOWN": ""}
        fresh = subprocess.run(["bash", str(modules / "run.sh"), "--host", "pi", "--select", "--yes"],
                               env=fresh_env, capture_output=True, text=True)
        assert fresh.stdout.splitlines() == ["alpha"], fresh.stdout + fresh.stderr
        fresh_env["AGENT_SKILLS_MODULE_KNOWN"] = "alpha,beta"
        old = subprocess.run(["bash", str(modules / "run.sh"), "--host", "pi", "--select", "--yes"],
                             env=fresh_env, capture_output=True, text=True)
        assert old.stdout == "", old.stdout + old.stderr
        (modules / "gamma").mkdir()
        (modules / "gamma" / "setup.sh").write_text(
            "#!/usr/bin/env bash\n# module: gamma\n# desc: new\n# default: Y\n# hosts: any\nexit 0\n")
        added = subprocess.run(["bash", str(modules / "run.sh"), "--host", "pi", "--select", "--yes"],
                               env=fresh_env, capture_output=True, text=True)
        assert added.stdout.splitlines() == ["gamma"], added.stdout + added.stderr
    print("安装偏好：保存/复用/choose/-y、模块新增与旧选择、CRLF、只读及非法输入均通过")


def check_unified_update():
    # 真入口、共同分发与偏好文件；只有会升级客户端／访问网络的执行器替换为记录器。
    with tempfile.TemporaryDirectory(prefix="unified-setup-") as td:
        tmp = pathlib.Path(td)
        src, home = tmp / "source tree", tmp / "home"
        src.mkdir(); home.mkdir()
        for name in ("dsh-setup.sh", "skills-sync.sh", "scripts/update-hosts.sh", "scripts/migrate-agents-tail.py",
                     "AGENTS.tail.md", "templates"):
            dest = src / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.symlink_to(ROOT / name)
        for group in ("base", "research"):
            skill = src / "skills" / group / f"demo-{group}"
            skill.mkdir(parents=True); (skill / "SKILL.md").write_text(group)
        for host in ("opencode", "pi"):
            (src / f"{host}-setup.sh").write_text(
                f'echo {host}:"$AGENT_SKILLS_HOST_ONLY:$AGENT_SKILLS_MEM_RESTART:$*" >> "$LOG"\n'
                f'rm -f "$ALIVE_FLAG"\n'
                f'test "${{FAIL_HOST:-}}" != "{host}" || exit 23\n'
                f'mod="$SOURCE_ROOT/modules/run.sh"; selected=$(bash "$mod" --host {host} --select --yes)\n'
                f'bash "$mod" --host {host} --selected "$selected"\n')
        # 统一入口自己收口 claude-mem worker；桩掉 curl/npx，既不碰本机 worker 也能断言只重启一次。
        bin_dir = tmp / "bin"; bin_dir.mkdir()
        # 健康检查桩：flag 文件存在即"worker 在跑"。宿主桩模拟官方安装器把它停掉，
        # 从而观察统一入口是否补做且只补做一次恢复。
        (bin_dir / "curl").write_text('#!/bin/sh\n[ -f "$ALIVE_FLAG" ]\n')
        # restart 桩把 flag 放回，模拟"重启成功、健康检查通过"；其它条目照旧记录调用。
        (bin_dir / "npx").write_text(
            '#!/bin/sh\necho "npx $*" >> "$LOG"\n'
            '[ "$*" != "restart" ] || : > "$ALIVE_FLAG"\n')
        for stub in bin_dir.iterdir():
            stub.chmod(0o755)
        (src / "skills-external.sh").write_text('echo shared >> "$LOG"\n')
        (src / "modules").mkdir(); shutil.copy(ROOT / "modules/run.sh", src / "modules/run.sh")
        mod = src / "modules/example"; mod.mkdir()
        (mod / "setup.sh").write_text('# module: example\n# hosts: any\n# default: N\necho module >> "$LOG"\n')
        unused = src / 'modules/unused'; unused.mkdir()
        (unused / 'setup.sh').write_text('# module: unused\n# hosts: any\n# default: Y\nexit 19\n')
        log = tmp / "calls"; pref = home / "preferences.conf"
        pref.write_text('SHARED_RESEARCH=1\nDSH_MODULES=example\nDSH_MODULES_KNOWN=example,unused\n')
        env = dict(PATH=f"{bin_dir}:{os.environ['PATH']}", HOME=str(home), AGENT_SKILLS_SOURCE=str(src),
                   AGENT_SKILLS_PREFERENCES=str(pref), SKILLS_EXTERNAL='skip', LOG=str(log))
        def run(*args, **extra):
            return subprocess.run(['bash', ROOT / 'setup.sh', *args], cwd=tmp, env=dict(env, **extra),
                                  stdin=subprocess.DEVNULL, start_new_session=True, capture_output=True, text=True, timeout=40)
        assert run('-y').returncode == 2 and not log.exists(), '首次无明确宿主时不得猜测'
        result = run('--hosts', 'opencode,pi,antigravity', '-y')
        assert result.returncode == 0, result.stdout + result.stderr
        expected = ['shared', 'opencode:1:0:-y', 'pi:1:0:-y', 'module']
        assert log.read_text().splitlines() == expected
        assert (home / '.gemini/AGENTS.md').is_file() and not (home / '.claude/CLAUDE.md').exists()
        installed = home / '.agents/skills/demo-research/SKILL.md'
        assert installed.read_text() == 'research'
        stamp = installed.stat().st_mtime_ns; saved = pref.stat().st_mtime_ns
        new_skill = pathlib.Path('skills/base/problem-framing')
        shutil.copytree(ROOT / new_skill, src / new_skill)
        assert run('-y').returncode == 0 and log.read_text().splitlines() == expected * 2
        assert (home / '.agents/skills/problem-framing/SKILL.md').read_bytes() == (ROOT / new_skill / 'SKILL.md').read_bytes()
        assert installed.stat().st_mtime_ns == stamp and pref.stat().st_mtime_ns == saved
        assert run('--hosts', 'bogus', '-y').returncode != 0 and pref.stat().st_mtime_ns == saved
        before = (home / '.gemini/AGENTS.md').stat().st_mtime_ns
        pi_config = home / '.pi/agent/settings.json'
        pi_config.parent.mkdir(parents=True, exist_ok=True)
        pi_config.write_text('{"custom":"preserve"}', encoding='utf-8')
        pi_stamp = pi_config.stat().st_mtime_ns
        assert run('--hosts', 'opencode', '-y').returncode == 0
        assert log.read_text().splitlines()[8:] == ['shared', 'opencode:1:0:-y', 'module']
        assert (home / '.gemini/AGENTS.md').stat().st_mtime_ns == before
        assert pi_config.read_text(encoding='utf-8') == '{"custom":"preserve"}' and pi_config.stat().st_mtime_ns == pi_stamp
        assert 'SHARED_HOSTS=opencode\n' in pref.read_text()
        link_stub = bin_dir / 'link'
        link_stub.write_text('#!/bin/sh\nexit 1\n'); link_stub.chmod(0o755)
        lines = pref.read_text().splitlines()
        variants = [('\r\n'.join(lines) + '\r\n').encode(),
                    ('# user comment\n' + '\n'.join(reversed([line for line in lines if '=' in line]))).encode()]
        for existing in variants:
            pref.write_bytes(existing)
            unchanged = run('-y')
            assert unchanged.returncode == 0, unchanged.stdout + unchanged.stderr
            assert pref.read_bytes() == existing, '格式不同但选择相同时不得改写'
        before_pref, before_log = pref.read_bytes(), log.read_bytes()
        failed = run('--hosts', 'none', '-y')
        assert failed.returncode != 0, '宿主名单未保存时不得报成功'
        assert pref.read_bytes() == before_pref and log.read_bytes() == before_log, '名单未保存时不得执行更新'
        assert '未保存' in failed.stderr
        link_stub.unlink()
        assert run('-y', FAIL_HOST='opencode').returncode == 23 and log.read_text().splitlines()[-1] == 'opencode:1:0:-y'
        # worker 本就没在跑时，绝不顺手启一个常驻进程
        assert not [line for line in log.read_text().splitlines() if line.startswith('npx ')]
        # 装前在跑时由统一入口收口一次，而不是每个宿主各自重启互相打断
        log.unlink()
        flag = tmp / "alive-flag"
        flag.touch()
        assert run("--hosts", "opencode,pi", "-y", ALIVE_FLAG=str(flag)).returncode == 0
        restarts = [line for line in log.read_text().splitlines() if line.startswith('npx ')]
        assert restarts == ['npx -y claude-mem@latest restart'], restarts
        # 宿主中途失败也必须把 worker 恢复回来（EXIT trap），而不是留下一个停掉的记忆后端
        log.unlink(); flag.touch()
        assert run("--hosts", "opencode,pi", "-y", ALIVE_FLAG=str(flag), FAIL_HOST="pi").returncode == 23
        restarts = [line for line in log.read_text().splitlines() if line.startswith('npx ')]
        assert restarts == ['npx -y claude-mem@latest restart'], restarts
    print('统一更新：选中宿主、旧偏好继承、公共项只执行一次、worker 只由入口收口、重跑与失败传播')


def check_mem_worker_restore():
    """安装器会停掉共享 worker；只在装前确实在跑时恢复，且统一入口只做一次。"""
    with tempfile.TemporaryDirectory(prefix="mem-worker-") as td:
        tmp = pathlib.Path(td); bin_dir = tmp / "bin"; bin_dir.mkdir()
        log = tmp / "npx.log"
        (bin_dir / "curl").write_text('#!/bin/sh\n[ "${ALIVE:-0}" = 1 ]\n')
        (bin_dir / "npx").write_text('#!/bin/sh\necho "npx $*" >> "$LOG"\n[ "${RESTART_OK:-1}" = 1 ]\n')
        for item in bin_dir.iterdir():
            item.chmod(0o755)
        settings = tmp / "settings.json"
        settings.write_text('{"CLAUDE_MEM_WORKER_HOST": "127.0.0.1", "CLAUDE_MEM_WORKER_PORT": "37991"}')
        bodies = [function(ROOT / name, fn)[0] for name in SETUPS
                  for fn in ("mem_worker_url", "mem_worker_alive", "mem_worker_restore")]
        assert len(set(bodies)) == 3, "四宿主 claude-mem worker 函数漂移"
        script = tmp / "run.sh"
        script.write_text("set -u\n" + "".join(bodies[i] for i in (0, 1, 2)) +
                          f'mem_worker_restore "{settings}" "${{WAS_ALIVE}}"\n')
        base = dict(PATH=f"{bin_dir}:{os.environ['PATH']}", LOG=str(log), HOME=str(tmp))

        def run(**extra):
            log.unlink(missing_ok=True)
            return subprocess.run(["bash", str(script)], env={**base, **{k: str(v) for k, v in extra.items()}},
                                  stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)

        got = run(ALIVE=1, WAS_ALIVE=1)
        assert got.returncode == 0, got.stdout + got.stderr
        assert log.read_text().splitlines() == ["npx -y claude-mem@latest restart"]
        assert "已重启" in got.stdout
        assert run(ALIVE=1, WAS_ALIVE=0).returncode == 0 and not log.exists(), "worker 原本没跑时不应启动它"
        assert run(ALIVE=1, WAS_ALIVE=1, AGENT_SKILLS_MEM_RESTART=0).returncode == 0 and not log.exists(), \
            "统一入口收口时各宿主不应各自重启"
        failed = run(ALIVE=0, WAS_ALIVE=1, RESTART_OK=0)
        assert failed.returncode != 0 and "手工执行" in failed.stderr, "重启失败必须报出可手工执行的补救命令"
    print('claude-mem worker：装前在跑才恢复、入口只收口一次、失败给出补救命令')


def main():
    check_no_late_questions()
    if os.name == "nt":
        print("SKIP: POSIX shell 行为夹具在 Windows 跳过；Windows 另跑 tests/pi-setup-windows-git-bash.py")
        return
    check_existing_credentials()
    check_dsh_existing_credentials()
    check_dsh_cold_node_url()
    check_dsh_python_versions()
    check_module_selection()
    check_codex_disabled_with_python_fallback()
    check_python_fallback()
    check_cold_windows_plan()
    check_write_refusal()
    check_pi_magic_guard()
    check_context_mode_conflicts()
    check_codex_codegraph_exact_name()
    check_external_skip_filter()
    check_opencode_compaction_plan()
    check_opencode_readonly_plans()
    check_opencode_source_assets()
    check_modules_local_only()
    check_agents_tail()
    check_multi_agent_auto_trigger()
    check_agents_tail_old_cache()
    check_agents_tail_migration()
    check_mem_search_setup()
    check_setup_preferences()
    check_unified_update()
    check_mem_worker_restore()
    print("PASS: setup 前置选择回归")


if __name__ == "__main__":
    main()
