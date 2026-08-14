---
name: new-module
description: >-
  Scaffold a Sidekick feature module. Use when the user says "new module",
  "добавь модуль", "make new-module", or attaches this skill.
---

# New module

1. Confirm the PascalCase name (`Awake`, `Dictation`). Do not invent a second name.
2. Run `make new-module NAME=<Name>`. Do not create the files by hand unless the generator cannot express a needed dependency.
3. Fill in `descriptor` (title, summary, symbol, `requiredPermissions`).
4. Inject system seams through the designated init. Live types only in `convenience init(context:)`.
5. Register nothing else: `Project.swift` and `AppEnvironment.featureTypes` are already patched.
6. Follow [Features/AGENTS.md](../../../Features/AGENTS.md).
7. `make generate` then `make verify`. If the module has a command the agent can safely run: `make install` and `scripts/smoke.sh`.
