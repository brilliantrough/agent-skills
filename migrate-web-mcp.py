#!/usr/bin/env python3
"""deprecated: mcphub-web-rename；用户确认退役后删除本文件和两个 setup 调用段。"""
import argparse
import json
import re
import shutil
import tempfile
from datetime import datetime
from pathlib import Path

OLD, NEW = 'mcphub-web', 'web'


def combine(old, new):
    """只合并相同值、缺失字段和占位符，不覆盖两份不同的实值。"""
    if old == new:
        return old
    if isinstance(old, dict) and isinstance(new, dict):
        result = dict(old)
        for key, value in new.items():
            result[key] = combine(old[key], value) if key in old else value
        return result
    for candidate, replacement in ((old, new), (new, old)):
        if isinstance(candidate, str) and re.search(r'<[A-Za-z][A-Za-z0-9 _-]*>', candidate):
            return replacement
    raise ValueError('mcphub-web 与 web 有不同的实值；保留原配置，请手工选择后重跑')


def migrate(path, host):
    text = path.read_text(encoding='utf-8')
    string = r'"(?:\\.|[^"\\])*"'
    clean = re.sub(f'({string})|//[^\n]*|/\\*[\\s\\S]*?\\*/', lambda m: m[1] or '', text)
    clean = re.sub(f'({string})|,(\\s*[}}\\]])', lambda m: m[1] or m[2], clean)
    config = json.loads(clean)
    servers = config.get('mcpServers' if host == 'pi' else 'mcp', {})
    groups = [servers]
    if host == 'opencode' and isinstance(servers.get('servers'), dict):
        groups.append(servers['servers'])
    changed = False
    for group in groups:
        if OLD not in group:
            continue
        group[NEW] = combine(group[OLD], group[NEW]) if NEW in group else group[OLD]
        del group[OLD]
        changed = True
    return config if changed else None


def main():
    parser = argparse.ArgumentParser(description='MCP mcphub-web → web；默认预览，--apply 备份后写入')
    parser.add_argument('host', choices=['opencode', 'pi'])
    parser.add_argument('paths', nargs='+', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    pending = []
    for path in dict.fromkeys(path.resolve() for path in args.paths):
        if not path.exists():
            continue
        config = migrate(path, args.host)
        if config is not None:
            pending.append((path, config))
    # 先检查所有文件，再写入；解析失败或名称冲突时不做部分迁移。
    for path, config in pending:
        print(f'migrate: {path}: {OLD} → {NEW}' + ('' if args.apply else '（预览，未写入）'))
        if not args.apply:
            continue
        backup = path.with_name(path.name + '.bak-web-' + datetime.now().strftime('%Y%m%d%H%M%S%f'))
        shutil.copy2(path, backup)
        temp = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as f:
                temp = Path(f.name)
                json.dump(config, f, ensure_ascii=False, indent=2)
                f.write('\n')
            temp.replace(path)
        finally:
            if temp is not None:
                temp.unlink(missing_ok=True)
        print(f'backup: {backup}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, TypeError, AttributeError) as error:
        raise SystemExit(f'WARN: web MCP 迁移未完成：{error}') from error
