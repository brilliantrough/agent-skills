#!/usr/bin/env python3
"""安装对应主版本的插件产物；不启动 OpenCode、不访问会话数据库。"""
from __future__ import annotations
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote, urlparse

STAMP = datetime.now().strftime('%Y%m%d%H%M%S%f')
MC = '@cortexkit/opencode-magic-context'
PONYTAIL = '@dietrichgebert/ponytail'
LEGACY = ['plugins/claude-mem-wrapper.js', 'plugins/later.js',
          'plugins/zz-context-rewrite.js', 'plugins/context-rewrite.js']
V1_ONLY = ['plugins/zz-agent-skills.js', 'plugins/context-mode.js',
           'plugins/session-notify.js', 'plugins/fixed-prompt-cache-key.js',
           'plugins/session-id-header.js', 'tui-plugins/later',
           'context-rewrite', 'plugins/context-mode']


def retire(path, cfg):
    destination = cfg / '.agent-skills-backups' / STAMP / path.relative_to(cfg)
    writable(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    path.rename(destination)
    print(f'backup: {path} -> {destination}')


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


def writable_cache(path):
    """允许用户缓存根与 OpenCode v2 的 @latest 叶子链接保持符号链接。"""
    cache_home = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache'))
    cache_root = cache_home / 'opencode'
    try:
        path.relative_to(cache_root)
    except ValueError as error:
        raise ValueError(f'缓存路径越界：{path}') from error
    for parent in path.parents:
        if parent == cache_home:
            continue
        if parent.is_symlink():
            raise ValueError(f'不覆盖符号链接父路径：{path}')


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


def directory(entry, cfg):
    spec = str(package(entry))
    if spec.startswith('file:'):
        spec = unquote(urlparse(spec).path)
        if os.name == 'nt':
            spec = spec.lstrip('/')
    path = Path(spec)
    if path.is_absolute():
        return path.resolve()
    return (cfg / path).resolve() if spec.startswith('.') else None


def native(entry) -> Any:
    return {'package': entry[0], 'options': entry[1]} if isinstance(entry, list) else entry


def npm_caches(name, spec='latest'):
    cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'opencode'
    key = name + '@' + spec
    if os.name == 'nt':
        key = re.sub(r'[<>:"|?*\x00-\x1f]', '_', key)
    return [cache / layout / key for layout in ('npm', 'packages')]


def cached_package(name, major=None, spec='latest'):
    caches = npm_caches(name, spec)
    if major is not None:
        caches = [caches[0 if major == 2 else 1]]
    for cache in caches:
        generations = sorted((p for p in cache.glob('*') if p.is_dir() and p.name.isdecimal()),
                             key=lambda p: int(p.name))
        root = (generations[-1] if generations else cache) / 'node_modules' / name
        if (root / 'package.json').exists():
            return root
    return None


def refreshed_entry(entry, name, major):
    updated = native(entry) if major == 2 else entry
    spec = name + '@latest'
    if isinstance(updated, dict):
        return {**updated, 'package': spec}
    if isinstance(updated, list):
        return [spec, *updated[1:]]
    return spec


def matches_package(entry, name):
    spec = str(package(entry)).replace('\\', '/')
    if spec == name or spec.startswith(name + '@'):
        return True
    local = spec.startswith(('.', '/', 'file:')) or re.match(r'^[A-Za-z]:/', spec)
    return bool(local and re.search(r'(^|/)' + re.escape(name) + r'(/|$)', spec))


def plugin_versions(cfg, major, output):
    config = merge(load(cfg / 'opencode.json'), load(cfg / 'opencode.jsonc'))
    entries = [*config.get('plugin', []), *config.get('plugins', [])]
    report = {}
    for name in (PONYTAIL, MC):
        entry = next((e for e in entries if matches_package(e, name)), name)
        spec = str(package(entry))
        local = directory(entry, cfg)
        revision = (spec[len(name):].lstrip('@') or 'latest') if local is None else 'latest'
        root = local if local is not None else cached_package(name, major, revision)
        current = None
        try:
            current = load(root / 'package.json').get('version') if root else None
        except (OSError, ValueError) as error:
            print(f'WARN: {name} 本地包版本无法读取：{error}')
        row = {'current': current, 'latest': None, 'prompt': None}
        default = 'Y' if name == PONYTAIL and local is None and revision == 'latest' else 'N'
        try:
            result = subprocess.run(['curl', '-fsSL', '--connect-timeout', '5', '-m', '15',
                                     'https://registry.npmjs.org/' + quote(name, safe='@/') + '/latest'],
                                    check=True, capture_output=True, text=True, encoding='utf-8')
            latest = json.loads(result.stdout)['version']
            remote = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)', latest)
            installed = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)', current or '')
            row['latest'] = latest
            if current == latest:
                status = '版本一致（不代表加载状态正常）'
            elif remote and installed:
                newer = tuple(map(int, remote.groups())) > tuple(map(int, installed.groups()))
                status = '有新版' if newer else '本地版本高于 latest，不降级'
                if newer:
                    row['prompt'] = default
            elif current:
                status = '非稳定版本，保留；请手工核对'
            else:
                status = '未安装／版本未知'
                # 缺包交宿主；已有未知缓存或显式路径／钉版才询问是否换回官方 latest。
                caches = npm_caches(name, revision)
                if remote and (local is not None or revision != 'latest' or caches[0 if major == 2 else 1].exists()):
                    row['prompt'] = default
            print(f'{name}: 本地 {current or "未安装／未知"} / npm latest {latest} — {status}')
        except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError) as error:
            print(f'WARN: {name}: 本地 {current or "未安装／未知"} / npm latest 查询失败；不据此刷新缓存：{error}')
        report[name] = row
    output.write_text(json.dumps(report, ensure_ascii=False), encoding='utf-8')


def magic_context(entries, major, cfg, refresh=False):
    entry = next((e for e in entries if is_mc(e)), None)
    if refresh:
        return refreshed_entry(entry, MC, major)
    try:
        return resolve_magic_context(entry, major, cfg)
    except ValueError as error:
        print(f'WARN: Magic Context：{error}')
        print('WARN: 未刷新缓存，保留现有登记；继续部署其他插件。Magic Context 尚未就绪，宿主启动可能失败；可重跑 setup 并确认刷新。')
        return native(entry) if major == 2 else entry


def resolve_magic_context(entry, major, cfg):
    if entry is None:
        installed = cached_package(MC)
        agent = Path(os.environ.get('PI_CODING_AGENT_DIR', Path.home() / '.pi/agent'))
        pi = agent / 'npm/node_modules/@cortexkit/pi-magic-context/package.json'
        version = load(installed / 'package.json').get('version') if installed else ''
        version = version or load(pi).get('version') or load(agent / 'npm/node_modules/pi-magic-context/package.json').get('version')
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
        root = cached_package(MC, major)
        if root is None:
            raise ValueError('无法确定现有 Magic Context @latest 的已装版本；请先把条目固定为已安装版本或包目录，不自动升级共享数据库')
    version = load(root / 'package.json').get('version', '')
    if not version or tuple(int(n) for n in version.split('.')[:2]) < (0, 45):
        raise ValueError(f'包版本 {version or "未知／缺失"}，v2 要求至少 0.45：{root}')
    normalized = native(entry)
    return {**normalized, 'package': str(root)} if isinstance(normalized, dict) else str(root)


def is_mc(entry):
    spec = str(package(entry))
    return not spec.startswith('-') and 'opencode-magic-context' in spec


def owned(entry, cfg):
    spec = str(package(entry))
    if spec.startswith('-'):
        return False
    paths = [*LEGACY, 'plugins/claude-mem.js', 'plugins/zz-agent-skills.js',
             'plugins/context-mode.js', 'plugins/context-mode',
             'tui-plugins/later', 'tui-plugins/later/index.mjs',
             'v2/later-cli.js', 'v2/tui.js']
    return directory(entry, cfg) in [(cfg / p).resolve() for p in paths] or bool(
        re.fullmatch(r'(npm:)?(context-mode|claude-mem)(@[^/]+)?', spec))


def merge(base, over):
    out = dict(base)
    for key, value in over.items():
        if key in ('plugin', 'plugins') and isinstance(out.get(key), list) and isinstance(value, list):
            out[key] = out[key] + [entry for entry in value if entry not in out[key]]
        else:
            out[key] = merge(out[key], value) if isinstance(out.get(key), dict) and isinstance(value, dict) else value
    return out


def cli_config(cfg):
    if (cfg / 'cli.json').exists():
        cli = load(cfg / 'cli.json')
        if 'plugins' in cli:
            cli['plugins'] = [e for e in cli['plugins'] if not owned(e, cfg) and not is_mc(e)]
        return cfg / 'cli.json', cli
    # v2 首启用自身迁移器转换旧 action 名、界面配置与 state/kv.json。
    old = merge(load(cfg / 'tui.json'), load(cfg / 'tui.jsonc'))
    old['plugin'] = [e for e in old.get('plugin', []) if not owned(e, cfg) and not is_mc(e)]
    return cfg / 'tui.json', old


def install(root, cfg, major, check=False, refresh_mc=False, refresh_ponytail=False):
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
    if major == 1 and ((cfg / 'v2').exists() or (cfg / 'cli.json').exists() or 'plugins' in config):
        raise ValueError('该配置已用于 v2；v1 请使用隔离配置目录，不自动降级数据库或插件')
    mc = magic_context(entries, major, cfg, refresh_mc)
    entries = [e for e in entries if not owned(e, cfg) and not is_mc(e)]
    if refresh_ponytail:
        entries = [refreshed_entry(e, PONYTAIL, major) if matches_package(e, PONYTAIL) else e for e in entries]
    old_entry = next((e for e in entries if directory(e, cfg) == (cfg / 'v2').resolve()), {})
    previous = native(old_entry)
    cli_path, cli = cli_config(cfg) if major == 2 else (cfg / 'tui.json', merge(load(cfg / 'tui.json'), load(cfg / 'tui.jsonc')))
    if major == 2:
        ponytail = previous.get('options', {}).get('ponytailPackage') if isinstance(previous, dict) else None
        if isinstance(previous, dict) and 'options' in previous:
            previous = {**previous, 'options': {k: v for k, v in previous['options'].items() if k != 'ponytailPackage'}}
            if not previous['options']:
                previous.pop('options')
        official_ponytail = next((native(e) for e in entries if matches_package(e, PONYTAIL)), PONYTAIL + ('@latest' if refresh_ponytail else ''))
        entries = [native(e) for e in entries if not matches_package(e, PONYTAIL) and e != old_entry]
        entries = [e for e in entries if directory(e, cfg) not in [(cfg / p).resolve() for p in V1_ONLY]]
        if mc is not None:
            entries.insert(0, mc)
        entries.append(official_ponytail)
        entries.append({**previous, 'package': str(cfg / 'v2')} if isinstance(previous, dict) else str(cfg / 'v2'))
        config.pop('plugin', None)
        config['plugins'] = entries
        if isinstance(config.get('skills'), dict) and 'paths' in config['skills']:
            retired = {(cfg / 'v2/ponytail/skills').resolve()}
            if ponytail:
                retired.add((Path(ponytail) / 'skills').resolve())
            config['skills']['paths'] = [p for p in config['skills']['paths'] if (cfg / p).resolve() not in retired]
    else:
        config['plugin'] = ([mc] if mc is not None else []) + entries
        if not any(matches_package(e, PONYTAIL) for e in entries):
            config['plugin'].append(PONYTAIL + ('@latest' if refresh_ponytail else ''))
        config.pop('plugins', None)
        cli['plugin'] = [e for e in cli.get('plugin', []) if not owned(e, cfg) and not is_mc(e)]
        cli['plugin'] += ([mc] if mc is not None else []) + ['./tui-plugins/later']
    obsolete = [cfg / p for p in [*LEGACY, *(V1_ONLY if major == 2 else [])] if (cfg / p).exists()]
    # 移走已知旧备份，不能留在 v2 会自动发现子目录的 plugins/ 下。
    obsolete += [p for p in (cfg / 'plugins').glob('context-mode.bak-*') if p.is_dir()]
    bundled = cfg / 'lib/claude-mem.js'
    old_bundle = cfg / 'plugins/claude-mem.js'
    if old_bundle.exists():
        obsolete.append(old_bundle)
    for path in [target, cfg / 'opencode.jsonc', cli_path, cfg / 'tui.jsonc', bundled,
                 cfg / '.agent-skills-backups', cfg / 'plugins/context-mode',
                 cfg / 'plugins/context-mode.js', cfg / 'vendor/context-mode',
                 *(cfg / name for name in manifest['install']), *obsolete]:
        writable(path)
    print(f'package: {manifest["version"]} / OpenCode v{major}')
    for relative in manifest['install']:
        print(f'managed: {cfg / relative}')
    for path in obsolete:
        print(f'retire: {path}')
    print(f'config: {target.name} ({"plugins" if major == 2 else "plugin"}), {cli_path.name}; 私密字段保留')
    cache_backups = []
    for name, refresh, folder in ((MC, refresh_mc, 'magic-context-cache'), (PONYTAIL, refresh_ponytail, 'ponytail-cache')):
        if not refresh:
            continue
        for cache in npm_caches(name):
            if not cache.exists():
                continue
            destination = cfg / '.agent-skills-backups' / STAMP / folder / cache.parent.parent.name / cache.name
            writable_cache(cache)
            writable(destination)
            cache_backups.append((cache, destination))
            print(f'refresh: {cache} -> {destination}')
        print(f'{name}: 改用 @latest；下次宿主启动下载，setup 不访问共享数据库、不更新 Pi 包')
    if check:
        print('ready: 发布包和配置检查完成；Magic Context 状态见上方 WARN（未写入）')
        return
    for cache, destination in cache_backups:
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.move(str(cache), str(destination))
        except OSError as error:
            raise ValueError(f'刷新缓存失败：{cache} -> {destination}：{error}') from error
        print(f'backup: {cache} -> {destination}')
    if old_bundle.exists() and not bundled.exists():
        bundled.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(old_bundle, bundled)
        print(f'moved bundle: {old_bundle} -> {bundled}')
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
            retire(destination, cfg)
        temporary.replace(destination)
        print(f'deployed: {destination}')
    for path in obsolete:
        retire(path, cfg)
    write(target, config)
    if (cfg / 'opencode.jsonc').exists():
        (cfg / 'opencode.jsonc').rename(cfg / ('opencode.jsonc.migrated-' + STAMP + '.bak'))
    write(cli_path, cli)
    if cli_path.name == 'tui.json' and (cfg / 'tui.jsonc').exists():
        (cfg / 'tui.jsonc').rename(cfg / ('tui.jsonc.migrated-' + STAMP + '.bak'))
        print('prepared: tui.json（原 JSONC 已备份）')
    print(f'OpenCode v{major} 插件已部署；未启动宿主、未迁移数据库')


if __name__ == '__main__':
    try:
        install(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]),
                '--check' in sys.argv[4:], '--refresh-magic-context' in sys.argv[4:],
                '--refresh-ponytail' in sys.argv[4:])
        if '--versions' in sys.argv[4:]:
            plugin_versions(Path(sys.argv[2]), int(sys.argv[3]), Path(sys.argv[sys.argv.index('--versions') + 1]))
    except Exception as error:
        sys.exit(f'ERROR: {error}')
