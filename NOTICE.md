NOTICE

The following skills in skills/ are derived from mattpocock/skills
(https://github.com/mattpocock/skills), Copyright (c) Matt Pocock,
licensed under the MIT License:

  - grilling
  - grill-with-docs
  - domain-modeling
  - tdd
  - diagnosing-bugs
  - code-review

The personal Pi UI includes modified MIT-licensed source from:

  - Pi Atelier 0.10.1 (https://github.com/michaelmjhhhh/pi-atelier)
    Source: pi/extensions/ui/atelier/; license: pi/extensions/ui/atelier/LICENSE
  - Pi Zentui 0.24.0 (https://github.com/lmilojevicc/pi-zentui)
    Selected editor/message renderer source: pi/extensions/ui/editor/
    License: pi/extensions/ui/editor/LICENSE

Original copyright notices are retained in those license files.

`context-mode/` builds a **fork of context-mode** (https://github.com/mksglu/context-mode),
licence text at `context-mode/LICENSE-context-mode` (Elastic License 2.0). The built
artifact (which keeps the upstream licence inside it) is **not** committed: it is
published as a GitHub release asset and installed from there, because it is compiled
output rather than reviewable source:

```bash
curl -fsSL https://github.com/brilliantrough/agent-skills/releases/latest/download/pi-context-mode-vendor.tar.gz \
  | tar -xz -C ~/.pi/agent/vendor/context-mode && pi install ~/.pi/agent/vendor/context-mode
```

The fork renames the eleven upstream tools to `ctxm_*`; the upstream names would
collide with `pi-magic-context`'s `ctx_search`, which makes Pi exit on startup.
Reproduce or update the artifacts with `bash context-mode/setup.sh --publish`.

All other files are original works of brilliantrough.
