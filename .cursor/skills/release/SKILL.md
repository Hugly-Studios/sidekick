---
name: release
description: >-
  Cut a Sidekick release tag. Use when the user says "release", "выпусти",
  or attaches this skill.
---

# Release

1. `make verify` is green.
2. Update `CHANGELOG.md` for the version.
3. Tag `vX.Y.Z` (marketing version). `CURRENT_PROJECT_VERSION` comes from `git rev-list --count HEAD` via `scripts/version.sh` — do not hand-edit it.
4. Push the tag. `.github/workflows/release.yml` builds Release and attaches `Sidekick.app.zip`.

Notarization and Sparkle are **not** in this flow yet. Remaining work is in `docs/releasing.md`: Developer ID, Sparkle, `SUFeedURL`, `SUPublicEDKey`, `generate_appcast`, notarize. Do not pretend those exist.
