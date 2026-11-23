"""Verify that each independent memory budget can fail a project check."""
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

checker = Path(__file__).resolve().parents[1] / 'skills/base/save-mem/scripts/check_size.py'
with TemporaryDirectory() as tmp:
    docs = Path(tmp) / 'docs'
    def run():
        return subprocess.run([sys.executable, checker, docs], capture_output=True, text=True)

    assert run().returncode == 0 and not docs.exists()
    folder = docs / 'project_memory'
    folder.mkdir(parents=True)
    p = folder / 'journal.sdoc'
    entry = '[TEXT]\nSTATEMENT: >>>\n[TEXT]\n%s\n<<<\n'
    p.write_text(entry % '结论', encoding='utf-8')
    result = run()
    assert result.returncode == 0 and '1 条' in result.stdout
    for text, reason in [('TITLE: Marker: >>>\n' + entry % ('字' * 700), '640'), ((entry % '') * 129, '128'), (' ' * 49153, '48 KiB')]:
        p.write_text(text, encoding='utf-8')
        result = run()
        assert result.returncode == 1 and reason in result.stderr
print('PASS: 记忆体量检查覆盖空项目、正文内标记和三个独立上限')
