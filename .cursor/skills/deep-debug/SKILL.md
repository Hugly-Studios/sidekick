---
name: deep-debug
description: >-
  Investigate a Sidekick failure using doctor, logs, signing and the control
  socket. Use when the user reports a bug and asks to investigate, check
  logs, or find the root cause.
---

# Deep debug

Identify the symptom, when it started, and whether it is install / permission / socket / feature.

Gather in parallel:

```bash
scripts/sidekick.sh doctor --json
scripts/sidekick.sh status --json
scripts/sidekick.sh logs --json --since 1h --level error
log show --style compact --last 1h --predicate 'subsystem == "com.hugly.sidekick"'
mdfind "kMDItemCFBundleIdentifier == 'com.hugly.sidekick'"
codesign -dv /Applications/Sidekick.app 2>&1
```

Read `doctor.permissions`, `doctor.warnings`, `doctor.signingKind`, `features[].failure`.

Typical causes:

| Evidence | Meaning |
|---|---|
| doctor exit 2 / `notRunning` | app not launched or stale socket |
| signingKind `ad-hoc` | TCC reset on every rebuild |
| missing accessibility | Workspaces (and similar) will not activate |
| several Sidekick.app copies | NSRunningApplication / IPC / TCC confusion |
| symbol-resolve test red | private API gone on this macOS |

Do not guess a fix before naming the evidence. Do not grant TCC yourself — tell the user which pane to open (`settingsURL` in doctor).
