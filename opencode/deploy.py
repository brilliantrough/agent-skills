#!/usr/bin/env python3
"""安装对应主版本的插件产物；不启动 OpenCode、不访问会话数据库。"""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import shutil
import sys
from datetime import datetime
from urllib.parse import unquote, urlparse
from typing import Any

STAMP = datetime.now().strftime('%Y%m%d%H%M%S%f')
MC = '@cortexkit/opencode-magic-context'


def load(path) -> dict[str, Any]:
    if not path.exists():
        return {}
    text = path.read_text(encoding='utf-8')
    string = r'"(?:\\.|[^"\\])*"'
    text = re.sub(f'({string})|//[^\n]*|/\\*[\\s\\S]*?\\*/', lambda m: m[1] or '', text)
    text = re.sub(f'({string})|,(\\s*[}}\\]])', lambda m: m[1] or m[2], text)
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise ValueError(f'{path} JSON 解析失败，保留原文件：{error}') from error
    if not isinstance(value, dict):
        raise ValueError(f'{path} 必须为 JSON 对象')
    return value


def writable(path):
    if any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError(f'不覆盖符号链接：{path}')


def write(path, value):
    if load(path) == value:
        return
    writable(path)
    if path.exists():
        shutil.copy2(path, str(path) + '.bak-' + STAMP)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.new')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.chmod(0o600)
    temp.replace(path)
    print(f'updated: {path}')


def package(entry):
    return entry.get('package', '') if isinstance(entry, dict) else entry[0] if isinstance(entry, list) else entry


def native(entry) -> Any:
    return {'package': entry[0], 'options': entry[1]} if isinstance(entry, list) else entry


def magic_context(entries, major, cfg):
    entry = next((e for e in entries if is_mc(e)), None)
    if entry is None:
        cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'opencode'
        installed = cache / 'packages' / (MC + '@latest') / 'node_modules' / MC / 'package.json'
        pi = Path.home() / '.pi/agent/npm/node_modules/pi-magic-context/package.json'
        version = load(installed).get('version') or load(pi).get('version')
        data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
        if not version and (data / 'cortexkit/magic-context/context.db').exists():
            raise ValueError('已有共享 Magic Context 数据库但无法确认运行版本；请先单独配置插件，不自动引入新版本')
        entry = MC + '@' + (version or '0.45.0')
    if major == 1:
        return entry
    spec = package(entry)
    if spec.startswith('file:'):
        parsed = urlparse(spec)
        root = Path(unquote(parsed.path).lstrip('/') if os.name == 'nt' else unquote(parsed.path))
    elif spec.startswith(('.', '/')) or re.match(r'^[A-Za-z]:[/\\]', spec):
        root = Path(spec) if Path(spec).is_absolute() else cfg / spec
    else:
        version = spec[len(MC):].lstrip('@') or 'latest'
        if version != 'latest':
            if tuple(int(n) for n in version.split('.')[:2]) < (0, 45):
                raise ValueError('现有 Magic Context 早于 0.45；请在停用各宿主的窗口单独升级，再配置 v2')
            return native(entry) if entry else spec
        cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'opencode'
        root = cache / 'packages' / (MC + '@latest') / 'node_modules' / MC
        if not (root / 'package.json').exists():
            raise ValueError('无法确定现有 Magic Context @latest 的已装版本；请先把条目固定为已安装版本或包目录，不自动升级共享数据库')
    version = load(root / 'package.json').get('version', '')
    if not version or tuple(int(n) for n in version.split('.')[:2]) < (0, 45):
        raise ValueError(f'Magic Context 包缺失或不支持 v2：{root}；保留配置，请单独处理')
    normalized = native(entry)
    return {**normalized, 'package': str(root)} if isinstance(normalized, dict) else str(root)


def is_mc(entry):
    spec = str(package(entry))
    return not spec.startswith('-') and 'opencode-magic-context' in spec


def owned(entry):
    spec = str(package(entry)).replace('\\', '/')
    if spec.startswith('-'):
        return False
    return any(s in spec for s in ['claude-mem-wrapper.js', '/claude-mem.js', 'plugins/later.js',
        'context-rewrite.js', 'zz-agent-skills.js', 'tui-plugins/later', 'context-mode.js']) or bool(re.fullmatch(r'(npm:)?context-mode(@[^/]+)?', spec))


def merge(base, over):
    out = dict(base)
    for key, value in over.items():
        out[key] = merge(out[key], value) if isinstance(out.get(key), dict) and isinstance(value, dict) else value
    return out


def cli_config(cfg):
    if (cfg / 'cli.json').exists():
        return cfg / 'cli.json', load(cfg / 'cli.json')
    # v2 首启用自身迁移器转换旧 action 名、界面配置与 state/kv.json。
    old = merge(load(cfg / 'tui.json'), load(cfg / 'tui.jsonc'))
    old['plugin'] = [e for e in old.get('plugin', []) if not owned(e) and not is_mc(e)]
    return cfg / 'tui.json', old


def install(root, cfg, major, check=False):
    manifest = load(root / 'MANIFEST.json')
    if manifest.get('major') != major:
        raise ValueError('发布包主版本与客户端不一致')
    import hashlib
    expected = ['plugins/zz-agent-skills.js', 'tui-plugins/later', 'context-rewrite'] if major == 1 else ['v2']
    if manifest['install'] != expected:
        raise ValueError('发布包安装目标不符合版本清单')
    for relative, digest in manifest['files'].items():
        path = root / relative
        if root.resolve() not in path.resolve().parents:
            raise ValueError(f'发布包文件路径越界：{relative}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'发布包校验失败：{relative}')
    target = cfg / 'opencode.json'
    config = merge(load(target), load(cfg / 'opencode.jsonc'))
    entries = [*config.get('plugin', []), *config.get('plugins', [])]
    if major == 1 and any(str(package(e)).replace('\\', '/').rstrip('/').endswith('/v2') for e in entries):
        raise ValueError('该配置已用于 v2；v1 请使用隔离配置目录，不自动降级数据库或插件')
    mc = magic_context(entries, major, cfg)
    entries = [e for e in entries if not owned(e) and not is_mc(e)]
    previous = next((e for e in entries if str(package(e)).replace('\\', '/').rstrip('/') == cfg.as_posix() + '/v2'), {})
    cli_path, cli = cli_config(cfg) if major == 2 else (cfg / 'tui.json', {})
    if major == 2:
        entries = [native(e) for e in entries if '@dietrichgebert/ponytail' not in str(package(e)) and e != previous]
        entries = [e for e in entries if not any(s in str(package(e)) for s in ['session-notify.js', 'fixed-prompt-cache-key.js', 'session-id-header.js'])]
        entries.insert(0, mc)
        entries.append({**previous, 'package': str(cfg / 'v2')} if isinstance(previous, dict) else str(cfg / 'v2'))
        config.pop('plugin', None)
        config['plugins'] = entries
        paths = config.setdefault('skills', {}).setdefault('paths', [])
        skills = str(cfg / 'v2/ponytail/skills')
        if skills not in paths:
            paths.append(skills)
    else:
        config['plugin'] = [mc, *entries]
        if not any('@dietrichgebert/ponytail' in str(package(e)) for e in entries):
            config['plugin'].append('@dietrichgebert/ponytail')
        config.pop('plugins', None)
    files = ['claude-mem-wrapper.js', 'later.js', 'zz-context-rewrite.js', 'context-rewrite.js']
    if major == 2:
        files += ['zz-agent-skills.js', 'context-mode.js', 'session-notify.js', 'fixed-prompt-cache-key.js', 'session-id-header.js']
    obsolete = [cfg / 'plugins' / name for name in files if (cfg / 'plugins' / name).exists()]
    for path in [target, cfg / 'opencode.jsonc', *(cfg / name for name in manifest['install']), *obsolete]:
        writable(path)
    if major == 2:
        writable(cli_path)
        writable(cfg / 'tui.jsonc')
    if check:
        print(f'ready: v{major} 发布包、配置和 Magic Context 版本检查通过（未写入）')
        return
    for relative in manifest['install']:
        source, destination = root / relative, cfg / relative
        if source.is_dir():
            before = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest() for p in destination.rglob('*') if p.is_file()}
            after = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file()}
            if before == after:
                print(f'unchanged: {destination}')
                continue
        elif destination.exists() and source.read_bytes() == destination.read_bytes():
            print(f'unchanged: {destination}')
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + '.new-' + STAMP)
        shutil.copytree(source, temporary) if source.is_dir() else shutil.copy2(source, temporary)
        if destination.exists():
            destination.rename(str(destination) + '.bak-' + STAMP)
        temporary.replace(destination)
        print(f'deployed: {destination}')
    for path in obsolete:
        path.rename(str(path) + '.bak-' + STAMP)
        print(f'retired: {path}')
    write(target, config)
    if (cfg / 'opencode.jsonc').exists():
        (cfg / 'opencode.jsonc').rename(cfg / ('opencode.jsonc.migrated-' + STAMP + '.bak'))
    if major == 2:
        write(cli_path, cli)
        if cli_path.name == 'tui.json' and (cfg / 'tui.jsonc').exists():
            (cfg / 'tui.jsonc').rename(cfg / ('tui.jsonc.migrated-' + STAMP + '.bak'))
            print('prepared: tui.json（原 JSONC 已备份；cli.json 由 v2 首启生成）')
    print(f'OpenCode v{major} 插件已部署；未启动宿主、未迁移数据库')


if __name__ == '__main__':
    try:
        install(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), '--check' in sys.argv[4:])
    except Exception as error:
        sys.exit(f'ERROR: {error}')
