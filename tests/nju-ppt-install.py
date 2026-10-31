#!/usr/bin/env python3
"""Isolated installer branch checks with a local main-tarball fixture; no real HOME or downloads."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("BASH") or shutil.which("bash")
assert BASH, "需要 Bash；Windows请指定Git Bash而不是WSL"


def run(args, env=None):
    return subprocess.run(args, env=env, capture_output=True, encoding="utf-8", errors="replace", timeout=90)


def posix(path):
    if os.name == "nt":
        p = run([BASH, "--noprofile", "--norc", "-c", 'cygpath -u "$1"', "--", str(path)])
        assert p.returncode == 0, p.stderr
        return p.stdout.strip()
    return str(path)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    path.chmod(0o755)


def archive(target, source):
    with tarfile.open(target, "w:gz") as t:
        t.add(source, arcname="agent-skills-main", filter=lambda m: None if "__pycache__" in m.name else m)


def external_checks(tmp, env):
    home = tmp / "external HOME"
    shared = home / ".agents/skills"
    sources = {
        "ui-ux-pro-max": "nextlevelbuilder/ui-ux-pro-max-skill",
        "huashu-design": "alchaincyf/huashu-design",
        "design-taste-frontend": "Leonxlnx/taste-skill",
        "redesign-existing-projects": "Leonxlnx/taste-skill",
        "nju-ppt": "old/local-lock-entry",
    }
    for name in sources:
        write(shared / name / "SKILL.md", "fixture\n")
    lock = home / ".agents/.skill-lock.json"
    lock.write_text(json.dumps({"skills": {n: {"source": s} for n, s in sources.items()}}))
    calls = tmp / "npx.log"
    write(tmp / "bin/npx", '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$NPX_LOG"\n')
    e = dict(env, HOME=posix(home), USERPROFILE=str(home), NPX_LOG=posix(calls))

    def check(*args):
        p = run([
            BASH, "--noprofile", "--norc", "-c",
            'export PATH="$FIXTURE_BIN:$PATH"; '
            '[ "$(command -v npx)" = "$FIXTURE_BIN/npx" ] || exit 99; '
            'exec bash "$@"', "--", str(ROOT / "skills-external.sh"), *args,
        ], e)
        text = calls.read_text() if calls.exists() else ""
        return p, text

    p, text = check()
    assert p.returncode == 0 and "ppt-master" not in text, (p.stdout, p.stderr, text)
    assert "nju-ppt" not in text, "本仓ppt条目不得交给第三方更新"
    assert "redesign-existing-projects" not in text, "上游已移除的skill不再代装或代更新"
    assert not (shared / "redesign-existing-projects").exists(), "沿用上游迁移已登记旧副本"
    write(shared / "redesign-existing-projects/SKILL.md", "unregistered local copy\n")
    calls.unlink(missing_ok=True)
    p, text = check("--ppt")
    assert p.returncode == 0, p.stderr
    assert "add hugohe3/ppt-master --skill ppt-master -g -y --agent pi" in text, text
    assert (shared / "redesign-existing-projects/SKILL.md").read_text() == "unregistered local copy\n"
    calls.unlink(missing_ok=True)
    e["SKILLS_EXTERNAL"] = "skip"
    p, text = check("--ppt")
    assert p.returncode == 0 and "add hugohe3/ppt-master --skill ppt-master" in text, (p.stderr, text)
    assert "add nextlevelbuilder" not in text and "add alchaincyf" not in text
    calls.unlink(missing_ok=True)
    e.pop("SKILLS_EXTERNAL")
    write(shared / "ppt-master/SKILL.md", "local custom engine\n")
    p, text = check("--ppt")
    assert p.returncode != 0 and "ppt-master" in p.stderr and "ppt-master" not in text
    assert (shared / "ppt-master/SKILL.md").read_text() == "local custom engine\n"
    print("PASS real external script: precise optional engine add, own-name exclusion, local-source conflict preserved")


def main():
    with tempfile.TemporaryDirectory(prefix="nju install 中文 ") as tmp:
        tmp = Path(tmp)
        source = tmp / "fixture"
        for entry in (ROOT / "skills").glob("*/*/SKILL.md"):
            dest = source / entry.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(entry, dest)
        shutil.copytree(
            ROOT / "skills/ppt/nju-ppt", source / "skills/ppt/nju-ppt",
            dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"),
        )
        write(source / "skills-external.sh", '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$EXTERNAL_LOG"\n')
        package = tmp / "main.tgz"
        archive(package, source)
        bindir = tmp / "bin"
        write(bindir / "curl", '''#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out="$2"; shift 2; else shift; fi
done
cp "$FIXTURE_ARCHIVE" "$out"
''')
        write(bindir / "fixture-python", '''#!/usr/bin/env bash
if [ "$1" = -c ]; then exit 0; fi
printf '%s\\n' "$*" >> "$PREPARE_LOG"
exit "${PREPARE_EXIT:-0}"
''')
        env = dict(os.environ)
        env.update({
            "FIXTURE_ARCHIVE": posix(package), "EXTERNAL_LOG": posix(tmp / "external.log"),
            "PREPARE_LOG": posix(tmp / "prepare.log"),
            "FIXTURE_BIN": posix(bindir),
            "NJU_PPT_PYTHON": posix(bindir / "fixture-python"),
        })
        for name in ["BASH_ENV", "ENV"]:
            env.pop(name, None)

        def install(home, *groups, success=True, extra=None):
            home.mkdir(exist_ok=True)
            e = dict(env, HOME=posix(home), USERPROFILE=str(home))
            e.update(extra or {})
            p = run([
                BASH, "--noprofile", "--norc", "-c",
                'export PATH="$FIXTURE_BIN:$PATH"; '
                '[ "$(command -v curl)" = "$FIXTURE_BIN/curl" ] || exit 99; '
                'exec bash "$@"', "--", str(ROOT / "skills-sync.sh"), *groups,
            ], e)
            assert (p.returncode == 0) == success, (groups, p.returncode, p.stdout[-2500:], p.stderr)
            return p

        base = tmp / "base HOME"
        install(base, "base")
        assert (base / ".agents/skills/steady-do/SKILL.md").exists()
        assert not (base / ".agents/skills/nju-ppt").exists()
        assert not (tmp / "prepare.log").exists()
        print("PASS base: no PPT files or environment preparation")

        home = tmp / "PPT 独立 HOME"
        install(home, "ppt")
        skill = home / ".agents/skills/nju-ppt"
        assert len(list((skill / "assets/nju-academic-ginkgo/templates").glob("*.svg"))) == 11
        assert not (home / ".agents/skills/steady-do").exists()
        assert "--ppt" in (tmp / "external.log").read_text()
        assert "--home" in (tmp / "prepare.log").read_text()
        branch_home = tmp / "branch HOME"
        branch_result = install(branch_home, "ppt", extra={"AGENT_SKILLS_REF": "feat/nju-ppt-optional"})
        assert "feat/nju-ppt-optional tarball" in branch_result.stdout
        assert (branch_home / ".agents/skills/nju-ppt/SKILL.md").is_file()
        install(home, "ppt")
        backups = home / ".local/share/agent-skills/.backups/ppt"
        assert not backups.exists()
        with (skill / "SKILL.md").open("a", encoding="utf-8") as f:
            f.write("\nlocal edit\n")
        install(home, "ppt")
        assert any("local edit" in p.read_text(encoding="utf-8") for p in backups.glob("*/SKILL.md"))
        assert "local edit" not in (skill / "SKILL.md").read_text(encoding="utf-8")
        print("PASS ppt: complete payload, explicit dependency flag, idempotence, drift backup")

        all_home = tmp / "all HOME"
        install(all_home, "all")
        assert (all_home / ".agents/skills/nju-ppt/SKILL.md").is_file()
        assert (all_home / ".agents/skills/steady-do/SKILL.md").is_file()
        install(home, "all", "ppt", success=False)
        install(tmp / "no python", "ppt", success=False, extra={"NJU_PPT_PYTHON": "/usr/bin/false"})
        install(tmp / "failed prepare", "ppt", success=False, extra={"PREPARE_EXIT": "1"})
        (source / "skills/ppt/nju-ppt/scripts/prepare.py").unlink()
        archive(package, source)
        p = install(tmp / "old main", "ppt", success=False)
        assert "main" in p.stderr and "ppt" in p.stderr
        print("PASS all/invalid groups/missing Python/failed preparation/old main error propagation")

        for name in ["opencode-setup.sh", "pi-setup.sh", "codex-setup.sh"]:
            text = (ROOT / name).read_text(encoding="utf-8")
            assert re.search(r'ask "[^"\n]*ppt 组[^"\n]*" N && SKILL_GROUPS\+=\(ppt\)', text), name
            assert "SKILL_GROUPS=(base)" in text
            assert '${AGENT_SKILLS_REF:-main}' in text, name
            assert '${AGENT_SKILLS_REPO:-brilliantrough/agent-skills}' in text, name
        print("PASS three setup entry points: PPT defaults to N; base remains default")
        external_checks(tmp, env)
        print("NOTE: non-PPT payload, download, external stage and Python invocation were fixtures; not a real GitHub install")


if __name__ == "__main__":
    main()
