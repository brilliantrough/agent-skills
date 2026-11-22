#!/usr/bin/env python3
"""Verification 入口自身的回归：SKIP 必须可见，静默成功不算 PASS。"""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / "scripts/check.sh"


def run(cmd, *, env=None):
    return subprocess.run(cmd, cwd=ROOT, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=180, check=False)


def main():
    with tempfile.TemporaryDirectory(prefix="check-gate-") as td:
        tmp = Path(td)
        fake_bin = tmp / "bin"
        fake_bin.mkdir()
        fake_python = fake_bin / "python3"
        fake_python.write_text(
            "#!/usr/bin/env bash\n"
            "for arg in \"$@\"; do\n"
            "  if [ \"$arg\" = tests/setup-preflight.py ]; then\n"
            "    echo 'SKIP: simulated Windows prerequisite'\n"
            "    exit 0\n"
            "  fi\n"
            "done\n"
            "exec \"$REAL_PYTHON\" \"$@\"\n",
            encoding="utf-8",
        )
        fake_python.chmod(0o755)
        env = os.environ.copy()
        env.update({
            "PATH": f"{fake_bin}{os.pathsep}{env['PATH']}",
            "REAL_PYTHON": sys.executable,
            "HOME": str(tmp / "home"),
            "XDG_CACHE_HOME": str(tmp / "cache"),
            "PYTHONPYCACHEPREFIX": str(tmp / "pycache"),
            "NODE_DISABLE_COMPILE_CACHE": "1",
        })
        result = run(["bash", "scripts/check.sh"], env=env)
        assert result.returncode == 0, result.stdout
        assert "SKIP setup-preflight.py: simulated Windows prerequisite" in result.stdout, result.stdout
        assert "PASS: 公开体检通过，但 1 项因缺前置条件 SKIP" in result.stdout, result.stdout

        source = CHECK.read_text(encoding="utf-8")
        match = re.search(r"^  t_run\(\) \{.*?^  \}", source, re.M | re.S)
        assert match, "生产 check.sh 中找不到 t_run"
        harness = tmp / "t-run.sh"
        harness.write_text(
            "set -uo pipefail\n"
            "fail=0\nskipped=0\n"
            "t_fail() { printf '   FAIL %s: %s\\n' \"$1\" \"$2\"; fail=1; }\n"
            "t_skip() { printf '   SKIP %s: %s\\n' \"$1\" \"$2\"; skipped=$((skipped + 1)); }\n"
            f"{match.group(0)}\n"
            "t_run quiet-noop python3 -c 'pass'\n"
            "exit \"$fail\"\n",
            encoding="utf-8",
        )
        result = run(["bash", str(harness)], env=env)
        assert result.returncode == 1, result.stdout
        assert "FAIL quiet-noop: 退出 0 但未输出 PASS" in result.stdout, result.stdout

    print("PASS: preflight SKIP 进入公开摘要，静默 noop 测试判 FAIL")


if __name__ == "__main__":
    main()
