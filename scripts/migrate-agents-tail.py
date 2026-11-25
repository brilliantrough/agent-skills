#!/usr/bin/env python3
"""同步宿主原生指令与发现入口，或按显式项目路径迁移旧规则。"""
import argparse
import json
import os
from pathlib import Path
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
    home = Path(os.environ.get('HOME') or Path.home())
    p = home / '.gemini/config/skills.json'
    shared = (home / '.agents/skills').resolve()
    try:
        raw = read_target(p)
        config = json.loads(raw) if p.exists() else {}
        if not isinstance(config, dict) or not isinstance(config.get('entries', []), list):
            raise ValueError('需要含 entries 数组的 JSON 对象')
        entries = config.setdefault('entries', [])
        found = False
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get('path'), str):
                raise ValueError('entries 中缺少有效的 path')
            path = p.parent / entry['path']
            matches = path.resolve() == shared
            if matches != (Path(os.path.abspath(path)).resolve() == shared):
                raise ValueError('链接目录中的相对路径有歧义，请将该清单条目的 path 改为绝对路径')
            found |= matches
        if found:
            return 0  # 保留用户对共享目录已有的 include_only / exclude。
        entries.append({'path': str(shared)})
        replace(p, (json.dumps(config, ensure_ascii=False, indent=2) + '\n').encode())
        print(f'Antigravity: 已登记共享 Skill 目录 → {p}')
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
    parser.add_argument('--antigravity-skills', action='store_true', help='登记共享 Skill 目录')
    parser.add_argument('--apply', action='store_true', help='确认项目不再需要随仓分发公共块，备份后移除')
    args = parser.parse_args()
    if args.antigravity_skills:
        if args.projects or args.apply or args.sync_global or args.sync_host:
            parser.error('--antigravity-skills 须单独使用')
        return antigravity_skills()
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
