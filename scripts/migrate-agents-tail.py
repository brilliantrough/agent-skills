#!/usr/bin/env python3
"""同步宿主原生指令与发现入口，或按显式项目路径迁移旧规则。"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
START = b'<!-- memory-system:start -->'
END = b'<!-- memory-system:end -->'


def span(data):
    if START not in data and END not in data:
        return None
    a, b = data.find(START), data.find(END)
    if data.count(START) != 1 or data.count(END) != 1 or b < a:
        raise ValueError('memory-system 标记残缺或重复，原样保留')
    return slice(a, b + len(END))


def normalized(data):
    return data.replace(b'\r\n', b'\n')


def canonical(data):
    location = span(data)
    if not location:
        raise ValueError('源文件缺少 memory-system 块')
    return normalized(data[location])


HOSTS = ('pi', 'opencode', 'dsh', 'codex', 'claude', 'antigravity')


def targets(only=None):
    env = os.environ
    home = Path(env.get('HOME') or Path.home())
    data = Path(env.get('XDG_DATA_HOME') or home / '.local/share')
    managed = data / 'agent-skills/dsh/home'
    roots = {
        'pi': env.get('PI_CODING_AGENT_DIR') or home / '.pi/agent',
        'opencode': env.get('OPENCODE_CONFIG_DIR') or Path(env.get('XDG_CONFIG_HOME') or home / '.config') / 'opencode',
        'codex': env.get('CODEX_HOME') or home / '.codex',
        'claude': env.get('CLAUDE_CONFIG_DIR') or home / '.claude',
        'dsh': env.get('DSH_HOME') or (managed if managed.is_dir() else home / '.dsh'),
    }
    for host, root in roots.items():
        if only and host != only:
            continue
        root = Path(root)
        if root.parts[:1] == ('~',):
            root = home.joinpath(*root.parts[1:])
        # 显式 --sync-host 即使目录还不存在也同步；自动探测只认已配置宿主
        if not only and host != env.get('AGENTS_TAIL_HOST') and not root.is_dir():
            continue
        if host == 'claude' and not only and env.get('AGENTS_TAIL_HOST') != host and root.is_dir() and {p.name for p in root.iterdir()} == {'skills'}:
            continue  # 统一入口预置的发现目录不代表已选择 Claude。
        name = 'CLAUDE.md' if host == 'claude' else 'AGENTS.md'
        if host == 'pi':
            name = next((n for n in ['AGENTS.override.md', name, 'AGENTS.MD', 'CLAUDE.md', 'CLAUDE.MD'] if (root / n).is_file()), name)
        yield host, root / name
    if only and only != 'antigravity':
        return
    gemini = home / '.gemini'
    if only or env.get('AGENTS_TAIL_HOST') == 'antigravity' or (gemini / 'AGENTS.md').is_file() or any(
            (gemini / name).is_dir() for name in ('antigravity', 'antigravity-cli')):
        yield 'antigravity', gemini / 'AGENTS.md'


def read_target(p):
    if p.is_symlink() or ROOT in p.resolve().parents:
        raise ValueError(f'保留符号链接或只读源码树：{p}')
    return p.read_bytes() if p.exists() else b''


def replace(p, data):
    p.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=p.parent, delete=False) as f:
        tmp = Path(f.name)
    try:
        tmp.write_bytes(data)
        if p.exists():
            tmp.chmod(stat.S_IMODE(p.stat().st_mode))
        os.replace(tmp, p)
    finally:
        if tmp.exists():
            tmp.unlink()


def global_block(p, block, write):
    old = read_target(p)
    loc = span(old)
    if loc and normalized(old[loc]) == block:
        return '已同步'
    if not write:
        raise ValueError(f'先同步用户级规则：{p}')
    nl = b'\r\n' if old.count(b'\r\n') * 2 > old.count(b'\n') else b'\n'
    new = block.replace(b'\n', nl)
    if loc:
        new = old[:loc.start] + new + old[loc.stop:]
    else:
        sep = b'' if not old or old.endswith(nl * 2) else nl if old.endswith(nl) else nl * 2
        new = old + sep + new + nl
    replace(p, new)
    return '已更新'


def antigravity_skills():
    # deprecated: 旧版在 ~/.gemini/config/skills.json 登记 ~/.agents/skills；
    # 现改由 skills-sync.sh 维护 ~/.gemini/config/skills/<名>（原生 Antigravity 与 T3 隔离目录共用），
    # 此处备份并清理无自定义过滤的旧受管条目，避免原生端重复扫描。
    home = Path(os.environ.get('HOME') or Path.home())
    p = home / '.gemini/config/skills.json'
    if not p.exists() and not p.is_symlink():
        return 0
    shared = (home / '.agents/skills').resolve()
    try:
        raw = read_target(p)
        config = json.loads(raw)
        if not isinstance(config, dict) or not isinstance(config.get('entries', []), list):
            raise ValueError('需要含 entries 数组的 JSON 对象')
        kept = []
        removed = False
        for entry in config.get('entries', []):
            if not isinstance(entry, dict) or not isinstance(entry.get('path'), str):
                raise ValueError('entries 中缺少有效的 path')
            path = p.parent / entry['path']
            matches = path.resolve() == shared
            if matches != (Path(os.path.abspath(path)).resolve() == shared):
                raise ValueError('链接目录中的相对路径有歧义，请将该清单条目的 path 改为绝对路径')
            if matches and set(entry.keys()) == {'path'}:
                removed = True
            else:
                kept.append(entry)
        if not removed:
            return 0  # 保留用户自定义条目及带 include_only / exclude 的过滤配置。
        backups = Path(os.environ.get('XDG_DATA_HOME') or home / '.local/share') / 'agent-skills/.backups'
        backups.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix='antigravity-skills.json.bak-', dir=backups, delete=False) as f:
            f.write(raw)
            backup = f.name
        if not kept and set(config.keys()) <= {'entries'}:
            p.unlink()
        else:
            config['entries'] = kept
            replace(p, (json.dumps(config, ensure_ascii=False, indent=2) + '\n').encode())
        print(f'Antigravity: 已清理旧 skills.json 中的重复共享目录（改用 ~/.gemini/config/skills），备份：{backup}')
        return 0
    except (OSError, ValueError) as e:
        print(f'WARN: {p}: {e}', file=sys.stderr)
        return 1


PLACEHOLDER_RE = re.compile(r'<[A-Za-z][A-Za-z0-9 _-]*>')
MANAGED_MCP_NAMES = ('web', 'codegraph', 'claude-mem')


def usable_str(value):
    return isinstance(value, str) and bool(value.strip()) and not PLACEHOLDER_RE.search(value)


def expand_home(raw, home):
    p = Path(raw)
    return home.joinpath(*p.parts[1:]) if p.parts[:1] == ('~',) else p


def clean_headers(raw):
    if not isinstance(raw, dict):
        return None
    out = {k: v for k, v in raw.items() if isinstance(k, str) and usable_str(v)}
    return out or None


def load_jsonc(path):
    try:
        text = path.read_text(encoding='utf-8')
    except OSError:
        return {}
    string = r'"(?:\\.|[^"\\])*"'
    clean = re.sub(f'({string})|//[^\n]*|/\\*[\\s\\S]*?\\*/', lambda m: m.group(1) or '', text)
    clean = re.sub(f'({string})|,(\\s*[}}\\]])', lambda m: m.group(1) or m.group(2), clean)
    try:
        data = json.loads(clean) if clean.strip() else {}
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def merge_dict(base, over):
    out = dict(base)
    for k, v in over.items():
        out[k] = merge_dict(out[k], v) if isinstance(out.get(k), dict) and isinstance(v, dict) else v
    return out


def oc_mcp_entry(env, home, name):
    oc_dir = expand_home(env.get('OPENCODE_CONFIG_DIR') or Path(env.get('XDG_CONFIG_HOME') or home / '.config') / 'opencode', home)
    oc = merge_dict(load_jsonc(oc_dir / 'opencode.json'), load_jsonc(oc_dir / 'opencode.jsonc'))
    mcp = oc.get('mcp') if isinstance(oc.get('mcp'), dict) else {}
    servers = mcp.get('servers') if isinstance(mcp.get('servers'), dict) else {}
    entry = servers.get(name) if isinstance(servers.get(name), dict) else mcp.get(name)
    return entry if isinstance(entry, dict) else None


def discover_web_mcp(env, home):
    raw_host = (env.get('MCPHUB_HOST') or '').strip().rstrip('/')
    if usable_str(raw_host):
        if re.match(r'^https?://', raw_host):
            url = raw_host + '/mcp/web' if re.match(r'^https?://[^/]+$', raw_host) else raw_host
        else:
            url = f'https://{raw_host}/mcp/web'
        return url, None
    pi_dir = expand_home(env.get('PI_CODING_AGENT_DIR') or home / '.pi/agent', home)
    pi_servers = load_jsonc(pi_dir / 'mcp.json').get('mcpServers')
    pi_web = pi_servers.get('web') if isinstance(pi_servers, dict) else None
    for candidate in (pi_web, oc_mcp_entry(env, home, 'web')):
        if isinstance(candidate, dict):
            url = candidate.get('url') or candidate.get('serverUrl')
            if usable_str(url) and re.match(r'^https?://', url.strip()):
                return url.strip(), clean_headers(candidate.get('headers'))
    return None, None


def discover_node_bin(env, home):
    ext = '.exe' if os.name == 'nt' else ''
    path_env = env.get('PATH')
    oc_entry = oc_mcp_entry(env, home, 'claude-mem') or {}
    oc_cmd = oc_entry.get('command')
    oc_node = oc_cmd[0] if isinstance(oc_cmd, list) and oc_cmd and isinstance(oc_cmd[0], str) else None
    if oc_node and Path(oc_node).name.lower() not in ('node', 'node.exe'):
        oc_node = None
    candidates = (
        oc_node,
        str(home / f'.local/share/pi-node/current/bin/node{ext}'),
        str(home / f'.local/share/fnm/aliases/default/bin/node{ext}'),
        str(home / f'.fnm/aliases/default/bin/node{ext}'),
        str(home / f'Library/Application Support/fnm/aliases/default/bin/node{ext}'),
        shutil.which('node', path=path_env),
    )
    for cand in candidates:
        if cand and Path(cand).is_file() and os.access(cand, os.X_OK):
            if 'fnm_multishells' in cand:
                try:
                    return str(Path(cand).resolve())
                except OSError:
                    pass
            return str(Path(cand))
    return None


def discover_codegraph_cmd(env, home):
    ext = '.exe' if os.name == 'nt' else ''
    path_env = env.get('PATH')
    candidates = [
        shutil.which('codegraph', path=path_env),
        shutil.which('codegraph.cmd', path=path_env),
        str(home / f'.local/bin/codegraph{ext}'),
    ]
    for cand in candidates:
        if not cand or not Path(cand).is_file() or not os.access(cand, os.X_OK):
            continue
        p = Path(cand)
        if p.suffix.lower() in ('.cmd', '.bat'):
            shim = p.parent / 'node_modules/@colbymchenry/codegraph/npm-shim.js'
            node = discover_node_bin(env, home)
            if shim.is_file() and node:
                return node, [str(shim), 'serve', '--mcp']
            continue
        return str(p), ['serve', '--mcp']
    return None, None


def discover_claude_mem_cmd(env, home):
    claude_dir = expand_home(env.get('CLAUDE_CONFIG_DIR') or home / '.claude', home)
    script = claude_dir / 'plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs'
    if not script.is_file():
        return None, None
    node = discover_node_bin(env, home)
    return (node, [str(script)]) if node else (None, None)


def is_managed_claude_mem(entry):
    if entry is None:
        return True
    if not isinstance(entry, dict) or 'url' in entry or 'serverUrl' in entry:
        return False
    if not usable_str(entry.get('command')):
        return True
    args = entry.get('args')
    return isinstance(args, list) and any(
        isinstance(a, str) and (('thedotmack' in a and a.endswith('mcp-server.cjs')) or bool(PLACEHOLDER_RE.search(a)))
        for a in args
    )


def bridge_t3_antigravity_mcp(home, source_mcp, backups_dir):
    t3_root = home / '.t3/userdata/providers/antigravity'
    if not t3_root.is_dir() or t3_root.is_symlink() or not source_mcp.is_file():
        return
    can_link = os.name != 'nt' and not sys.platform.startswith(('msys', 'cygwin'))
    src_bytes = source_mcp.read_bytes()
    for prof in sorted(t3_root.iterdir()):
        if not prof.is_dir() or prof.is_symlink():
            continue
        cfg_dir = prof / 'config'
        if cfg_dir.is_symlink() or not (cfg_dir.is_dir() or (prof / 'antigravity-acp').is_dir()):
            continue
        cfg_dir.mkdir(exist_ok=True)
        target = cfg_dir / 'mcp_config.json'
        if target.is_symlink():
            if target.exists() and target.samefile(source_mcp):
                continue
            print(f'WARN: 保留 T3 自定义符号链接：{target}', file=sys.stderr)
            continue
        if target.exists():
            old = target.read_bytes()
            if old.strip() and normalized(old) != normalized(src_bytes):
                try:
                    parsed = json.loads(old)
                    existing_servers = parsed.get('mcpServers') if isinstance(parsed, dict) else None
                except ValueError:
                    existing_servers = None
                if not isinstance(existing_servers, dict) or (set(existing_servers) - set(MANAGED_MCP_NAMES)):
                    print(f'WARN: 保留 T3 独立 MCP 配置：{target}', file=sys.stderr)
                    continue
                backups_dir.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(prefix='t3-antigravity-mcp_config.json.bak-', dir=backups_dir, delete=False) as f:
                    f.write(old)
            elif not can_link and normalized(old) == normalized(src_bytes):
                if os.name != 'nt':
                    target.chmod(0o600)
                continue
        if can_link:
            with tempfile.NamedTemporaryFile(dir=cfg_dir, delete=False) as f:
                tmp = Path(f.name)
            tmp.unlink()
            try:
                tmp.symlink_to(source_mcp)
                os.replace(tmp, target)
                print(f'Antigravity: 已桥接 T3 MCP 配置 → {target}')
            finally:
                if tmp.exists() or tmp.is_symlink():
                    tmp.unlink()
        else:
            replace(target, src_bytes)
            if os.name != 'nt':
                target.chmod(0o600)
            print(f'Antigravity: 已同步 T3 MCP 配置 → {target}')


def antigravity_mcp():
    env = os.environ
    home = Path(env.get('HOME') or Path.home())
    p = home / '.gemini/config/mcp_config.json'
    backups = Path(env.get('XDG_DATA_HOME') or home / '.local/share') / 'agent-skills/.backups'
    try:
        raw = read_target(p)
        config = json.loads(raw) if raw.strip() else {}
        if not isinstance(config, dict) or not isinstance(config.get('mcpServers', {}), dict):
            raise ValueError('需要含 mcpServers 对象的 JSON 配置')
        orig_servers = config.get('mcpServers')
        servers = dict(orig_servers or {})

        # 1. web (Streamable HTTP；沿用宿主默认懒加载，保留已有有效 URL 与 stdio 桥接)
        cur_web = servers.get('web')
        if cur_web is None or isinstance(cur_web, dict):
            cur_url = (cur_web or {}).get('url') or (cur_web or {}).get('serverUrl')
            if not usable_str(cur_url) and (not cur_web or 'command' not in cur_web):
                url, headers = discover_web_mcp(env, home)
                if url:
                    entry = dict(cur_web or {})
                    key = 'serverUrl' if 'serverUrl' in entry and 'url' not in entry else 'url'
                    entry[key] = url
                    if headers and 'headers' not in entry:
                        entry['headers'] = headers
                    servers['web'] = entry

        # 2. codegraph (stdio)
        cur_cg = servers.get('codegraph')
        if cur_cg is None or (isinstance(cur_cg, dict) and 'url' not in cur_cg and 'serverUrl' not in cur_cg
                              and str(cur_cg.get('type', '')).lower() != 'remote'
                              and (not usable_str(cur_cg.get('command')) or cur_cg.get('args') in (None, ['serve', '--mcp']))):
            cg_cmd, cg_args = discover_codegraph_cmd(env, home)
            if cg_cmd:
                entry = dict(cur_cg or {})
                entry['command'] = cg_cmd
                entry['args'] = cg_args
                servers['codegraph'] = entry

        # 3. claude-mem MCP 检索端 (stdio；不写 Antigravity hooks，保留非 thedotmack 自定义条目)
        cur_mem = servers.get('claude-mem')
        if is_managed_claude_mem(cur_mem):
            mem_cmd, mem_args = discover_claude_mem_cmd(env, home)
            if mem_cmd:
                entry = dict(cur_mem or {})
                entry['command'] = mem_cmd
                entry['args'] = mem_args
                servers['claude-mem'] = entry

        if not servers:
            return 0
        if isinstance(orig_servers, dict) and servers == orig_servers:
            if os.name != 'nt' and p.is_file():
                p.chmod(0o600)
            print(f'Antigravity: MCP 配置已同步 ({", ".join(servers)}) → {p}')
            bridge_t3_antigravity_mcp(home, p, backups)
            return 0
        config['mcpServers'] = servers
        new_bytes = (json.dumps(config, ensure_ascii=False, indent=2) + '\n').encode()
        if raw.strip():
            backups.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(prefix='antigravity-mcp_config.json.bak-', dir=backups, delete=False) as f:
                f.write(raw)
        replace(p, new_bytes)
        if os.name != 'nt':
            p.chmod(0o600)
        print(f'Antigravity: 已更新 MCP 配置 ({", ".join(servers)}) → {p}')
        bridge_t3_antigravity_mcp(home, p, backups)
        return 0
    except (OSError, ValueError) as e:
        print(f'WARN: {p}: {e}', file=sys.stderr)
        return 1


def released_blocks(block):
    yield block
    proc = subprocess.run(['git', '-C', str(ROOT), 'log', '--format=%H', '--', 'AGENTS.tail.md'], stdout=subprocess.PIPE, check=True)
    for rev in proc.stdout.decode().splitlines():
        data = subprocess.check_output(['git', '-C', str(ROOT), 'show', rev + ':AGENTS.tail.md'])
        if START in data and END in data:
            yield canonical(data)


def migrate(p, known, apply, globals_):
    if p.resolve() in globals_:
        raise ValueError('这是用户级文件，不是待迁移项目')
    old = read_target(p)
    loc = span(old)
    if not loc:
        return '无旧块'
    if normalized(old[loc]) not in known:
        raise ValueError('旧块有定制或本地 Git 历史不全，保留，请人工核对')
    if not apply:
        return '可迁移（预览，未写入）'
    with tempfile.NamedTemporaryFile(prefix=p.name + '.bak-', dir=p.parent, delete=False) as f:
        f.write(old)
        backup = f.name
    remaining = old[:loc.start] + old[loc.stop:]
    if remaining in (b'', b'\n', b'\r\n'):
        p.unlink()
    else:
        replace(p, remaining)
    return f'已移除旧块；恢复请复制备份 {backup} 到 {p}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('projects', nargs='*', type=Path)
    parser.add_argument('--sync-global', action='store_true', help='同步本账号已配置宿主')
    parser.add_argument('--sync-host', choices=HOSTS, help='只同步指定宿主的用户级公共块（目录不存在也创建）')
    parser.add_argument('--antigravity-skills', action='store_true', help='清理旧 skills.json 中重复的共享 Skill 目录条目')
    parser.add_argument('--antigravity-mcp', action='store_true', help='同步 Antigravity 基础 MCP 配置并桥接 T3 隔离目录')
    parser.add_argument('--apply', action='store_true', help='确认项目不再需要随仓分发公共块，备份后移除')
    args = parser.parse_args()
    if args.antigravity_skills:
        if args.projects or args.apply or args.sync_global or args.sync_host or args.antigravity_mcp:
            parser.error('--antigravity-skills 须单独使用')
        return antigravity_skills()
    if args.antigravity_mcp:
        if args.projects or args.apply or args.sync_global or args.sync_host:
            parser.error('--antigravity-mcp 须单独使用')
        return antigravity_mcp()
    if args.sync_host and (args.sync_global or args.apply or args.projects):
        parser.error('--sync-host 须与 --sync-global、--apply 和项目目录分开使用')
    if not args.sync_host and (args.sync_global == bool(args.projects) or (args.sync_global and args.apply)):
        parser.error('指定项目目录（可加 --apply），或单独使用 --sync-global / --sync-host HOST')
    block = canonical((ROOT / 'AGENTS.tail.md').read_bytes())
    hosts = list(targets(args.sync_host))
    failed = False
    if args.sync_global or args.sync_host or args.apply:
        if not hosts:
            print('未检测到宿主配置目录，未写入')
            return int(args.apply)
        for host, p in hosts:
            try:
                override = p.with_name('AGENTS.override.md')
                if host == 'codex' and override.is_file() and override.read_bytes().strip():
                    raise ValueError(f'{override} 优先，保留临时覆盖；请先处理该文件')
                print(host, p, global_block(p, block, args.sync_global or bool(args.sync_host)))
            except (OSError, ValueError) as e:
                print(f'WARN: {p}: {e}', file=sys.stderr)
                failed = True
        if not args.projects or failed:
            return int(failed)
    known = set(released_blocks(block))
    for project in args.projects:
        p = project / 'AGENTS.md'
        try:
            if not project.is_dir():
                raise ValueError('项目目录不存在')
            print(p, migrate(p, known, args.apply, {path.resolve() for _, path in hosts}))
        except (OSError, ValueError) as e:
            print(f'WARN: {p}: {e}', file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
