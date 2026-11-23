---
name: save-mem
description: Keep a consequential fact or milestone when future work needs it. Default to no write. Use for explicit save requests, durable corrections, or a phase conclusion; never mirror a note across memory stores.
---

# Save Memory

Honor an explicit save request in the requested destination. Correct a current norm when a confirmed decision replaces it. Otherwise, if an existing durable source suffices for future work, stop; finishing a task is not a reason to write memory.

- For a fact that will change future work and is not already captured, choose **one** available destination: claude-mem for cross-session recall, or Magic Context for a stable project constraint. Update an existing entry when appropriate. Use `ctx_note` for an explicit reminder; use `discipline` only when the user explicitly invokes it. Never store credentials.
- **Leave StrictDoc untouched by default.** Write there only on explicit request or at a meaningful milestone with a lasting conclusion a human needs: what was achieved or decided, why it matters, and any condition that would change the next decision. A few sentences in the existing node suffice. Link the original evidence only if needed.
- When a settled norm changes, preserve its UID and history, mark the old decision `Superseded`, and link its successor using the project's grammar. Update the `project-profile` when the project's shape, major routes or key conclusions change.
- Keep independent research routes and evidence limits distinct; a paused route is not a disproved hypothesis.
- If a blocker still affects the next decision, keep its consequence and reopening condition in the existing handoff or risk entry. Do not also write a journal entry. Keep specs, requested plans, runbooks and experiment results in their own files; no second summary for memory.
- For a human-facing update use `readable-docs`. After changing `.sdoc` or its configuration run `strictdoc export .` from the docs root. Leave broader historical cleanup to an explicit `consolidator` request.
