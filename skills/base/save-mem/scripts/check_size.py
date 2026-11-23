"""Read-only size check for the suite's StrictDoc memory directories."""
import re
import sys
from pathlib import Path


def check(docs):
    size = count = 0
    errors = []
    for folder in ('project_memory', 'handbook'):
        for path in sorted((docs / folder).rglob('*.sdoc')):
            data = path.read_bytes()
            size += len(data)
            start = None
            multiline = False
            lines = data.decode('utf-8-sig').splitlines()
            for number, line in enumerate([*lines, None], 1):
                if multiline and line is not None:
                    multiline = line != '<<<'
                elif line is None or re.fullmatch(r'\[{1,2}/?[A-Z][A-Z0-9_]*\]{1,2}', line):
                    if start is not None:
                        length = len('\n'.join(lines[start - 1:number - 1]).rstrip())
                        limit = 640 if folder == 'project_memory' else 1200
                        if length > limit:
                            errors.append(f'{path}:{start}: 条目 {length} 字符，上限 {limit}')
                    start = None
                    if line and line.strip('[]') not in ('DOCUMENT', 'GRAMMAR', 'SECTION') and not line.strip('[]').startswith('/'):
                        start = number
                        count += 1
                elif re.fullmatch(r'[A-Z][A-Z0-9_]*: >>>', line):
                    multiline = True
    if size > 48 * 1024:
        errors.append(f'记忆源文件共 {size} 字节，上限 48 KiB')
    if count > 128:
        errors.append(f'共 {count} 条，上限 128 条')
    for error in errors:
        print(error, file=sys.stderr)
    print(f'StrictDoc 记忆：{count} 条，{size} 字节')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(check(Path(sys.argv[1]) if len(sys.argv) > 1 else Path('docs')))
