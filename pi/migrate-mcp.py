#!/usr/bin/env python3
"""迁移本套件的 ~/.agents/mcp.json 到 Pi 原生 MCP；默认预览，--apply 备份后写入。"""
import argparse
import copy
import json
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


NATIVE_FIELDS = {
    "command", "args", "env", "cwd", "url", "headers", "oauth", "auth", "type",
    "timeout", "enabled", "exposure", "toolExposure", "description",
}


def load_config(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except (OSError, ValueError) as error:
        raise SystemExit(f"ERROR: {path} 无法读取（{error}）；未修改配置") from error
    if not isinstance(data, dict):
        raise SystemExit(f"ERROR: {path} 顶层必须是对象；未修改配置")
    return data


def native_value(value):
    if value.startswith("!!"):
        prefix, value = "$!", value[2:]
    elif value.startswith("!"):
        return value
    else:
        prefix = ""
    # 保留 ${NAME}，转换旧变量写法；其它 $ 在 adapter 中是字面值。
    pattern = r"\$\{(\w+)\}|\$env:(\w+)|\{env:(\w+)\}|\$"
    return prefix + re.sub(pattern, lambda m: "${" + next(g for g in m.groups() if g) + "}"
                           if any(m.groups()) else "$$", value)


def native_server(name, server):
    if not isinstance(server, dict) or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise SystemExit(f"ERROR: 服务器 {name} 定义或名称无效；未修改配置")
    server = dict(server)
    server.pop("toolPrefix", None)
    direct = server.pop("directTools", False)
    server.setdefault("exposure", "deferred")
    if isinstance(direct, bool) and direct:
        server["exposure"] = "direct"
    elif isinstance(direct, list):
        server["toolExposure"] = {**dict.fromkeys(direct, "direct"), **server.get("toolExposure", {})}
    if "disabled" in server:
        server["enabled"] = not server.pop("disabled")
    if "requestTimeoutMs" in server:
        server.setdefault("timeout", server.pop("requestTimeoutMs") / 1000)
    unsupported = server.keys() - NATIVE_FIELDS
    if unsupported:
        raise SystemExit(f"ERROR: {name} 有未转换的 adapter 字段 {', '.join(sorted(unsupported))}；未写入，请先手工迁移")
    if "auth" in server or "oauth" in server:
        raise SystemExit(f"ERROR: {name} 有 adapter 认证配置，须先按原生格式转换并重新登录；未修改配置")
    for field in ("command", "cwd", "url", "args"):
        values = server.get(field, [])
        for value in values if isinstance(values, list) else [values]:
            if isinstance(value, str) and ("$" in value or "{env:" in value):
                raise SystemExit(f"ERROR: {name}.{field} 有变量引用，原生不在该字段插值；未修改配置")
    for field in ("env", "headers"):
        if field in server:
            server[field] = {key: native_value(value) for key, value in server[field].items()}
    if server.get("type") == "sse":
        raise SystemExit(f"ERROR: {name} 使用 SSE，须先确认 streamable HTTP 地址；未修改配置")
    if not server.get("command") and not server.get("url"):
        raise SystemExit(f"ERROR: {name} 缺 command/url；未修改配置")
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="备份后应用；不传则只预览字段名，不显示凭据")
    args = parser.parse_args()
    pi = shutil.which("pi")
    if not pi:
        raise SystemExit("ERROR: 未找到 pi，请先安装 Pi 0.99.0 或更新版本")
    version = subprocess.check_output([pi, "--version"], text=True).strip()
    numbers = re.match(r"(\d+)\.(\d+)\.(\d+)", version)
    if not numbers or tuple(map(int, numbers.groups())) < (0, 99, 0):
        raise SystemExit(f"ERROR: Pi {version} 不支持原生 MCP，请升级后重跑；未修改配置")

    home = Path.home()
    agent = Path(os.environ.get("PI_CODING_AGENT_DIR", home / ".pi/agent")).expanduser()
    # 仅迁移本套件的共享来源；其它 adapter 来源需显式转换，不能静默漏掉服务器。
    for p in [home / ".config/mcp/mcp.json", home / ".agents/mcp/mcp.json",
              agent / "mcp-adapter.json", Path(".mcp.json"), Path(".pi/mcp-adapter.json")]:
        if load_config(p):
            raise SystemExit(f"ERROR: 发现额外 MCP 配置 {p}，请先手工转换到对应 Pi mcp.json；未修改配置")

    source = home / ".agents/mcp.json"
    shared = load_config(source)
    if any(v for k, v in shared.items() if k != "mcpServers"):
        raise SystemExit(f"ERROR: {source} 有 adapter 全局设置，需先手工转换；未修改配置")
    project = load_config(Path(".pi/settings.json"))
    if "pi-mcp-adapter" in json.dumps(project):
        raise SystemExit("ERROR: 项目 .pi/settings.json 仍登记 adapter，请先摘除该登记；未修改配置")
    paths = [agent / "mcp.json", agent / "settings.json"]
    old, before, data = {}, {}, {}
    for p in paths:
        if p.is_symlink():
            raise SystemExit(f"ERROR: {p} 是符号链接，未修改配置")
        old[p] = p.read_text(encoding="utf-8") if p.exists() else None
        before[p] = load_config(p)
        data[p] = copy.deepcopy(before[p])
    mcp, settings = (data[p] for p in paths)
    servers = mcp.setdefault("mcpServers", {})
    if not isinstance(shared.get("mcpServers", {}), dict) or not isinstance(servers, dict):
        raise SystemExit("ERROR: mcpServers 必须是对象；未修改配置")
    namespaces = {name.replace("-", "_") for name in servers}
    for name, server in shared.get("mcpServers", {}).items():
        if name not in servers:
            if name.replace("-", "_") in namespaces:
                raise SystemExit(f"ERROR: {name} 与原生服务器命名空间冲突；未修改配置")
            servers[name] = native_server(name, server)
            namespaces.add(name.replace("-", "_"))
            print(f"导入服务器: {name}（连接参数保留，工具暴露/变量语法转为原生）")
        else:
            print(f"保留原生服务器: {name}（不覆盖已有定义）")
    packages = settings.get("packages", [])
    settings["packages"] = [p for p in packages
                            if re.split(r"[@/]", (p if isinstance(p, str) else p["source"]).removeprefix("npm:"))[0] != "pi-mcp-adapter"]
    extensions = settings.get("extensions", [])
    settings["extensions"] = [p for p in extensions if p.lstrip("+!-") != "builtin:mcp"
                              and "pi-mcp-adapter" not in p] + ["+builtin:mcp"]
    tools = settings.get("defaultTools", [])
    settings["defaultTools"] = [t for t in tools if t.lstrip("+-") not in ("codemode", "tool_search")] + ["+codemode", "+tool_search"]

    changes = [(p, json.dumps(data[p], ensure_ascii=False, indent=2) + "\n") for p in paths
               if old[p] is None or before[p] != data[p]]
    for p, _ in changes:
        keys = [k for k, v in data[p].items() if before[p].get(k) != v]
        print(f"{'更新' if old[p] is not None else '新建'}: {p}；字段: {', '.join(keys)}")
    if not args.apply:
        print("仅预览；确认后加 --apply。旧共享配置、OAuth 文件和安装目录均不改动。")
        return
    stamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
    for p, text in changes:
        if (p.read_text(encoding="utf-8") if p.exists() else None) != old[p]:
            raise SystemExit(f"ERROR: {p} 在预览后被其它进程修改，停止写入")
        p.parent.mkdir(parents=True, exist_ok=True)
        if old[p] is not None:
            backup = p.with_name(p.name + ".bak-mcp-" + stamp)
            shutil.copy2(p, backup)
            backup.chmod(0o600)
            print(f"backup: {backup}")
        fd, tmp = tempfile.mkstemp(prefix=".mcp-migrate-", dir=p.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            os.replace(tmp, p)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    print("已写入" if changes else "unchanged: 已是原生 MCP 配置")
    print("运行 pi mcp list 检查连接；重开 Pi 后 /mcp 应显示原生管理界面。")


if __name__ == "__main__":
    main()
