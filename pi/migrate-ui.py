#!/usr/bin/env python3
"""Preview/apply the local UI migration. Never install packages or touch credentials."""
import argparse
import hashlib
import json
import os
import shutil
import time
from pathlib import Path

LEGACY = {
    "extensions/linefeed-submit.ts": "b1420c8c47b22a1c26b91ff7e840af0750a3f7023d70cb1af54ae63d3eeca32c",
    "extensions/tps-meter.ts": "40a540fdcda24b124066c0a6486056618eeb4fa5bc838465d288a3f3b6e15ffe",
    "extensions/usage-labels.ts": "8921348bb7ed05f8693ab3a74eae3ba7f5e0023f9a158c85bbdce7118c6dd48e",
}
SOURCE = "git:github.com/brilliantrough/agent-skills"
UI = "pi/extensions/ui/index.ts"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, default=Path(os.environ.get("PI_CODING_AGENT_DIR", Path.home() / ".pi/agent")))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    agent = args.agent_dir.expanduser().resolve()
    package = agent / "git/github.com/brilliantrough/agent-skills"
    try:
        registered = json.loads((package / "package.json").read_text())["pi"]["extensions"]
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(f"STOP: cannot read installed package manifest: {error}") from error
    if not (package / UI).is_file() or UI not in registered:
        raise SystemExit("STOP: update/install the agent-skills package with its new UI first; nothing changed")
    def load(name, default):
        path = agent / name
        if path.is_symlink():
            raise SystemExit(f"STOP: refusing symlink {path}")
        try:
            return json.loads(path.read_text()) if path.exists() else default
        except (OSError, ValueError) as error:
            raise SystemExit(f"STOP: cannot read {path}: {error}; nothing changed") from error
    settings = load("settings.json", {})
    packages = settings.get("packages", [])
    own = next((p for p in packages if (p if isinstance(p, str) else p.get("source")) == SOURCE), None)
    if own is None or isinstance(own, dict) and "extensions" in own:
        raise SystemExit("STOP: agent-skills missing or has custom extension filters; review manually")
    moves = []
    for name, checksum in LEGACY.items():
        path = agent / name
        if not path.exists():
            continue
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise SystemExit(f"STOP: modified legacy file {path}; review diff before migration")
        moves.append(name)
    def legacy_package(item):
        source = item if isinstance(item, str) else item.get("source", "")
        return any(source == n or source.startswith(n + "@") for n in ("npm:pi-zentui", "npm:pi-atelier")) or source == str(agent / "local-packages/atelier-bridge")
    removed = [p for p in packages if legacy_package(p)]
    settings["packages"] = [p for p in packages if not legacy_package(p)]
    settings.setdefault("tuiMode", "fullscreen")
    keys = load("keybindings.json", {})
    keys.setdefault("tui.input.submit", ["ctrl+enter", "ctrl+j"])
    keys.setdefault("tui.input.newLine", ["enter", "shift+enter"])
    configs = {"settings.json": settings, "keybindings.json": keys}
    for new, old, default in [
        ("agent-skills-ui.json", "pi-atelier.json", {"preset": "editorial", "showSidebarOnStartup": True, "completionNotifications": False}),
        ("agent-skills-editor.json", "zentui.json", {"components": {"editor": {"modelLabel": "name", "colorSource": "theme"}}}),
    ]:
        configs[new] = load(new, None)
        if configs[new] is None:
            configs[new] = load(old, default)
    changes = {name: data for name, data in configs.items() if load(name, None) != data}
    print("Disable legacy UI packages:", [p if isinstance(p, str) else p["source"] for p in removed])
    print("Backup and retire known files:", moves)
    print("Config changes:", list(changes))
    if not changes and not moves:
        print("Already migrated; no changes")
        return
    if not args.apply:
        print("Preview only; use --apply after reviewing")
        return
    backup = agent / "backups" / f"ui-migration-{time.time_ns()}"
    backup.mkdir(parents=True)
    (backup / "manifest.json").write_text(json.dumps({"changed": list(changes), "moved": moves, "new": [n for n in changes if not (agent/n).exists()]}, indent=2)+"\n")
    for name in changes:
        if (agent / name).exists():
            dest = backup / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(agent / name, dest)
    # Stage config writes atomically before retiring the old auto-discovered files.
    for name, data in changes.items():
        dest = agent / name
        temp = dest.with_name(dest.name + ".ui-migrate.tmp")
        with temp.open("x", encoding="utf-8") as file:
            json.dump(data, file, ensure_ascii=False, indent=2)
            file.write("\n")
        if dest.exists():
            shutil.copymode(dest, temp)
        os.replace(temp, dest)
    for name in moves:
        dest = backup / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.move(agent / name, dest)
        except OSError as error:
            raise SystemExit(f"STOP: migration incomplete; do not reload. Restore from {backup}: {error}") from error
    print("Migrated. Backup:", backup)
    print("Use /reload. Old npm packages/configs remain on disk for rollback.")


if __name__ == "__main__":
    main()
