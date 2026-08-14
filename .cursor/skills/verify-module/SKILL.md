---
name: verify-module
description: >-
  Prove a Sidekick module works: verify, install, smoke, doctor and logs.
  Use when the user says "проверь модуль", "verify module", or after adding
  a feature.
---

# Verify module

1. `make verify`
2. `make install` if the change touches the app, socket, CLI or feature lifecycle
3. `scripts/smoke.sh` — exit 3 means a human must grant a TCC permission; do not treat that as a code failure
4. `scripts/sidekick.sh features enable <id> --json`
5. `scripts/sidekick.sh run <command.id> --json` for non-destructive commands only
6. `scripts/sidekick.sh doctor --json` — read `permissions`, `warnings`, `failure`
7. `scripts/sidekick.sh logs --json --since 10m --level error`

Do not run commands that change global system state unless the user asked and you pass `--allow-destructive`.
