---
name: save-mem
description: Honor explicit save requests and maintain the project's durable profile, decisions, risks and milestones. Leave routine capture to Claude-Mem; completing a task does not require another summary.
---

# Save Memory

When enabled, Claude-Mem captures routine work for later recall. If the user asks to remember something, honor the requested destination. Without a specified destination, use the host's Claude-Mem save tool when available; otherwise use one available durable store and say where. Do not save credentials or manually mirror a fact across stores.

## What belongs in StrictDoc

| Record | Update it when… |
|---|---|
| Project profile | The project's purpose, structure, main research routes or key understanding changes. Use `project-profile`; distinguish a paused route from a disproved one. |
| Decisions | A settled choice changes how future work should proceed. Keep its scope and reason. When replacing an active decision, retain its UID and history, mark it `Superseded`, and link its successor. |
| Risks | A material uncertainty changes the next decision. In the existing risk entry or handoff, state what is unknown, its consequence and what would resolve it. Don't create a risk register for routine caveats. |
| Journal | A phase reaches a lasting outcome worth explaining to a future reader. Record the conclusion and its limits; leave the sequence of attempts in Claude-Mem. |

Read the existing entry first. If it already says what future work needs, leave it alone; otherwise maintain it in place. After editing StrictDoc memory, run `python3 <save-mem skill directory>/scripts/check_size.py docs` from the project root. After changing `.sdoc` or its configuration, also run `strictdoc export .` from the docs root.
