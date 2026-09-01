---
name: quick-do
description: Execute a simple, well-scoped task directly in this session with zero ceremony — no plan documents, no grilling, no TDD, no test scripts. Use when the user cues this skill for a small task (batch text edits across files, a config tweak, a one-off script, a small refactor). Ponytail taste throughout.
---

# Quick Do: understand → do → done

For simple tasks the user explicitly cues. The whole job fits in this session.

## Rules

- Ask AT MOST one clarifying question, and only if the task is genuinely ambiguous. Prefer the obvious interpretation and proceed.
- No plan documents, no grilling sessions, no sub-agents. Todo list only if there are more than ~5 distinct steps.
- Survey only what the task touches: glob/read the target files first, then act. Do not explore the wider codebase.
- Ponytail taste: minimum code that works. No over-encapsulation, no defensive programming, no redundant re-validation, no speculative abstraction. Deletion over addition; boring over clever.
- No tests, no TDD, no verification scripts. The change running without errors IS the verification; the user checks the result themselves.
- Single exception: destructive or irreversible operations (bulk overwrite/delete) — show what will change and get a nod before doing it.
- When done: one line stating what changed. No essay, no summary section.
