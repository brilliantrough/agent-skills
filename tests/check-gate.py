#!/usr/bin/env python3
"""Verification 入口自身的回归：SKIP 必须可见，静默成功不算 PASS。"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
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
            "PYTHONOPTIMIZE": "1",
        })
        result = run(["bash", "scripts/check.sh"], env=env)
        assert result.returncode == 0, result.stdout
        assert "SKIP setup-preflight.py: simulated Windows prerequisite" in result.stdout, result.stdout
        assert "PASS: 公开体检通过，但 1 项因缺前置条件 SKIP" in result.stdout, result.stdout
        assert "PASS 自研外置退役" in result.stdout, "快速 check.sh 未执行退役静态契约"
        asset_suffix = "且已入库" if os.path.lexists(ROOT / ".git") else "（非 Git 树，未核对入库）"
        assert f"PASS 入口与 Verification 资产存在{asset_suffix}" in result.stdout, result.stdout
        assert "PASS 本仓源码无 raw／archive／codeload 旁路" in result.stdout, "快速 check.sh 未执行取源闭包"

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

        # 静态契约在隔离副本中必须能抓回退；夹具不得继承或污染调用者的 Git 仓库选择。
        static_root = tmp / "static-repo"
        static_test = static_root / "tests/source-bench.py"
        static_test.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "tests/source-bench.py", static_test)
        fixture_env = os.environ.copy()
        fixture_env["GIT_INDEX_FILE"] = str(tmp / "caller-index-must-stay-absent")
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_PREFIX", "GIT_CONFIG"):
            fixture_env.pop(key, None)
        fixture_env["PYTHONOPTIMIZE"] = "0"

        def run_static(mode="--static-contract", root=static_root, env=fixture_env):
            return run([sys.executable, str(root / "tests/source-bench.py"), mode], env=env)

        def git_fixture(*args):
            subprocess.run(["git", *args], cwd=static_root, env=fixture_env, check=True,
                           stdout=subprocess.DEVNULL)

        def write_fixture(name, text="fixture\n"):
            target = static_root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")

        for name in (
            "pi/extensions/context-rewrite.ts", "opencode/v2/context-rewrite.js",
            "opencode/plugins/context-rewrite.js", "dsh/index.mjs",
            "context-mode/fork-patches.mjs", "context-mode/release.mjs", "context-mode/guidance.md",
        ):
            target = static_root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        result = run_static("--context-output-static")
        assert result.returncode == 0, result.stdout
        with (static_root / "pi/extensions/context-rewrite.ts").open("a", encoding="utf-8") as f:
            f.write("\n// context_output_read\n")
        result = run_static("--context-output-static")
        assert result.returncode != 0 and "仍引用退役外置" in result.stdout, result.stdout

        # 引号路径合法；普通未跟踪、add -N 和 PYTHONOPTIMIZE 都不能冒充已入库。
        shutil.copy2(ROOT / "pi/extensions/context-rewrite.ts", static_root / "pi/extensions/context-rewrite.ts")
        write_fixture("scripts/check.sh", "  t_case \"tests/formal.mjs\" \"$why\" node tests/formal.mjs\n")
        required = [
            "setup.sh", "scripts/update-hosts.sh",
            "scripts/check.sh", "scripts/verify-subagents.sh", "tests/setup-preflight.py",
            "tests/nju-ppt-editability.py", "skills/base/verification/SKILL.md",
            "skills/base/save-mem/scripts/check_size.py",
            "skills/base/discipline/scripts/check_block.py",
            "scripts/link-mem-search.mjs", "scripts/migrate-agents-tail.py",
            "skills/base/verification/references/reviewer.md", "dsh/verification-policy.mjs",
            "skills/base/trust-pyramid/references/pstack.md",
            "skills/base/multi-agent/SKILL.md",
            "skills/base/multi-agent/references/guide.md",
            "skills/base/deepseek-efficiency/SKILL.md",
        ]
        for name in required:
            if name != "scripts/check.sh":
                if (ROOT / name).is_file():
                    target = static_root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(ROOT / name, target)
                else:
                    write_fixture(name)
        write_fixture("tests/formal.mjs", "")
        for name in ("pi-setup.sh", "opencode-setup.sh", "codex-setup.sh", "dsh-setup.sh",
                     "skills-sync.sh", "modules/run.sh", "modules/codegraph/setup.sh"):
            target = static_root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        git_fixture("init", "-q")
        git_fixture("add", "--", *required)
        result = run_static()
        assert result.returncode != 0 and "tests/formal.mjs 未入库" in result.stdout, result.stdout
        optimized_env = fixture_env.copy()
        optimized_env["PYTHONOPTIMIZE"] = "1"
        result = run_static(env=optimized_env)
        assert result.returncode != 0 and "tests/formal.mjs 未入库" in result.stdout, result.stdout
        git_fixture("add", "-N", "--", "tests/formal.mjs")
        result = run_static()
        assert result.returncode != 0 and "tests/formal.mjs 未入库" in result.stdout, result.stdout
        git_fixture("add", "--", "tests/formal.mjs")
        result = run_static()
        assert result.returncode == 0, result.stdout

        # 完整仓名判定：第三方与 Release 合法，本仓 raw／archive／codeload 一律失败。
        allowed = (
            "# https://raw.githubusercontent.com/example/agent-skills-extra/main/x.sh\n"
            "# https://codeload.github.com/example/other/tar.gz\n"
            "# https://github.com/example/agent-skills/releases/download/v1/x.tar.gz\n"
            "# https://github.com/example/agent-skills.git\n"
        )
        write_fixture("modules/codegraph/setup.sh", allowed)
        result = run_static()
        assert result.returncode == 0, result.stdout
        for name, url in (
            ("modules/codegraph/setup.sh", "https://raw.githubusercontent.com/example/agent-skills/main/x.sh"),
            ("modules/run.sh", "https://github.com/example/agent-skills/archive/refs/tags/v1.tar.gz"),
            ("modules/run.sh", "https://codeload.github.com/example/agent-skills/tar.gz/refs/heads/main"),
        ):
            write_fixture(name, f"# {url}\n")
            result = run_static()
            assert result.returncode != 0 and "旁路" in result.stdout, (url, result.stdout)
        write_fixture("modules/run.sh")
        write_fixture("modules/codegraph/setup.sh")

        # 无自身 .git 的源码包合法，即使位于无关父仓库；损坏的自身索引必须显式失败。
        unrelated = tmp / "unrelated"
        unrelated.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=unrelated, env=fixture_env, check=True)
        nogit_root = unrelated / "package"
        shutil.copytree(static_root, nogit_root, ignore=shutil.ignore_patterns(".git"))
        result = run_static(root=nogit_root)
        assert result.returncode == 0 and "非 Git 树，未核对入库" in result.stdout, result.stdout
        (static_root / ".git/index").write_bytes(b"broken-index")
        result = run_static()
        assert result.returncode != 0 and "索引读取失败" in result.stdout, result.stdout
        assert not (tmp / "caller-index-must-stay-absent").exists(), "夹具污染了调用者指定的 Git 索引"

    print("PASS: preflight SKIP、静默 noop、退役回退、资产／取源闭包及 Git 隔离均被门禁捕获")


if __name__ == "__main__":
    main()
