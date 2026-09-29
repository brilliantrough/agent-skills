#!/usr/bin/env python3
"""Check the real context-mode messages with macOS Bash 3.2 + UTF-8.

Run: python3 tests/pi-setup-shell-messages.py
Only echo lines are executed; no installation or configuration changes.
"""
import os
from pathlib import Path
import subprocess

script = (Path(__file__).resolve().parent.parent / "pi-setup.sh").read_text(encoding="utf-8")
cases = (
    ('echo "已登记:', "CM_DIR", "/tmp/context-mode", "stdout"),
    ('echo "WARN: 下载/解包发布包失败', "CM_URL", "https://example.com/vendor.tar.gz", "stderr"),
)
for prefix, variable, value, stream in cases:
    lines = [line.strip() for line in script.splitlines() if line.strip().startswith(prefix)]
    assert len(lines) == 1, (prefix, lines)
    for locale in ("C", "zh_CN.UTF-8"):
        result = subprocess.run(
            ["/bin/bash", "-euc", lines[0]],
            env={**os.environ, "LC_ALL": locale, variable: value},
            capture_output=True,
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert value.encode() in getattr(result, stream), result
print("PASS: context-mode success/failure messages expand under C and UTF-8 locales")
