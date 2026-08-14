---
name: ship-pr
description: >-
  Ship current changes as a PR — never uses git stash. Only use when the user
  explicitly attaches this skill or says "create PR", "open PR", "создай PR",
  "ship-pr". Do NOT trigger on "запуш" or "отправь" alone.
---

# Ship PR

Take the current changes and open a GitHub PR. **Never uses `git stash`.**

## Step 1 — Look at the whole diff

```bash
git status --porcelain
git diff
git log --oneline origin/main..HEAD 2>/dev/null
```

If the working tree is clean AND there are no commits ahead of `origin/main` — stop.

If the working tree is clean but there ARE commits ahead of `origin/main`, skip classification and open/push the existing branch.

## Step 2 — Classify

| Situation | Flow |
|---|---|
| The whole diff belongs to this task | In-place: `git fetch origin main && git switch -c <branch> origin/main` |
| Other in-progress files must stay dirty | Ask the user. Do not stash. |
| Ownership unclear | Ask via `AskQuestion` |

Branch prefixes: `feat/`, `fix/`, `chore/`, `refactor/`.

## Step 3 — Commit, push, PR

```bash
git add <relevant files>
git commit -m "$(cat <<'EOF'
type(scope): short summary

Optional body.
EOF
)"
git push -u origin HEAD
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
- Why this change was needed
- What approach was taken

## Test plan
- [ ] make verify
- [ ] make install && scripts/smoke.sh (if CLI/lifecycle changed)
EOF
)"
```

Do not force-push. Do not include `Config/Signing.local.xcconfig` or secrets. Do not pass `--no-verify` to `git push` — `lefthook.yml` pre-push runs `make verify`.
