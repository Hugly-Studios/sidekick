---
name: ship-and-merge
description: >-
  Ship a PR and enable squash auto-merge. Use when the user says
  "ship and merge", "создай PR и смерджи", "автомердж".
---

# Ship & Merge

1. Follow [ship-pr](../ship-pr/SKILL.md) in full.
2. Enable auto-merge:

```bash
gh pr merge --auto --squash
```

3. Return the PR URL. Note that merge waits on the CI `Verify` check.

If `gh pr merge --auto` fails with "auto-merge is not allowed", tell the user to enable it in repo settings.
