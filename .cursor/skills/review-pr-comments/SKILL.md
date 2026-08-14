---
name: review-pr-comments
description: >-
  Triage PR review comments from any review bot and humans. Verify EVERY
  comment by reading the actual code. Use when the user says "посмотри
  комментарии в PR", "разбери ревью", "review comments".
---

# Review PR comments

Zero trust. Authority and P0/Critical badges are sort order, not evidence.

Project lives on GitHub (`Hugly-Studios/sidekick`). Use `gh`.

## Fetch

```bash
python3 .cursor/skills/review-pr-comments/scripts/pr_review.py fetch <N>
python3 .cursor/skills/review-pr-comments/scripts/pr_review.py sync <N>
```

`sync` uses a git worktree and does not stash. If it prints a worktree path, capture:

```bash
PR_REVIEW="$(git rev-parse --show-toplevel)/.cursor/skills/review-pr-comments/scripts/pr_review.py"
```

and work inside that directory, invoking the script by absolute path.

## Verify every comment

Read the cited file ±20 lines. Grep contracts. Attempt a cheap, safe repro when feasible. Verdict: **REAL / NEEDS-USER-INPUT / NOISE**.

REAL requires one concrete input where old and new code diverge. Style-only and speculative comments are NOISE (`minimal-changes`, `verify-before-fixing`).

## Fix, commit, reply

```bash
python3 "$PR_REVIEW" commit-msg <N> --plan - <<'EOF'
[{"comment_id": 123, "file": "Apps/Mac/Sources/Foo.swift", "fix": "…"}]
EOF

python3 "$PR_REVIEW" reply-batch <N> --plan - <<'EOF'
[
  {"comment_id": 123, "resolve": true,  "body": "Fixed in {sha}: …"},
  {"comment_id": 456, "resolve": false, "body": "Verified — already handled at …"}
]
EOF
```

Push before replying so `{sha}` exists on the remote. Do not resolve NOISE threads. Do not auto-reply to NEEDS-USER-INPUT.
