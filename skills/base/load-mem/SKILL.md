---
name: load-mem
description: Resume project work using its profile, current decisions and open risks. Use Claude-Mem's official mem-search when a prior attempt or decision matters and the available context does not answer the question.
---

# Load Memory

Start from the task and the project's instructions, including any active user discipline. Reuse context already in the session. On a handoff, the **project profile** (usually `docs/handbook/project-profile.sdoc`) is the starting point for the project's purpose, structure, research routes and current evidence.

## What to consult

| Question | Source |
|---|---|
| What rule applies now? | Read the relevant active decision in StrictDoc. A superseded decision or dated journal entry explains history, not current policy. |
| What still blocks this route? | Read the relevant risk in `docs/project_memory/risks.sdoc` if the project uses it, or the current handoff. Check what evidence would resolve it. |
| Why did we choose this? What did we already try? | Use Claude-Mem's official `mem-search`: search for an index, inspect the timeline around a promising result, then fetch selected observations. |
| What exactly was said before the conversation was compacted? | Use Magic Context to locate and expand the original exchange. |

Claude-Mem's injected summary can already answer a question. When it cannot, use the installed skill or the host's available search, timeline and observation tools; their names vary by host. If the backend is unavailable, use project records or Git and flag a gap only if it affects the decision. Check the current implementation before treating a historical observation as today's behavior. Stop when the evidence is sufficient.
