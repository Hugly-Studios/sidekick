---
name: review
description: >-
  Review Sidekick code changes. Use when the user says "review", "проверь",
  "ревью", or asks to look over changes before merging.
---

# Code Review

Find **real problems**. `git diff` is the only source of truth. If this is the same chat that wrote the code, warn that a fresh chat is more objective.

## Step 1 — Context

In parallel: `git diff`, `git diff --staged`, `git status`, `ReadLints` on changed files. Do not run `make verify` here unless the user asked — hooks/CI own that.

## Step 2 — Checklist

- Plan conformance
- Logic and error propagation
- Module boundaries: a feature must not talk to the menu bar or CLI
- `activate` / `deactivate` symmetry — system state restored
- Retain cycles (`self` in commands, observers, `Task`)
- Concurrency: MainActor default vs explicit `@concurrent` for background work
- Permission leaks: do not request TCC outside `PermissionsKit` / `FeatureRegistry`
- Private API without a resolve test
- Dead code, unused imports, leftover shims

## Step 3 — Report

```
## Review Results

**Status**: [OK / Has issues / Has critical problems]

### Critical
- `file.swift:42` — …

### Important
- …

### Minor
- …

### Not implemented from plan
- …
```

Do not fix silently. Wait for confirmation.
