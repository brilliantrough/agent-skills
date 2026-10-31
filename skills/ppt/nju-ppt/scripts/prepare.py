#!/usr/bin/env python3
"""Check nju-ppt paths/runtime; --install prepares only its own venv and core packages."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import venv

SKILL = Path(__file__).resolve().parents[1]
TEMPLATE = SKILL / "assets/nju-academic-ginkgo"
BASELINE = "8070d3df1f6f54b5fb60a9ae66e79c664f050212"
SCRIPTS = (
    "project_manager.py", "apply_template.py", "svg_quality_checker.py",
    "svg_to_pptx.py", "template_preview_pptx.py", "pptx_delivery_check.py",
    "text_measure.py", "svg_editor/server.py",
)
PROTOTYPES = (
    "01_cover", "02_points3", "03_toc", "04_chapter", "05_pillars4",
    "06_two_col", "07_timeline", "08_chart_column", "09_chart_combo",
    "10_table", "11_ending",
)


def require_files(root, names):
    missing = [str(root / name) for name in names if not (root / name).is_file()]
    if missing:
        raise RuntimeError("缺少文件：" + ", ".join(missing))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", help="允许创建独立venv并联网补齐核心依赖")
    parser.add_argument("--home", type=Path, default=Path.home(), help="安装器传入的原生用户目录；测试可用临时HOME")
    parser.add_argument("--engine", type=Path, help="显式ppt-master skill根目录；也可设PPT_MASTER_ROOT")
    args = parser.parse_args()
    if sys.version_info < (3, 10):
        raise RuntimeError("需要Python 3.10+；安装器可用NJU_PPT_PYTHON选择解释器")
    home = args.home.expanduser().resolve()
    engine = args.engine or Path(os.environ.get("PPT_MASTER_ROOT", home / ".agents/skills/ppt-master"))
    engine = engine.expanduser().resolve()
    require_files(engine, ["SKILL.md", *("scripts/" + name for name in SCRIPTS)])
    require_files(TEMPLATE, [
        "templates/design_spec.md", *("templates/" + name + ".svg" for name in PROTOTYPES),
        "images/nju-logo.png", "images/ginkgo-leaf.png", "icons/imported/nju-campus.svg",
    ])
    env = home / ".local/share/agent-skills/nju-ppt/venv"
    python = env / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not python.is_file():
        if not args.install:
            raise RuntimeError("独立环境不存在；同意准备依赖后用Python 3.10+重跑本命令并加 --install")
        venv.EnvBuilder(with_pip=True).create(env)
    if args.install:
        subprocess.run([
            str(python), "-m", "pip", "install", "--disable-pip-version-check",
            "-r", str(SKILL / "requirements-core.txt"),
        ], check=True, stdout=sys.stderr)
    subprocess.run([
        str(python), "-c",
        "import sys\nif sys.version_info < (3,10): raise SystemExit('venv needs Python 3.10+')\n"
        "import pptx, yaml, xlsxwriter, PIL, pathops, uharfbuzz, flask, bs4",
    ], check=True, stdout=sys.stderr)
    # An existing entry point alone does not prove this template contract still works.
    result = subprocess.run([
        str(python), str(engine / "scripts/svg_quality_checker.py"),
        str(TEMPLATE / "templates"), "--template-mode", "--canonical-authoring",
    ], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError("引擎或模板契约校验失败：\n" + result.stdout + result.stderr)
    print(json.dumps({
        "python": str(python), "ppt_master_root": str(engine),
        "template_root": str(TEMPLATE), "skill_root": str(SKILL),
        "core_imports": "passed", "template_contract": "passed",
        "tested_engine_baseline": BASELINE,
        "not_checked": ["full_generation", "office", "fonts", "projection"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print("ERROR: " + str(exc), file=sys.stderr)
        sys.exit(1)
