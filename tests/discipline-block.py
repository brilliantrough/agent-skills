import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

checker = Path(__file__).resolve().parents[1] / 'skills/base/discipline/scripts/check_block.py'
start, end = ('<!-- user-discipline:' + x + ' -->\n' for x in ('start', 'end'))
rule = '### D-001 数据保护\n'
block = start + rule + end
with TemporaryDirectory() as tmp:
    p = Path(tmp) / 'AGENTS.md'
    def run():
        return subprocess.run([sys.executable, checker, p], capture_output=True).returncode

    assert run() == 0 and not p.exists()
    for text, expected in [('正文\n', 0), ('```md\n' + block + '```\n' + block, 0),
                           ('\n    ' + start, 0), ('```D-001``` is a rule identifier.\n\n' + end, 1),
                           (end + start, 1), (block + block, 1), (start, 1),
                           (start + rule + rule + end, 1)]:
        p.write_bytes(text.encode())
        assert run() == expected and p.read_bytes() == text.encode()
print('PASS: 纪律块检查接受可选块，拒绝错序、残缺、重复块和重复编号')
