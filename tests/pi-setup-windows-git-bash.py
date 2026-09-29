#!/usr/bin/env python3
"""隔离 HOME 的 Pi Git Bash 回归;不下载/安装包,不改真实用户配置。
运行: python tests/pi-setup-windows-git-bash.py
可选 BASH 指定 Git Bash,BUN_TEST_BIN 指定真实 bun.exe 做运行时测试。
"""

import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


def extract(pattern, text, group=1):
    match = re.search(pattern, text, re.DOTALL)
    assert match is not None, f"在安装脚本中找不到测试锚点: {pattern}"
    return match.group(group)


ROOT = pathlib.Path(__file__).resolve().parent.parent
TEXT = (ROOT / "pi-setup.sh").read_text(encoding="utf-8")
FUNCTION = extract(r"ensure_git_bash_startup\(\) \{\n.*?\n\}", TEXT, 0)
BODY = extract(r"<<'PY_GIT_BASH'\n(.*?)\nPY_GIT_BASH", FUNCTION)
BASH = os.environ.get("BASH") or shutil.which("bash")
assert BASH, "需要 Bash;Windows 请在 Git Bash 中运行或指定 BASH"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")


def run(args, env=None, ok=True):
    p = subprocess.run(
        args,
        env=env or ENV,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        check=False,
    )
    if ok:
        assert p.returncode == 0, (args[0], p.returncode, p.stdout, p.stderr)
    return p


def posix(p):
    if os.name == "nt":
        return run(
            [BASH, "--noprofile", "--norc", "-c", 'cygpath -u "$1"', "--", str(p)]
        ).stdout.strip()
    return str(p)


def configure(home, bindir, terminal="mintty", ok=True):
    return run([sys.executable, "-c", BODY, str(home), bindir, terminal], ok=ok)


def snapshot(home):
    return {
        p.name: (p.read_bytes(), p.stat().st_mtime_ns)
        for p in home.iterdir()
        if p.is_file()
    }


def shell(home, command, mode="-lc"):
    # 排除父终端已有的 Bun PATH,避免未写启动文件也误判成功。
    env = dict(ENV, HOME=posix(home), PATH="/usr/bin:/bin", MSYS2_PATH_TYPE="strict")
    for key in ("BASH_ENV", "ENV", "BUN_INSTALL", "__agent_skills_bashrc_loaded"):
        env.pop(key, None)
    return run([BASH, mode, command], env=env).stdout.strip()


def main():
    if os.name == "nt":
        kernel = run([BASH, "-c", "uname -s"]).stdout
        assert any(s in kernel for s in ("MINGW", "MSYS", "CYGWIN")), (
            "Windows 测试不能误用 WSL bash"
        )
    with tempfile.TemporaryDirectory(prefix="agent-skills Windows ") as tmp:
        root = pathlib.Path(tmp)
        bindir = root / "Bun 中文 ' $ space" / "bin"
        bindir.mkdir(parents=True)
        probe = bindir / "agent_skills_probe"
        probe.write_text("#!/usr/bin/env bash\necho probe-ok\n", encoding="utf-8")
        probe.chmod(0o755)
        bp = posix(bindir)

        fresh = root / "fresh home"
        fresh.mkdir()
        configure(fresh, bp)
        assert (fresh / ".bash_profile").exists()
        assert "CtrlShiftShortcuts=yes" in (fresh / ".minttyrc").read_text()
        for mode in ("-lc", "-ic"):
            assert "probe-ok" in shell(fresh, "agent_skills_probe", mode)
        path = shell(fresh, '. "$HOME/.bashrc"; . "$HOME/.bashrc"; printf %s "$PATH"')
        assert path.split(":").count(bp) == 1, path
        before = snapshot(fresh)
        configure(fresh, bp)
        assert snapshot(fresh) == before, "重复配置不得重写文件/新增备份"
        print(
            "PASS fresh HOME: login + interactive shells, quoted/Unicode path, PATH dedup, idempotence"
        )

        for login in (".profile", ".bash_login", ".bash_profile"):
            home = root / login[1:]
            home.mkdir()
            rc = 'RC_COUNT=$(( ${RC_COUNT:-0} + 1 ))\nalias keep_me="echo retained"\n'
            profile = 'KEEP_PROFILE=yes\n. "$HOME/.bashrc"\n'
            (home / ".bashrc").write_text(rc)
            (home / login).write_text(profile)
            mintty = (
                "CtrlShiftShortcuts=no\r\nCopyOnSelect=no\r\nKeyFunctions=C+V:paste\r\n"
            )
            (home / ".minttyrc").write_bytes(mintty.encode())
            configure(home, bp)
            assert (home / ".bashrc").read_text().startswith(rc)
            assert (home / login).read_text().startswith(profile)
            assert (home / ".minttyrc").read_bytes() == mintty.encode()
            assert any(p.read_text() == rc for p in home.glob(".bashrc.bak-*"))
            assert any(p.read_text() == profile for p in home.glob(login + ".bak-*"))
            if login != ".bash_profile":
                assert not (home / ".bash_profile").exists(), "不能遮蔽原有登录文件"
            assert shell(home, 'printf "%s:%s" "$KEEP_PROFILE" "$RC_COUNT"') == "yes:1"
            before = snapshot(home)
            configure(home, bp)
            assert snapshot(home) == before
        print(
            "PASS existing profiles: original bytes/explicit mintty choices, backups, no double source"
        )

        home = root / "non-mintty"
        home.mkdir()
        configure(home, bp, "vscode")
        assert not (home / ".minttyrc").exists()
        home = root / "exchange"
        home.mkdir()
        (home / ".minttyrc").write_text("CtrlExchangeShift=yes\n")
        configure(home, bp)
        assert "CtrlShiftShortcuts=" not in (home / ".minttyrc").read_text()
        print(
            "PASS other terminals untouched; CtrlExchangeShift does not gain dangerous shortcuts"
        )

        home = root / "broken"
        home.mkdir()
        (home / ".bashrc").write_text("# >>> agent-skills Bun PATH >>>\nkeep this\n")
        before = snapshot(home)
        assert configure(home, bp, ok=False).returncode != 0
        assert snapshot(home) == before
        # Windows 可能未开开发者模式;不借助 ln 的拷贝退化伪装成 symlink 测试。
        home = root / "symlink"
        home.mkdir()
        target = root / "outside"
        target.write_text("unchanged\n")
        try:
            (home / ".bashrc").symlink_to(target)
        except OSError as e:
            print(f"SKIP native symlink creation unavailable: {e.__class__.__name__}")
        else:
            assert configure(home, bp, ok=False).returncode != 0
            assert target.read_text() == "unchanged\n"
            assert not (home / ".bash_profile").exists()
        print("PASS malformed managed block fails before any write")

        for platform, answer in (("0", "0"), ("1", "1")):
            home = root / f"skip-{platform}"
            home.mkdir()
            cmd = f"IS_WIN={platform}; ask() {{ return {answer}; }};\n{FUNCTION}\nensure_git_bash_startup"
            run(
                [BASH, "--noprofile", "--norc", "-c", cmd],
                env=dict(ENV, HOME=posix(home)),
            )
            assert not list(home.iterdir())
        print("PASS Linux/WSL guard and declined confirmation perform no writes")

        bad = root / "broken Bun"
        bad.mkdir()
        executable = bad / "bun"
        executable.write_bytes(
            b'#!/usr/bin/env bash\nif [ "$1" = --version ]; then echo fake; else exit 42; fi\n'
        )
        executable.chmod(0o755)
        home = root / "failed-pi"
        home.mkdir()
        runtime = extract(r'BUN_BIN="\$\(command -v bun.*?\nfi\n', TEXT, 0)
        p = run(
            [BASH, "--noprofile", "--norc", "-ec", "BIN_EXT=;\n" + runtime],
            env=dict(ENV, HOME=posix(home), PATH=posix(bad) + ":/usr/bin:/bin"),
            ok=False,
        )
        assert p.returncode != 0 and "ERROR: Bun" in p.stderr
        assert not list(home.iterdir())
        print("PASS Pi: broken bun:sqlite fails before startup configuration")

        real_bun = os.environ.get("BUN_TEST_BIN")
        if real_bun:
            # 同卷 hardlink 只执行不改二进制;不支持时复制,绝不改真实配置目录。
            binary = bindir / ("bun.exe" if os.name == "nt" else "bun")
            try:
                os.link(real_bun, binary)
            except OSError:
                shutil.copy2(real_bun, binary)
            home = root / "pi"
            home.mkdir()
            runtime = extract(
                r'if \[ "\$IS_WIN" = 1 \] && \[ -n "\$\{BUN_INSTALL:-\}" \]; then\n.*?\nBUN_BIN="\$\(command -v bun.*?\nfi\n',
                TEXT,
                0,
            )
            # 使用真正的发现/验证/helper及cygpath;禁止测试期间意外下载。
            platform = "1" if os.name == "nt" else "0"
            npath = 'cygpath -m "$1"' if os.name == "nt" else 'printf %s "$1"'
            cmd = (
                f"IS_WIN={platform}; BIN_EXT={shlex.quote(binary.suffix)}; ask() {{ return 0; }}; "
                f'npath() {{ {npath}; }}; python3() {{ {shlex.quote(sys.executable)} "$@"; }};\n'
                "curl() { echo unexpected-download >&2; return 99; };\n"
                + FUNCTION
                + "\n"
                + runtime
            )
            env = dict(
                ENV,
                HOME=posix(home),
                PATH="/usr/bin:/bin",
                BUN_INSTALL=str(bindir.parent),
                TERM_PROGRAM="mintty",
            )
            runner = root / "bun-case.sh"
            runner.write_bytes(cmd.encode("utf-8"))
            run([BASH, "--noprofile", "--norc", "-eu", posix(runner)], env=env)
            if os.name == "nt":
                assert (home / ".bashrc").exists()
                assert shell(home, "bun -e 'console.log(\"runtime-ok\")'").endswith(
                    "runtime-ok"
                )
            # 原生宿主无需 bash 也能启动带空格路径的 Windows 可执行文件。
            assert (
                run([str(binary), "-e", 'console.log("native-ok")']).stdout.strip()
                == "native-ok"
            )
            print("PASS Pi: real Bun + bun:sqlite + MSYS paths + native spawn")
        else:
            print("SKIP real Bun smoke test: set BUN_TEST_BIN to enable")

        # 调用完整 merge_cfg(仅 curl 替换为本地模板),覆盖首次写入和重跑路径。
        merge = extract(r"merge_cfg\(\) \{\n.*?\n\}", TEXT, 0)
        fixture = root / "template.json"
        fixture.write_text(json.dumps({"tuiMode": "fullscreen", "defaultModel": "new"}))
        for platform, terminal, initial, expected in (
            ("1", "mintty", None, "regular"),
            ("1", "vscode", None, "fullscreen"),
            ("0", "mintty", None, "fullscreen"),
            ("1", "mintty", "regular", "regular"),
            ("1", "mintty", "fullscreen", "fullscreen"),
        ):
            home = root / f"mode-{platform}-{terminal}-{initial}"
            home.mkdir()
            dest = home / "settings.json"
            if initial:
                dest.write_text(json.dumps({"tuiMode": initial, "defaultModel": "old"}))
            cmd = (
                f'IS_WIN={platform}; SETTINGS="$HOME/settings.json";\n'
                "GW_BASE= K_CLAUDE= K_CODEX= K_ANTHROPIC= K_EMBED= K_MEM= MCPHUB_HOST=;\n"
                f'python3() {{ {shlex.quote(sys.executable)} "$@"; }};\n'
                "ask() { return 0; }; fill_template_placeholders() { :; };\n"
                'curl() { while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then cp "$FIXTURE" "$2"; return; fi; shift; done; return 1; };\n'
                + merge
                + '\nmerge_cfg fixture "$SETTINGS"\n'
            )
            env = dict(
                ENV, HOME=posix(home), TERM_PROGRAM=terminal, FIXTURE=posix(fixture)
            )
            runner = root / "merge-case.sh"
            runner.write_bytes(cmd.encode("utf-8"))
            run([BASH, "--noprofile", "--norc", "-eu", posix(runner)], env=env)
            assert json.loads(dest.read_text()) == {
                "tuiMode": expected,
                "defaultModel": "new",
            }
            before = snapshot(home)
            run([BASH, "--noprofile", "--norc", "-eu", posix(runner)], env=env)
            assert snapshot(home) == before
        print(
            "PASS full Pi merge: mintty-only first default, both explicit modes preserved, idempotence"
        )
    print("PASS Pi Windows Git Bash isolated regression checks")


if __name__ == "__main__":
    main()
