#!/usr/bin/env python3
"""源码基准回归：默认受管 clone、复用/fetch、显式本地工作树零修改、离线复用、file:// 模板可取。

生产实现是四个 setup 与 skills-sync.sh 共用的 file_url/acquire_source（check.sh 校验逐字节一致）；
本测试直接调用真实函数，fixture 是一个本地 git 仓库，经 AGENT_SKILLS_REPO 以 file:// 传入。
`--static-contract` 只运行入口资产、取源与大输出退役静态契约，供快速 check.sh 复用；
`--context-output-static` 仅保留输出退役单项，便于隔离变异回归。
"""
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ("pi-setup.sh", "opencode-setup.sh", "codex-setup.sh", "dsh-setup.sh", "skills-sync.sh")


def function(path, name):
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if re.match(rf"^{name}\(\)\s*\{{", line))
    heredoc = None
    for i in range(start + 1, len(lines)):
        stripped = lines[i].strip()
        if heredoc:
            if stripped == heredoc:
                heredoc = None
            continue
        marker = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)", lines[i])
        if marker:
            heredoc = marker.group(1)
            continue
        if lines[i].rstrip("\n") == "}":
            return "".join(lines[start:i + 1])
    raise AssertionError(f"{path.name}: 函数 {name} 未闭合")


def shared_scope():
    """五个脚本的取源实现必须逐字节一致;skills-sync 直接跑真实脚本。"""
    blocks = {name: (function(ROOT / name, "file_url"), function(ROOT / name, "acquire_source"))
              for name in FILES}
    first = blocks[FILES[0]]
    for name in FILES[1:]:
        assert blocks[name] == first, f"{name} 的取源实现与 {FILES[0]} 不一致"
    return first


def git(repo, *args, env=None):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True,
                          env=env, check=False)


def commit(repo, name, content):
    if name is not None:
        (repo / name).write_text(content, encoding="utf-8")
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
    assert git(repo, "add", "-A").returncode == 0
    assert git(repo, "commit", "-qm", str(name), env=env).returncode == 0


def make_source(tmp):
    """最小本仓工作树:skills/<组>/<名>/SKILL.md、templates/ 与 skills-external.sh,提交成 main。"""
    repo = tmp / "fixture-repo"
    (repo / "skills/base/demo").mkdir(parents=True)
    (repo / "skills/base/demo/SKILL.md").write_text("demo skill\n", encoding="utf-8")
    (repo / "templates/pi").mkdir(parents=True)
    (repo / "templates/pi/settings.json").write_text('{"demo": true}\n', encoding="utf-8")
    # skills-sync.sh 无条件调用同一棵树里的外部依赖脚本
    (repo / "skills-external.sh").write_text(
        '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "${EXTERNAL_LOG:-/dev/null}"\nexit 0\n',
        encoding="utf-8")
    assert subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True).returncode == 0
    commit(repo, None, "seed\n")
    return repo


def run_source(ctx, runner_extra="", env_extra=None):
    """在子 Bash 里执行真实的取源实现,并输出解析结果。"""
    file_url_fn, acquire_fn = ctx["funcs"]
    script = ctx["tmp"] / "acquire.sh"
    script.write_text(
        "set -uo pipefail\n"
        "IS_WIN=0\n"
        f"{file_url_fn}\n{acquire_fn}\n"
        "acquire_source || { echo \"ACQUIRE-FAILED\"; exit 3; }\n"
        "printf 'ROOT=%s\\nSELF_RAW=%s\\nRAW=%s\\n' \"$SOURCE_ROOT\" \"$SELF_RAW\" \"$RAW\"\n"
        f"{runner_extra}\n",
        encoding="utf-8",
    )
    env = {"PATH": os.environ["PATH"], "HOME": str(ctx["home"]),
           "XDG_DATA_HOME": str(ctx["xdg"]), "AGENT_SKILLS_REPO": ctx["repo_url"]}
    env.update(env_extra or {})
    return subprocess.run(["bash", str(script)], capture_output=True, text=True, env=env, cwd=ROOT,
                          stdin=subprocess.DEVNULL, timeout=60, check=False)


def parse(out):
    return dict(re.findall(r"^(ROOT|SELF_RAW|RAW)=(.*)$", out, re.M))


def check_json_template_crossed(out, xdg, want):
    """curl 用解析出的 file:// 取模板——同一个 URL 机制,不需要 mock。"""
    values = parse(out)
    url = values["RAW"] + "/pi/settings.json"
    got = subprocess.run(["curl", "-fsSL", "--connect-timeout", "5", "-m", "20", url],
                         capture_output=True, text=True, check=False)
    assert got.returncode == 0, (url, got.stderr)
    assert got.stdout == want, (url, got.stdout)


def context_output_retirement():
    bad = []
    if (ROOT / "context-rewrite/output-store.mjs").exists():
        bad.append("自研 output-store 不应恢复")
    for name in ("pi/extensions/context-rewrite.ts", "opencode/v2/context-rewrite.js",
                 "opencode/plugins/context-rewrite.js", "dsh/index.mjs"):
        source = (ROOT / name).read_text(encoding="utf-8")
        if re.search(r"createOutputStore|READ_TOOL|context_output_read", source):
            bad.append(f"{name} 仍引用退役外置")
        if not re.search(r"name: TOOL|\[TOOL\]", source):
            bad.append(f"{name} 不应误删 context_rewrite")
    for name in ("context-mode/fork-patches.mjs", "context-mode/release.mjs", "context-mode/guidance.md"):
        source = (ROOT / name).read_text(encoding="utf-8")
        if "Use context_output_read for exact snapshots" in source:
            bad.append(f"{name} 仍指向退役读取工具")
        if not any(text in source for text in ("outputOwner", "native output gates", "原生输出门控")):
            bad.append(f"{name} 缺原生输出门控说明")
    if bad:
        raise RuntimeError("大输出退役静态契约失败：\n" + "\n".join(bad))
    print("PASS 自研外置退役:context_rewrite 与原生门控说明保留")


def entry_asset_closure():
    """入口直接引用的正式资产必须在干净检出中存在；Git 交付候选里不能只靠本机未跟踪文件。"""
    text = (ROOT / "scripts/check.sh").read_text(encoding="utf-8")
    refs = {
        "tests/setup-preflight.py", "tests/nju-ppt-editability.py",
        "scripts/verify-subagents.sh", "skills/base/verification/SKILL.md",
        "skills/base/verification/references/reviewer.md", "dsh/verification-policy.mjs",
    }
    for line in text.splitlines():
        stripped = line.lstrip()
        if not stripped.startswith("t_case "):
            continue
        try:
            words = shlex.split(stripped, comments=True)
        except ValueError as exc:
            raise RuntimeError(f"t_case 行无法按 shell 字面参数读取：{stripped}") from exc
        if len(words) < 2 or "$" in words[1]:
            raise RuntimeError(f"t_case 首参数必须是可静态核对的路径：{line.strip()}")
        refs.add(words[1])
    tracked = None
    if os.path.lexists(ROOT / ".git"):
        env = os.environ.copy()
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_PREFIX", "GIT_CONFIG"):
            env.pop(key, None)
        try:
            out = subprocess.check_output(["git", "ls-files", "--stage", "--debug", "--"], cwd=ROOT, env=env,
                                          text=True, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError) as exc:
            raise RuntimeError("检测到 Git 元数据，但索引读取失败；修复索引后再交付") from exc
        tracked = set()
        current = None
        for line in out.splitlines():
            if not line.startswith(" "):
                meta, sep, path = line.partition("\t")
                fields = meta.split()
                # stage 0 且有实际 blob 才可能是交付内容；空文件正常 staged 也合法。
                current = path if sep and len(fields) == 3 and fields[2] == "0" and fields[1].strip("0") else None
                if current:
                    tracked.add(current)
            elif current and "flags:" in line:
                flags = int(line.rsplit("flags:", 1)[1].strip(), 16)
                if flags & 0x20000000:  # CE_INTENT_TO_ADD：add -N 不会把文件写入 index tree。
                    tracked.discard(current)
    bad = []
    for name in sorted(refs):
        if not (ROOT / name).is_file():
            bad.append(f"{name} 缺失")
        elif tracked is not None and name not in tracked:
            bad.append(f"{name} 未入库；完整 git add 后再作为交付候选（add -N 不算）")
    if bad:
        raise RuntimeError("入口资产闭包失败：\n" + "\n".join(bad))
    suffix = "且已入库" if tracked is not None else "（非 Git 树，未核对入库）"
    print(f"PASS 入口与 Verification 资产存在{suffix}")


def source_channel_contract():
    """本仓源码只走受管 Git／显式源码树；Release 与第三方仓库不受此禁令影响。"""
    files = [ROOT / name for name in FILES] + [ROOT / "modules/run.sh"]
    files += sorted((ROOT / "modules").glob("*/setup.sh"))
    bad = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        for url in re.findall(r"https?://[^\s\"'<>]+", text):
            parsed = urlsplit(url)
            host = (parsed.hostname or "").lower()
            parts = [part for part in parsed.path.split("/") if part]
            own_repo = len(parts) >= 2 and parts[1].lower() == "agent-skills"
            forbidden = False
            if host == "raw.githubusercontent.com":
                forbidden = own_repo
            elif host == "codeload.github.com":
                forbidden = own_repo
            elif host == "github.com" and own_repo and len(parts) >= 3:
                forbidden = parts[2].lower() in {"archive", "raw"}
            if forbidden:
                bad.append(f"{path.relative_to(ROOT)}: 本仓 raw／archive／codeload 旁路：{url}")
    if bad:
        raise RuntimeError("源码取源必须回到受管 Git／显式源码树：\n" + "\n".join(bad))
    print("PASS 本仓源码无 raw／archive／codeload 旁路；Release 与第三方来源保留")


def static_contract():
    context_output_retirement()
    entry_asset_closure()
    source_channel_contract()


def main():
    static_contract()
    funcs = shared_scope()
    with tempfile.TemporaryDirectory(prefix="source-bench-") as d:
        tmp = pathlib.Path(d)
        repo = make_source(tmp)
        ctx = {"tmp": tmp, "funcs": funcs, "home": tmp / "home", "xdg": tmp / "xdg",
               "repo_url": f"file://{repo}"}
        ctx["home"].mkdir()
        managed = ctx["xdg"] / "agent-skills/source"

        # 1) 首次 clone:默认受管路径,取自 AGENT_SKILLS_REPO
        out = run_source(ctx)
        assert out.returncode == 0, out.stderr + out.stdout
        values = parse(out.stdout)
        assert values["ROOT"] == str(managed), values
        assert (managed / "skills/base/demo/SKILL.md").is_file()
        assert values["RAW"].startswith("file://") and values["RAW"].endswith("/templates"), values
        check_json_template_crossed(out.stdout, ctx["xdg"], '{"demo": true}\n')
        first_commit = git(managed, "rev-parse", "HEAD").stdout.strip()
        print("PASS 首次 clone:受管路径、skills/templates 就位、file:// 模板可被 curl 取到")

        # 2) 复用并更新:第二次只需 fetch,不重新 clone;能取到新提交
        commit(repo, "second", "second\n")
        out = run_source(ctx)
        assert out.returncode == 0, out.stderr + out.stdout
        assert (managed / "second").is_file(), "未 fetch 到新提交"
        assert git(managed, "rev-parse", "HEAD").stdout.strip() != first_commit
        assert "首次克隆" not in out.stdout, out.stdout
        print("PASS 复用/fetch:同一受管 clone 更新到新提交,不重复克隆")

        # 3) 显式本地工作树:只读,不 pull、不改动候选工作树的 .git 与文件
        candidate = repo
        head_before = git(candidate, "rev-parse", "HEAD").stdout
        status_before = git(candidate, "status", "--porcelain").stdout
        refs_before = sorted(p.name for p in (candidate / ".git/refs").rglob("*"))
        out = run_source(ctx, env_extra={"AGENT_SKILLS_SOURCE": os.path.relpath(candidate, ROOT),
                                         "AGENT_SKILLS_REPO": "file:///nonexistent/repo"})
        assert out.returncode == 0, out.stderr + out.stdout
        values = parse(out.stdout)
        assert values["ROOT"] == str(candidate), values
        assert values["SELF_RAW"] == f"file://{candidate}", values
        assert git(candidate, "rev-parse", "HEAD").stdout == head_before
        assert git(candidate, "status", "--porcelain").stdout == status_before, "候选工作树被改动"
        assert sorted(p.name for p in (candidate / ".git/refs").rglob("*")) == refs_before
        assert "只读" in out.stdout and "首次克隆" not in out.stdout, out.stdout
        print("PASS 显式 AGENT_SKILLS_SOURCE:零 git 修改、零网络,直接使用候选工作树")
        special = tmp / "candidate [x] #?%"
        shutil.copytree(repo, special)
        out = run_source(ctx, env_extra={"AGENT_SKILLS_SOURCE": str(special)})
        assert out.returncode == 0, out.stderr + out.stdout
        values = parse(out.stdout)
        assert "%5B" in values["SELF_RAW"] and "%5D" in values["SELF_RAW"], values
        check_json_template_crossed(out.stdout, ctx["xdg"], '{"demo": true}\n')
        print("PASS file:// 特殊路径:方括号、空格、#、?、% 均可读取")

        # 4) 离线但已有受管 clone:WARN 并继续用已有提交,不静默当成最新
        stale = git(managed, "rev-parse", "--short", "HEAD").stdout.strip()
        out = run_source(ctx, env_extra={"AGENT_SKILLS_REPO": "file:///nonexistent/repo"})
        assert out.returncode == 0, out.stderr + out.stdout
        assert "WARN" in out.stderr and stale in out.stderr, (out.stdout, out.stderr)
        assert parse(out.stdout)["ROOT"] == str(managed)
        print("PASS 离线已有 clone:WARN 并报出所用 commit,继续可用")

        # 5) 离线且没有 clone:明确失败,不退回到任何陈旧内容
        empty = tmp / "empty-xdg"
        env = {"AGENT_SKILLS_REPO": "file:///nonexistent/repo", "XDG_DATA_HOME": str(empty)}
        out = run_source(ctx, env_extra=env)
        assert out.returncode == 3, out.stdout + out.stderr
        assert "ERROR" in out.stderr and not (empty / "agent-skills/source").exists()
        # 显式来源无效时同样拒绝,不猜路径
        out = run_source(ctx, env_extra={"AGENT_SKILLS_SOURCE": str(tmp)})
        assert out.returncode == 3 and "不是本仓工作树" in out.stderr, out.stderr
        print("PASS 无可用源:不会静默使用不存在/不完整的内容")

        # 6) skills-sync.sh 的真实入口:默认 clone 取源,不再下载 tarball;同步到隔离 HOME
        sync_home = tmp / "sync-home"
        sync_home.mkdir()
        env = {"PATH": os.environ["PATH"], "HOME": str(sync_home), "XDG_DATA_HOME": str(empty),
               "AGENT_SKILLS_REPO": f"file://{repo}", "ASSUME_YES": "1", "AGENTS_TAIL": "0",
               "SKILLS_EXTERNAL": "skip"}
        proc = subprocess.run(["bash", str(ROOT / "skills-sync.sh"), "base"], capture_output=True,
                              text=True, env=env, stdin=subprocess.DEVNULL, timeout=180, check=False)
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert "codeload" not in proc.stdout and "tarball" not in proc.stdout, proc.stdout
        assert (sync_home / ".agents/skills/demo/SKILL.md").read_text() == "demo skill\n"
        # 第二次在同一 HOME 上跑:复用 clone,未变不重写
        proc = subprocess.run(["bash", str(ROOT / "skills-sync.sh"), "base"], capture_output=True,
                              text=True, env=env, stdin=subprocess.DEVNULL, timeout=180, check=False)
        assert proc.returncode == 0 and "unchanged: base/demo" in proc.stdout, proc.stdout
        print("PASS skills-sync.sh:真实入口从受管 clone 取源并幂等同步")
        # 从候选目录运行时，AGENTS 尾块不得回写候选树。
        (repo / "AGENTS.tail.md").write_text(
            "<!-- memory-system:start -->\nTEST-BLOCK\n<!-- memory-system:end -->\n", encoding="utf-8")
        candidate_env = dict(env, AGENT_SKILLS_SOURCE=str(repo), AGENTS_TAIL="1")
        proc = subprocess.run(["bash", str(ROOT / "skills-sync.sh"), "base"], capture_output=True,
                              text=True, env=candidate_env, cwd=repo, stdin=subprocess.DEVNULL,
                              timeout=60, check=False)
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert "只读源码树" in proc.stdout and not (repo / "AGENTS.md").exists()
        print("PASS 候选源码树:AGENTS 尾块不回写")

        # 7) Pi 本地路径包：真实 Pi 会把绝对安装路径写成相对 agent dir 的 source。
        agent = tmp / "relative-agent"
        source = tmp / "relative-src"
        agent.mkdir()
        source.mkdir()
        (agent / "settings.json").write_text('{"packages": ["../relative-src"]}\n', encoding="utf-8")
        probe = tmp / "pkg-installed.sh"
        probe.write_text(
            "set -euo pipefail\nIS_WIN=0\nnpath() { printf '%s' \"$1\"; }\n"
            f"AGENT_DIR={shlex.quote(str(agent))}\nSETTINGS={shlex.quote(str(agent / 'settings.json'))}\n"
            + function(ROOT / "pi-setup.sh", "pkg_installed")
            + "\npkg_installed \"$1\"\n",
            encoding="utf-8")
        found = subprocess.run(["bash", str(probe), str(source)], capture_output=True, text=True, check=False)
        assert found.returncode == 0, found.stdout + found.stderr
        missing = subprocess.run(["bash", str(probe), str(tmp / "other")], capture_output=True, text=True, check=False)
        assert missing.returncode == 1, missing.stdout + missing.stderr
        relative_probe = tmp / "pkg-installed-relative-agent.sh"
        relative_probe.write_text(probe.read_text(encoding="utf-8").replace(
            f"AGENT_DIR={shlex.quote(str(agent))}", "AGENT_DIR=relative-agent"), encoding="utf-8")
        found = subprocess.run(["bash", str(relative_probe), str(source)], capture_output=True,
                               text=True, cwd=tmp, check=False)
        assert found.returncode == 0, found.stdout + found.stderr
        pi_text = (ROOT / "pi-setup.sh").read_text(encoding="utf-8")
        assert 'pi_install "$REPO_PI_SPEC"' in pi_text
        assert 'old_spec="git:github.com/brilliantrough/agent-skills"' in pi_text
        assert 'remove "$old_spec"' in pi_text
        print("PASS Pi 本地路径包:相对 source 可识别，旧 git 登记有退役入口")
        runtime_home = tmp / "runtime-home"
        current_bin = runtime_home / ".local/share/pi-node/current/bin"
        current_bin.mkdir(parents=True)
        for name in ("pi", "node"):
            (current_bin / name).write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            (current_bin / name).chmod(0o755)
        prefix_probe = tmp / "pi-prefix.sh"
        prefix_probe.write_text(pi_text.split("ask() {", 1)[0]
                                + "\nprintf 'AGENT=%s\\nPI=%s\\nNODE=%s\\n' \"$AGENT_DIR\" \"$(command -v pi)\" \"$(command -v node)\"\n",
                                encoding="utf-8")
        prefix_env = dict(os.environ, HOME=str(runtime_home), PI_CODING_AGENT_DIR="agent")
        prefixed = subprocess.run(["bash", str(prefix_probe)], capture_output=True, text=True,
                                  env=prefix_env, cwd=tmp, check=False)
        assert prefixed.returncode == 0, prefixed.stdout + prefixed.stderr
        assert f"AGENT={tmp / 'agent'}" in prefixed.stdout
        assert f"PI={current_bin / 'pi'}" in prefixed.stdout and f"NODE={current_bin / 'node'}" in prefixed.stdout
        print("PASS Pi 前置环境:current Node 与相对 agent dir 在计划前归一化")

        # 8) staged Pi 包：从本地树复制运行资产，npm 只在首次/lock 变化时运行，候选树零依赖写入。
        for name in ("pi", "context-rewrite", "image-gen"):
            (repo / name).mkdir()
        (repo / "pi/extensions/ui").mkdir(parents=True)
        (repo / "pi/extensions/ui/index.ts").write_text("export {};\n", encoding="utf-8")
        link_probe = tmp / "link-dev-types.sh"
        link_probe.write_text(
            "set -euo pipefail\nIS_WIN=0\n" + f"SOURCE_ROOT={shlex.quote(str(repo))}\n"
            + function(ROOT / "pi-setup.sh", "link_dev_types") + "\nlink_dev_types\n",
            encoding="utf-8")
        linked = subprocess.run(["bash", str(link_probe)], capture_output=True, text=True, cwd=repo, check=False)
        assert linked.returncode == 0 and "候选源码树只读" in linked.stdout, linked.stdout + linked.stderr
        assert not (repo / "node_modules").exists()
        (repo / "package.json").write_text('{"name":"agent-skills","dependencies":{"acp-kernel":"0.0.101"}}\n', encoding="utf-8")
        (repo / "package-lock.json").write_text('{"lockfileVersion":3}\n', encoding="utf-8")
        npm_log = tmp / "npm.log"
        fake_bin = tmp / "fake-bin"
        fake_bin.mkdir()
        (fake_bin / "npm").write_text(
            '#!/usr/bin/env bash\nmkdir -p node_modules/acp-kernel\nprintf "%s\\n" "$*" >> "$NPM_LOG"\n',
            encoding="utf-8")
        (fake_bin / "npm").chmod(0o755)
        vendor = tmp / "pi-agent/vendor/agent-skills"
        prepare = tmp / "prepare-pi.sh"
        prepare.write_text(
            "set -euo pipefail\nIS_WIN=0\nnpath() { printf '%s' \"$1\"; }\n"
            f"AGENT_DIR={shlex.quote(str(tmp / 'pi-agent'))}\nSOURCE_ROOT={shlex.quote(str(repo))}\n"
            "REPO_PI_SPEC=\"$AGENT_DIR/vendor/agent-skills\"\n"
            "REPO_PI_PKG=\"$REPO_PI_SPEC\"\nPLAN_PI_PKGS=1\nPLAN_PI_UPDATE=0\nPLAN_WRITE_CFG=1\n"
            + function(ROOT / "pi-setup.sh", "prepare_repo_pi_pkg")
            + "\nprepare_repo_pi_pkg\nprepare_repo_pi_pkg\n",
            encoding="utf-8")
        env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}", NPM_LOG=str(npm_log))
        staged = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert staged.returncode == 0, staged.stdout + staged.stderr
        assert (vendor / "node_modules/acp-kernel").is_dir()
        assert not (repo / "node_modules").exists(), "候选工作树被写入依赖"
        assert len(npm_log.read_text(encoding="utf-8").splitlines()) == 1, "lock 未变时不应重复 npm ci"
        assert not list((tmp / "pi-agent/vendor").glob("agent-skills.bak-*")), "同内容重跑不应制造备份"
        # lock 变化必须重新安装；紧随的第二次相同运行仍保持幂等。
        (repo / "package-lock.json").write_text('{"lockfileVersion":3,"changed":true}\n', encoding="utf-8")
        staged = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert staged.returncode == 0, staged.stdout + staged.stderr
        assert len(npm_log.read_text(encoding="utf-8").splitlines()) == 2, "lock 变化未触发 npm ci"
        assert len(list((tmp / "pi-agent/vendor").glob("agent-skills.bak-*"))) == 1
        # 已删除的 output-store 随受管目录刷新退役；历史快照不动，第二次运行保持 unchanged。
        legacy = vendor / "context-rewrite/output-store.mjs"
        legacy.write_text("legacy\n", encoding="utf-8")
        snapshots = tmp / "context-output"
        snapshots.mkdir()
        (snapshots / "keep.txt").write_text("keep\n", encoding="utf-8")
        staged = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert staged.returncode == 0 and not legacy.exists(), staged.stdout + staged.stderr
        assert (snapshots / "keep.txt").read_text(encoding="utf-8") == "keep\n"
        assert "unchanged: 本仓库 Pi 本地包" in staged.stdout
        assert len(list((tmp / "pi-agent/vendor").glob("agent-skills.bak-*"))) == 2
        # 缺件或源码目录软链都必须失败并保留旧副本，不能删除候选依赖。
        before = (vendor / "package-lock.json").read_bytes()
        (repo / "pi").rename(repo / "pi-real")
        failed = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert failed.returncode != 0 and (vendor / "package-lock.json").read_bytes() == before
        (repo / "pi-real/node_modules").mkdir()
        (repo / "pi-real/node_modules/keep").write_text("keep", encoding="utf-8")
        (repo / "pi").symlink_to(repo / "pi-real", target_is_directory=True)
        failed = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert failed.returncode != 0 and (repo / "pi-real/node_modules/keep").is_file()
        (repo / "pi").unlink()
        (repo / "pi-real").rename(repo / "pi")
        # vendor 父链接指回候选时，拒绝在任何依赖写入前停止。
        linked_agent = tmp / "linked-agent"
        linked_agent.mkdir()
        (linked_agent / "vendor").symlink_to(repo, target_is_directory=True)
        linked_prepare = tmp / "prepare-pi-linked.sh"
        linked_prepare.write_text(prepare.read_text(encoding="utf-8").replace(
            f"AGENT_DIR={shlex.quote(str(tmp / 'pi-agent'))}", f"AGENT_DIR={shlex.quote(str(linked_agent))}"), encoding="utf-8")
        failed = subprocess.run(["bash", str(linked_prepare)], capture_output=True, text=True, env=env, check=False)
        assert failed.returncode != 0 and not (repo / "node_modules").exists()
        # 已装副本继承的清单软链必须先解除，复制新清单不得写穿候选文件。
        for name in ("package.json", "package-lock.json"):
            candidate_file = repo / f"candidate-{name}"
            candidate_file.write_text('{"untouched":true}\n', encoding="utf-8")
            (vendor / name).unlink()
            (vendor / name).symlink_to(candidate_file)
        staged = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert staged.returncode == 0, staged.stdout + staged.stderr
        for name in ("package.json", "package-lock.json"):
            assert (repo / f"candidate-{name}").read_text(encoding="utf-8") == '{"untouched":true}\n'
            assert not (vendor / name).is_symlink()
        # 即使链接目标内容完全相同，也必须替换旧链接，不能被 diff 误判为 unchanged。
        for name in ("package.json", "package-lock.json"):
            same_file = repo / f"same-{name}"
            same_file.write_bytes((repo / name).read_bytes())
            (vendor / name).unlink()
            (vendor / name).symlink_to(same_file)
        staged = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert staged.returncode == 0, staged.stdout + staged.stderr
        for name in ("package.json", "package-lock.json"):
            assert not (vendor / name).is_symlink(), f"同内容重跑遗留 {name} 软链"
            assert (repo / f"same-{name}").read_bytes() == (repo / name).read_bytes()
        # 源清单自身也不允许是链接，避免 staged 副本继续依赖外部路径。
        (repo / "package.json").rename(repo / "package-real.json")
        (repo / "package.json").symlink_to(repo / "package-real.json")
        failed = subprocess.run(["bash", str(prepare)], capture_output=True, text=True, env=env, check=False)
        assert failed.returncode != 0 and (repo / "package-real.json").is_file()
        (repo / "package.json").unlink()
        (repo / "package-real.json").rename(repo / "package.json")
        print("PASS Pi staged 包:本地树装配、依赖复用、候选树零写入")


if __name__ == "__main__":
    if sys.argv[1:] == ["--static-contract"]:
        static_contract()
    elif sys.argv[1:] == ["--context-output-static"]:
        context_output_retirement()
    else:
        main()
