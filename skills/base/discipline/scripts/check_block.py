"""Check standalone discipline markers and rule IDs, without editing AGENTS.md."""
from pathlib import Path
import re
import sys


def check(path):
    if not path.exists():
        return
    opened = closed = False
    ids = set()
    fence = ''
    for n, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        text = line.expandtabs(4).rstrip()
        if text.startswith('    '):  # Indented Markdown examples are not top-level markers.
            continue
        text = text.lstrip(' ')
        if fence:
            if text.startswith(fence) and not text.strip(fence[0]):
                fence = ''
            continue
        match = re.match(r'(`{3,}|~{3,})', text)
        if match and not (match[1][0] == '`' and '`' in text[match.end():]):
            fence = match[1]
        elif text == '<!-- user-discipline:start -->':
            if opened or closed:
                sys.exit(f'{path}:{n}: 重复的纪律块起点')
            opened = True
        elif text == '<!-- user-discipline:end -->':
            if not opened:
                sys.exit(f'{path}:{n}: 纪律块终点没有对应起点')
            opened, closed = False, True
        elif opened:
            match = re.match(r'###\s+(D-\d+)\b', text)
            if match:
                if match[1] in ids:
                    sys.exit(f'{path}:{n}: 重复纪律编号 {match[1]}')
                ids.add(match[1])
    if opened:
        sys.exit(f'{path}: 纪律块缺少终点')


if __name__ == '__main__':
    check(Path(sys.argv[1]) if len(sys.argv) > 1 else Path('AGENTS.md'))
