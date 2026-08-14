#!/usr/bin/env python3
"""Triage helper for the review-pr-comments skill.

Fetches PR review comments/threads/reviews/discussion in one shot, strips bot
noise (walkthroughs, badges, `diff_hunk` snippets, analysis-chain `<details>`
blocks) down to a thread-centric digest ranked for triage, and provides
reply/resolve commands that pick the correct GitHub endpoint automatically
(no more manual REST-id <-> GraphQL-node-id mapping, no more 422s from the
wrong reply endpoint).

The script only does the mechanical parts: fetch, merge, clean, rank, post.
It never decides REAL/NOISE/NEEDS-USER-INPUT — that verification against the
actual code stays with the agent, per the skill's core principle.

Usage:
  pr_review.py fetch <PR> [--repo owner/repo] [--json] [--all]
  pr_review.py sync <PR> [--repo owner/repo] [--dry-run] [--cleanup]
  pr_review.py status <PR> [--repo owner/repo]
  pr_review.py reply <PR> <comment_id> --body-file <path|-> [--resolve] [--dry-run] [--repo owner/repo]
  pr_review.py reply-batch <PR> --plan <path|-> [--dry-run] [--repo owner/repo]
  pr_review.py commit-msg <PR> --plan <path|-> [--repo owner/repo]

Reply/reply-batch bodies may contain `{sha}` — it's replaced with the current
short HEAD at post time, so replies can be drafted before the fix commit exists.
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import dataclasses
import json
import os
import re
import subprocess
import sys
from typing import Any


# --------------------------------------------------------------------------
# gh CLI wrappers
# --------------------------------------------------------------------------

def _run_gh(args: list[str]) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def _parse_concatenated_json(text: str) -> list[Any]:
    """`gh api --paginate` may emit one JSON value per page back-to-back
    instead of a single merged array, depending on the endpoint/version."""
    decoder = json.JSONDecoder()
    values: list[Any] = []
    text = text.strip()
    idx = 0
    while idx < len(text):
        value, end = decoder.raw_decode(text, idx)
        values.append(value)
        idx = end
        while idx < len(text) and text[idx].isspace():
            idx += 1
    return values


def gh_api_array(path: str) -> list[dict]:
    raw = _run_gh(["api", path, "--paginate"])
    items: list[dict] = []
    for value in _parse_concatenated_json(raw):
        items.extend(value) if isinstance(value, list) else items.append(value)
    return items


def gh_api_get(path: str) -> dict | None:
    """GET that returns None only for a genuine 404 (the resource is not of
    this kind — expected during endpoint classification). Any other failure
    (network, auth, 5xx) raises, so a transient error can't be silently
    mistaken for "not found" and reclassify a comment to the wrong endpoint."""
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode != 0:
        stderr = result.stderr or ""
        if "HTTP 404" in stderr or "Not Found" in stderr:
            return None
        raise RuntimeError(f"gh api {path} failed: {stderr.strip()}")
    return json.loads(result.stdout)


def gh_api_post(path: str, body: str) -> dict:
    raw = _run_gh(["api", path, "-X", "POST", "-f", f"body={body}"])
    return json.loads(raw)


def gh_graphql(query: str, **variables: Any) -> dict:
    args = ["api", "graphql", "--paginate", "-f", f"query={query}"]
    for key, value in variables.items():
        flag = "-F" if isinstance(value, int) else "-f"
        args += [flag, f"{key}={value}"]
    raw = _run_gh(args)
    pages = _parse_concatenated_json(raw)
    if len(pages) == 1:
        return pages[0]
    # Fallback for gh versions that don't auto-merge paginated connections:
    # concatenate the reviewThreads.nodes lists ourselves.
    merged = pages[0]
    nodes = merged["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
    for page in pages[1:]:
        nodes.extend(page["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"])
    return merged


def resolve_repo(explicit: str | None) -> str:
    if explicit:
        return explicit
    return _run_gh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).strip()


# --------------------------------------------------------------------------
# Local git (for `sync` — check the PR branch out into an isolated worktree so
# the main checkout, and any uncommitted work in it, is never touched)
# --------------------------------------------------------------------------

WORKTREE_DIRNAME = ".pr-review-worktrees"


def _git(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], capture_output=True, text=True)


def _git_out(args: list[str]) -> str:
    result = _git(args)
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def current_branch() -> str:
    """Branch name, or 'HEAD' when detached."""
    return _git_out(["rev-parse", "--abbrev-ref", "HEAD"])


def tracked_changes() -> bool:
    """True if there are staged/unstaged modifications to *tracked* files."""
    return bool(_git_out(["status", "--porcelain", "--untracked-files=no"]))


def local_branch_exists(branch: str) -> bool:
    return _git(["show-ref", "--verify", "--quiet", f"refs/heads/{branch}"]).returncode == 0


def repo_root() -> str:
    return _git_out(["rev-parse", "--show-toplevel"])


def worktree_path(pr: int) -> str:
    # Kept INSIDE the workspace root so the agent's file tools can edit there,
    # under a dedicated dir that is git-ignored locally (see ensure_local_exclude).
    return os.path.join(repo_root(), WORKTREE_DIRNAME, f"pr-{pr}")


def registered_worktrees() -> dict[str, str]:
    """Map absolute worktree path -> checked-out branch (refs/heads/<b> or '')."""
    out = _git_out(["worktree", "list", "--porcelain"])
    result: dict[str, str] = {}
    path = None
    for line in out.splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
            result[path] = ""
        elif line.startswith("branch ") and path is not None:
            result[path] = line[len("branch "):]
    return result


def ensure_local_exclude() -> None:
    """Add the worktree dir to .git/info/exclude (repo-local, uncommitted) so it
    never shows up in `git status` or gets committed — without touching the
    tracked .gitignore."""
    common = _git_out(["rev-parse", "--git-common-dir"])
    exclude = os.path.join(common, "info", "exclude")
    pattern = f"/{WORKTREE_DIRNAME}/"
    try:
        existing = open(exclude, encoding="utf-8").read() if os.path.exists(exclude) else ""
        if pattern not in existing.split():
            os.makedirs(os.path.dirname(exclude), exist_ok=True)
            with open(exclude, "a", encoding="utf-8") as fh:
                if existing and not existing.endswith("\n"):
                    fh.write("\n")
                fh.write(f"{pattern}\n")
    except OSError:
        pass  # a missing local exclude is cosmetic (dir would just show as untracked)


# --------------------------------------------------------------------------
# Fetching
# --------------------------------------------------------------------------

THREADS_QUERY = """
query($owner:String!,$name:String!,$pr:Int!,$endCursor:String) {
  repository(owner:$owner,name:$name) {
    pullRequest(number:$pr) {
      reviewThreads(first:100, after:$endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          comments(first:100) { nodes { id databaseId } }
        }
      }
    }
  }
}
"""


def fetch_pr_meta(repo: str, pr: int) -> dict:
    raw = _run_gh([
        "pr", "view", str(pr), "--repo", repo,
        "--json", "number,url,state,headRefName,baseRefName,author,title",
    ])
    return json.loads(raw)


def fetch_threads(owner: str, name: str, pr: int) -> list[dict]:
    data = gh_graphql(THREADS_QUERY, owner=owner, name=name, pr=pr)
    return data["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]


def fetch_all(repo: str, pr: int) -> dict:
    owner, name = repo.split("/", 1)
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        meta_f = pool.submit(fetch_pr_meta, repo, pr)
        comments_f = pool.submit(gh_api_array, f"repos/{repo}/pulls/{pr}/comments")
        reviews_f = pool.submit(gh_api_array, f"repos/{repo}/pulls/{pr}/reviews")
        issue_comments_f = pool.submit(gh_api_array, f"repos/{repo}/issues/{pr}/comments")
        threads_f = pool.submit(fetch_threads, owner, name, pr)
        return {
            "meta": meta_f.result(),
            "comments": comments_f.result(),
            "reviews": reviews_f.result(),
            "issue_comments": issue_comments_f.result(),
            "threads": threads_f.result(),
        }


def build_thread_index(threads: list[dict]) -> dict[int, dict]:
    """Map REST comment databaseId -> GraphQL thread node. This is the piece
    that used to be done by hand (cross-referencing two paginated responses)."""
    index: dict[int, dict] = {}
    for node in threads:
        for c in node["comments"]["nodes"]:
            index[c["databaseId"]] = node
    return index


# --------------------------------------------------------------------------
# Noise filtering / body cleaning / priority extraction
# --------------------------------------------------------------------------

NOISE_MARKERS = (
    "<!-- walkthrough_start -->",
    "<!-- pre_merge_checks_walkthrough_start -->",
    "<!-- finishing_touch_checkbox_start -->",
    "<!-- tips_start -->",
    "<!-- CURSOR_SUMMARY -->",
    "<!-- ci-gate-summary -->",
)
NOISE_MARKER_PATTERNS = (
    re.compile(r"<!--\s*[\w-]*-summary\s*-->"),
    re.compile(r"<!--\s*devin-review-badge-"),
    re.compile(r"<!--\s*[\w-]*-badge-"),
    re.compile(r"<!--\s*[\w-]*-ci-[\w-]*\s*-->"),
)


def is_noise_body(body: str) -> bool:
    """True if the body is empty or carries one of the specific auto-generated
    markers in NOISE_MARKERS / NOISE_MARKER_PATTERNS. Presence anywhere is
    sufficient *because these markers only ever appear in fully auto-generated
    comments* (walkthrough/summary/badge/CI wrappers) — a human or a real bot
    finding never embeds one. Arbitrary HTML comments that are NOT in the marker
    set (e.g. a `BUGBOT_BUG_ID` inside a genuine finding) do not match and are
    kept. So this deliberately does not try to detect "marker among real text":
    that case doesn't occur for these markers, and a stricter emptiness check
    would wrongly keep walkthroughs (whose body between the markers is itself
    real-looking prose)."""
    if not body.strip():
        return True
    return any(m in body for m in NOISE_MARKERS) or any(p.search(body) for p in NOISE_MARKER_PATTERNS)


DEVIN_BADGE_MARKERS = re.compile(
    r"<!--\s*devin-review-badge-begin\s*-->.*?<!--\s*devin-review-badge-end\s*-->", re.S
)

# <details> blocks are NOT uniformly noise: CodeRabbit hides genuine root-cause
# explanations ("Mechanism: ...") and proposed-fix diffs behind them, and
# Cursor Bugbot hides "Additional Locations" (other files the same bug
# touches) the same way — deleting all <details> blocks indiscriminately was
# throwing away exactly the evidence the verification pass needs (caught via
# a real Greptile finding on PR #1010 about a missing flush() that a blanket
# strip would have hidden). Only the summaries below are pure bot scaffolding
# with zero triage value; everything else gets unwrapped (tags dropped, inner
# text kept). CodeRabbit review-summary bodies nest these several levels deep
# (per-file -> per-finding -> per-fix), so this needs depth-aware parsing,
# not a single non-greedy regex.
NOISE_DETAILS_SUMMARIES = (
    "prompt for ai agents",
    "prompt for agents",
    "prompt for all review comments",
    "analysis chain",
    "learnings used",
    "code graph analysis results",
    "committable suggestion",  # already pulled out separately by extract_suggestion()
    "review info",
    "run configuration",
    "commits",
    "files selected for processing",
    "files skipped from review",
    "finishing touches",
    "generate unit tests",
    "generate docstrings",
    "autofix (beta)",
    "pre-merge checks",
    "passed checks",
    "walkthrough",
)
DETAILS_OPEN = re.compile(r"<details[^>]*>", re.I)
DETAILS_TAG = re.compile(r"<details[^>]*>|</details>", re.I)
# CodeRabbit nests these inside markdown blockquotes for extra indent, e.g.
# "> <details>\n> <summary>...</summary><blockquote>" — the leading "> " and
# the bare <blockquote> tag aren't whitespace, so the summary match must
# tolerate them or it silently fails and leaks raw HTML into the digest.
SUMMARY_BLOCK = re.compile(r"\A[\s>]*<summary>(.*?)</summary>", re.S)
BLOCKQUOTE_TAG = re.compile(r"</?blockquote>", re.I)
HEADING_TAG = re.compile(r"</?h[1-6]>", re.I)
DIV_TAG = re.compile(r"</?div>", re.I)
# Cursor/Devin "Fix in Cursor" / "Open in Devin Review" buttons: sometimes
# wrapped in a <div>, sometimes a bare <a> — match the link itself so both
# shapes are covered, then drop whatever wrapper <div> is left over.
BADGE_LINK = re.compile(r'<a\s+href="[^"]*(?:cursor\.com|devin\.ai)[^"]*"[^>]*>.*?</a>', re.S | re.I)
GENERIC_LINK = re.compile(r"<a\s+[^>]*>(.*?)</a>", re.S | re.I)


def _is_noise_details_summary(summary: str) -> bool:
    lowered = summary.strip().lower()
    return any(noise in lowered for noise in NOISE_DETAILS_SUMMARIES)


def _find_matching_close(text: str, search_from: int) -> int:
    """search_from points just after an opening <details>; returns the start
    index of its matching </details>, tracking nesting depth."""
    depth = 1
    pos = search_from
    while depth > 0:
        match = DETAILS_TAG.search(text, pos)
        if match is None:
            return len(text)
        depth += 1 if match.group(0).lower().startswith("<details") else -1
        pos = match.end()
    return pos - len("</details>")


def unwrap_details_blocks(text: str) -> str:
    """Recursively drop pure-noise <details> blocks (by summary) and unwrap
    everything else, keeping the inner content but not the <details>/
    <summary> wrapper tags."""
    pieces: list[str] = []
    pos = 0
    while True:
        open_match = DETAILS_OPEN.search(text, pos)
        if open_match is None:
            pieces.append(text[pos:])
            break
        pieces.append(text[pos:open_match.start()])
        close_start = _find_matching_close(text, open_match.end())
        inner = text[open_match.end():close_start]
        after = close_start + len("</details>")

        summary_match = SUMMARY_BLOCK.match(inner)
        summary = summary_match.group(1) if summary_match else ""
        body = inner[summary_match.end():] if summary_match else inner
        body = unwrap_details_blocks(body)  # nested blocks

        pieces.append("" if _is_noise_details_summary(summary) else body.strip())
        pos = after
    return "".join(pieces)


HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)
SUP_BLOCK = re.compile(r"<sup>.*?</sup>", re.S)
IMG_OR_LINKED_IMG = re.compile(r"<a href=\"#\"><img[^>]*></a>|<img[^>]*>")
MARKETING_LINES = re.compile(
    r"^(---\s*)?\*?Was this helpful\?.*$"
    r"|^<sub>.*</sub>$"
    r"|^Comment `@[\w-]+ help`.*$"
    r"|^💡.*$"  # GitHub Copilot's own "Add Copilot custom instructions" footer
    r"|^View \d+ additional finding.*$"  # Devin's "View N additional findings in Devin Review." footer
    r"|^>?\s*_Source: [^_]*_\s*$",  # CodeRabbit provenance footer (Learnings / Coding guidelines / SAST), optionally blockquoted in review bodies
    re.M,
)
SUGGESTION_BLOCK = re.compile(r"```suggestion\n(.*?)```", re.S)

PRIORITY_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r'alt="P0"'), "critical"),
    (re.compile(r'alt="P1"'), "high"),
    (re.compile(r'alt="P2"'), "medium"),
    (re.compile(r'alt="P3"'), "low"),
    (re.compile(r"_🔴 Critical_"), "critical"),
    (re.compile(r"_🟠 Major_"), "high"),
    (re.compile(r"_🟡 Minor_"), "low"),
    (re.compile(r"\*\*High Severity\*\*"), "high"),
    (re.compile(r"\*\*Medium Severity\*\*"), "medium"),
    (re.compile(r"\*\*Low Severity\*\*"), "low"),
    (re.compile(r"^🔴 \*\*", re.M), "critical"),
    (re.compile(r"^🟠 \*\*", re.M), "high"),
    (re.compile(r"^🟡 \*\*", re.M), "low"),
]
PRIORITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "unranked": 4}


def extract_priority(raw_body: str) -> str:
    for pattern, label in PRIORITY_PATTERNS:
        if pattern.search(raw_body):
            return label
    return "unranked"


def extract_suggestion(raw_body: str) -> str | None:
    match = SUGGESTION_BLOCK.search(raw_body)
    return match.group(1).rstrip("\n") if match else None


def clean_body(raw: str) -> str:
    """Strip everything that isn't the reviewer's actual claim: badge divs,
    pure-scaffolding <details> blocks (CodeRabbit's shell-script "Analysis
    chain" dumps are the single biggest source of noise — often 90%+ of a
    comment's bytes) while keeping genuine evidence hidden in other <details>
    blocks (root-cause "Mechanism", "Proposed fix" diffs, Bugbot's "Additional
    Locations"), HTML comment markers, and marketing tails. The
    `<summary>Committable suggestion</summary>` code is extracted separately
    via extract_suggestion() before this runs, then dropped here to avoid
    duplicating it inline."""
    text = DEVIN_BADGE_MARKERS.sub("", raw)
    text = unwrap_details_blocks(text)
    # A body_finding claim is a *slice* of a larger <details> tree, so it can
    # carry an orphan <details>/</details> with no matching partner that
    # unwrap_details_blocks (pair-based) leaves behind. A well-formed body has
    # none of these after unwrap, so stripping leftovers is safe.
    text = DETAILS_TAG.sub("", text)
    text = BLOCKQUOTE_TAG.sub("", text)
    text = HEADING_TAG.sub("", text)
    text = HTML_COMMENT.sub("", text)
    text = SUP_BLOCK.sub("", text)
    text = BADGE_LINK.sub("", text)  # cursor.com/devin.ai buttons, div-wrapped or bare
    text = DIV_TAG.sub("", text)  # leftover wrapper tags around the badge(s) just removed
    text = IMG_OR_LINKED_IMG.sub("", text)  # priority badge icons and any remaining bare <img>
    text = GENERIC_LINK.sub(r"\1", text)  # any other <a href>text</a> -> keep just the text
    text = text.replace("&nbsp;", " ")
    text = MARKETING_LINES.sub("", text)
    # Collapse the empty "> " padding lines left behind once the <details>/
    # <blockquote> tags they used to indent are gone (CodeRabbit nests
    # findings inside markdown blockquotes for extra indentation).
    text = re.sub(r"(?:^>[ \t]*$\n){2,}", ">\n", text, flags=re.M)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def is_bot_login(login: str) -> bool:
    return login.endswith("[bot]") or login == "Copilot"


# --------------------------------------------------------------------------
# Thread-centric model
# --------------------------------------------------------------------------

@dataclasses.dataclass
class ThreadEntry:
    kind: str  # "review_thread" | "review_summary" | "discussion"
    thread_id: str | None
    is_resolved: bool
    is_outdated: bool
    path: str
    line: int | None
    comments: list[dict]  # chronological, raw REST-shaped dicts

    @property
    def root(self) -> dict:
        return self.comments[0]

    @property
    def last(self) -> dict:
        return self.comments[-1]


def group_review_comments(comments: list[dict], thread_index: dict[int, dict]) -> list[ThreadEntry]:
    groups: dict[str, list[dict]] = {}
    order: list[str] = []
    fallback_groups: dict[int, list[dict]] = {}

    for c in comments:
        node = thread_index.get(c["id"])
        if node is None:
            root = c.get("in_reply_to_id") or c["id"]
            fallback_groups.setdefault(root, []).append(c)
            continue
        key = node["id"]
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(c)

    entries: list[ThreadEntry] = []
    for key in order:
        cs = sorted(groups[key], key=lambda c: c["created_at"])
        node = thread_index[cs[0]["id"]]
        entries.append(ThreadEntry(
            kind="review_thread",
            thread_id=node["id"],
            is_resolved=node["isResolved"],
            is_outdated=node["isOutdated"],
            path=cs[0]["path"],
            line=cs[0].get("line") or cs[0].get("original_line"),
            comments=cs,
        ))
    for cs in fallback_groups.values():
        cs = sorted(cs, key=lambda c: c["created_at"])
        entries.append(ThreadEntry(
            kind="review_thread",
            thread_id=None,
            is_resolved=False,
            is_outdated=cs[0].get("position") is None,
            path=cs[0]["path"],
            line=cs[0].get("line") or cs[0].get("original_line"),
            comments=cs,
        ))
    return entries


def reviews_to_entries(reviews: list[dict]) -> list[ThreadEntry]:
    entries = []
    for r in reviews:
        if not r.get("body", "").strip():
            continue  # empty COMMENTED wrapper (the vast majority) — not actionable
        entries.append(ThreadEntry(
            kind="review_summary", thread_id=None, is_resolved=False, is_outdated=False,
            path="(review summary)", line=None,
            comments=[{
                "id": r["id"], "user": r["user"], "body": r["body"],
                "created_at": r["submitted_at"], "html_url": r.get("html_url", ""),
            }],
        ))
    return entries


def issue_comments_to_entries(issue_comments: list[dict], pr_author: str) -> list[ThreadEntry]:
    entries = []
    for c in issue_comments:
        if is_noise_body(c["body"]) or c["user"]["login"] == pr_author:
            continue  # pure walkthroughs, or our own replies posted to this endpoint
        entries.append(ThreadEntry(
            kind="discussion", thread_id=None, is_resolved=False, is_outdated=False,
            path="(discussion)", line=None, comments=[c],
        ))
    return entries


def compute_status(entry: ThreadEntry, pr_author: str) -> str:
    if entry.kind == "review_thread":
        if entry.is_resolved:
            return "resolved"
        if entry.is_outdated:
            return "outdated"
    if entry.last["user"]["login"] == pr_author:
        return "answered_by_author"
    return "open"


def build_record(entry: ThreadEntry, pr_author: str) -> dict:
    root = entry.root
    raw_body = root["body"]
    author = root["user"]["login"]
    replies = [
        {"author": c["user"]["login"], "body": clean_body(c["body"])}
        for c in entry.comments[1:]
    ]
    return {
        "kind": entry.kind,
        "status": compute_status(entry, pr_author),
        "thread_id": entry.thread_id,
        "comment_id": root["id"],
        "path": entry.path,
        "line": entry.line,
        "author": author,
        "is_bot": is_bot_login(author),
        "priority": extract_priority(raw_body),
        "near": [],
        "claim": clean_body(raw_body),
        "suggestion": extract_suggestion(raw_body),
        "replies": replies,
        "reply_count": len(replies),
        "last_author": entry.last["user"]["login"],
        "created_at": root["created_at"],
        "url": root.get("html_url", ""),
    }


# --------------------------------------------------------------------------
# Body-embedded findings (review/issue bodies, not inline threads)
#
# GitHub can only anchor an inline review thread to a line INSIDE the diff, so
# every finding a bot has about code *outside* the diff — CodeRabbit's
# "Outside diff range comments", Devin's "issues in files not directly in the
# diff" — is structurally forced into a review/issue BODY. Those bodies were
# previously shown as one-line "Discussion / PR-level summaries" and never
# triaged, silently dropping real (sometimes Major) bugs. These extractors mine
# them back into first-class, triageable records with a concrete path+line.
#
# Keyed on the structural MARKER, not the bot login (per the skill's
# bot-agnostic principle): any bot reusing the devin marker or the CodeRabbit
# section format is picked up automatically.
# --------------------------------------------------------------------------

DEVIN_FINDING_RE = re.compile(
    r"<!--\s*devin-review-comment\s*(?P<json>\{.*?\})\s*-->(?P<body>.*?)"
    r"(?=<!--\s*devin-review-comment|\Z)",
    re.S,
)
CR_SECTION_RE = re.compile(
    r"<summary>[^<]*?(Outside diff range|Nitpick|Additional|Duplicate)\s+comments\s*\(\d+\)\s*</summary>",
    re.I,
)
CR_FILE_RE = re.compile(
    r"<summary>\s*(?P<path>[\w./+-]+\.[A-Za-z0-9]{1,6})\s*\(\d+\)\s*</summary>"
)
CR_LINE_REF_RE = re.compile(r"`(?P<a>\d+)(?:-\d+)?`:")
CR_SECTION_LABEL = {
    "outside diff range": "outside-diff",
    "nitpick": "nitpick",
    "additional": "additional",
}


def extract_devin_findings(raw_body: str) -> list[dict]:
    """Each Devin finding is delimited by a
    `<!-- devin-review-comment {"file_path","start_line","end_line","id"} -->`
    marker whose JSON carries the exact location. Parsed on the RAW body,
    before clean_body() strips HTML comments."""
    findings = []
    for m in DEVIN_FINDING_RE.finditer(raw_body):
        try:
            meta = json.loads(m.group("json"))
        except json.JSONDecodeError:
            continue
        path = meta.get("file_path")
        if not path:
            continue
        body = m.group("body")
        priority = extract_priority(body)
        if priority == "unranked":
            priority = "high" if str(meta.get("id", "")).startswith("SEC_") else "medium"
        findings.append({
            "path": path,
            "line": meta.get("start_line"),
            "priority": priority,
            "claim": clean_body(body),
            "section": "files-not-in-diff",
        })
    return findings


def extract_coderabbit_findings(raw_body: str) -> list[dict]:
    """CodeRabbit nests findings that aren't posted as inline threads inside
    the review body: `<summary>SECTION comments (N)</summary>` -> per-file
    `<summary>path (n)</summary>` -> ``\\`L1-L2\\`: severity + text``. The
    "Duplicate" section is skipped (those already exist as inline threads)."""
    text = re.sub(r"(?m)^>[ \t]?", "", raw_body)  # drop CodeRabbit's blockquote indentation
    sections = [(m.start(), m.group(1).lower()) for m in CR_SECTION_RE.finditer(text)]
    section_starts = [pos for pos, _ in sections]
    files = list(CR_FILE_RE.finditer(text))
    findings = []
    for i, fm in enumerate(files):
        section = None
        for pos, label in sections:
            if pos < fm.start():
                section = label
            else:
                break
        if section is None or section == "duplicate":
            continue
        region_end = files[i + 1].start() if i + 1 < len(files) else len(text)
        for pos in section_starts:
            if fm.end() < pos < region_end:
                region_end = pos
                break
        region = text[fm.end():region_end]
        refs = list(CR_LINE_REF_RE.finditer(region))
        for j, ref in enumerate(refs):
            seg_end = refs[j + 1].start() if j + 1 < len(refs) else len(region)
            seg = region[ref.start():seg_end]
            priority = extract_priority(seg)
            if priority == "unranked" and "nitpick" in section:
                priority = "low"
            findings.append({
                "path": fm.group("path"),
                "line": int(ref.group("a")),
                "priority": priority,
                "claim": clean_body(seg),
                "section": CR_SECTION_LABEL.get(section, section),
            })
    return findings


def extract_body_findings(raw_body: str) -> list[dict]:
    if DEVIN_FINDING_RE.search(raw_body):
        return extract_devin_findings(raw_body)
    if CR_SECTION_RE.search(raw_body):
        return extract_coderabbit_findings(raw_body)
    return []


def mine_body_findings(
    entries: list[ThreadEntry], thread_records: list[dict]
) -> list[dict]:
    """Turn body-embedded findings from review_summary/discussion entries into
    open body_finding records, deduped against inline threads that already
    cover the exact same spot (same path AND same line). Proximity alone must
    NOT hide a body finding: two findings a few lines apart are routinely
    unrelated bugs, so only an exact location match is treated as a duplicate
    (near-but-not-equal spots stay visible for the verification pass)."""
    thread_spots = [
        (r["path"], r["line"])
        for r in thread_records
        if r["kind"] == "review_thread" and r["line"] is not None
    ]

    def already_inline(path: str, line: int | None) -> bool:
        return line is not None and any(
            path == p and line == pl for p, pl in thread_spots
        )

    out = []
    for entry in entries:
        if entry.kind not in ("review_summary", "discussion"):
            continue
        root = entry.root
        author = root["user"]["login"]
        for f in extract_body_findings(root["body"]):
            if already_inline(f["path"], f["line"]):
                continue
            out.append({
                "kind": "body_finding",
                "status": "open",
                "thread_id": None,
                "comment_id": root["id"],  # parent review/issue comment (reply target)
                "path": f["path"],
                "line": f["line"],
                "author": author,
                "is_bot": is_bot_login(author),
                "priority": f["priority"],
                "near": [],
                "claim": f["claim"],
                "suggestion": None,
                "replies": [],
                "reply_count": 0,
                "last_author": author,
                "created_at": root.get("created_at", ""),
                "url": root.get("html_url", ""),
                "section": f["section"],
                "parent_kind": entry.kind,
            })
    return out


def mark_nearby(records: list[dict]) -> None:
    """Cross-link open threads that sit within 3 lines of each other (same
    file, different authors) via a symmetric `near` list — a *hint* that they
    might be the same finding, NOT a hide. Proximity alone can't prove two
    comments are the same bug (two bots at adjacent lines routinely flag
    unrelated issues), and deciding sameness is a semantic call this script
    must never make — that's the verification pass's job. So nothing is ever
    dropped from triage; the agent verifies near threads together and folds
    them only after reading both claims."""
    by_path: dict[str, list[dict]] = {}
    for r in records:
        if r["kind"] == "review_thread" and r["status"] == "open":
            by_path.setdefault(r["path"], []).append(r)

    for group in by_path.values():
        group.sort(key=lambda r: r["line"] or 0)
        for i, r in enumerate(group):
            for other in group[i + 1:]:
                same_spot = abs((other["line"] or 0) - (r["line"] or 0)) <= 3
                if same_spot and other["author"] != r["author"]:
                    r["near"].append(other["comment_id"])
                    other["near"].append(r["comment_id"])


def collect_records(data: dict) -> list[dict]:
    pr_author = data["meta"]["author"]["login"]
    thread_index = build_thread_index(data["threads"])
    entries = (
        group_review_comments(data["comments"], thread_index)
        + reviews_to_entries(data["reviews"])
        + issue_comments_to_entries(data["issue_comments"], pr_author)
    )
    records = [build_record(e, pr_author) for e in entries]
    records += mine_body_findings(entries, records)
    mark_nearby(records)
    return records


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

STATUS_LABELS = {
    "answered_by_author": "Answered by author (awaiting reviewer)",
    "resolved": "Resolved",
    "outdated": "Outdated",
}


def render_markdown(meta: dict, records: list[dict], show_all: bool) -> str:
    lines = [
        f"# PR #{meta['number']} — {meta['title']}",
        f"State: {meta['state']} | Branch: {meta['headRefName']} -> {meta['baseRefName']} | Author: {meta['author']['login']}",
        "",
    ]

    thread_records = [r for r in records if r["kind"] == "review_thread"]
    body_findings = [r for r in records if r["kind"] == "body_finding"]
    counts = collections.Counter(r["status"] for r in thread_records)
    open_records = [r for r in thread_records if r["status"] == "open"]
    open_records.sort(key=lambda r: (r["is_bot"], PRIORITY_ORDER.get(r["priority"], 9)))
    body_findings.sort(key=lambda r: (r["is_bot"], PRIORITY_ORDER.get(r["priority"], 9)))
    near_count = sum(1 for r in open_records if r["near"])

    lines.append(
        f"Threads: {len(thread_records)} total — "
        f"{len(open_records)} to triage | "
        f"{counts.get('resolved', 0)} resolved | "
        f"{counts.get('answered_by_author', 0)} answered_by_author | "
        f"{counts.get('outdated', 0)} outdated"
        + (f" | {near_count} with nearby thread(s)" if near_count else "")
        + (f" | {len(body_findings)} body finding(s)" if body_findings else "")
    )

    lines.append("")
    lines.append(f"## To triage ({len(open_records)})")
    for n, r in enumerate(open_records, start=1):
        lines.append("")
        lines.append(
            f"{n}. [{r['priority'].upper()}] {r['path']}:{r['line']} — {r['author']} "
            f"(comment={r['comment_id']}, thread={r['thread_id']})"
        )
        if r["near"]:
            near_ids = ", ".join(f"comment={cid}" for cid in r["near"])
            lines.append(f"   (possibly same finding as {near_ids} — verify together, don't assume)")
        for claim_line in r["claim"].splitlines():
            lines.append(f"   {claim_line}")
        for reply in r["replies"]:
            lines.append("")
            lines.append(f"   -- reply by {reply['author']}:")
            for reply_line in reply["body"].splitlines():
                lines.append(f"      {reply_line}")
        if r["suggestion"]:
            lines.append("")
            lines.append("   Suggestion:")
            lines.append("   ```")
            lines.extend(f"   {sug_line}" for sug_line in r["suggestion"].splitlines())
            lines.append("   ```")

    if body_findings:
        lines.append("")
        lines.append(
            f"## Body findings ({len(body_findings)}, verify these too — embedded in a "
            f"review/issue body, not an inline thread; reply goes to the parent review, "
            f"no thread to resolve)"
        )
        for n, r in enumerate(body_findings, start=len(open_records) + 1):
            lines.append("")
            lines.append(
                f"{n}. [{r['priority'].upper()}] {r['path']}:{r['line']} — {r['author']} "
                f"({r['section']}, parent comment={r['comment_id']})"
            )
            for claim_line in r["claim"].splitlines():
                lines.append(f"   {claim_line}")

    discussions = [r for r in records if r["kind"] in ("review_summary", "discussion")]
    if discussions:
        lines.append("")
        lines.append(f"## Discussion / PR-level summaries ({len(discussions)}, context only — not threads to triage)")
        for r in discussions:
            first_line = next((ln for ln in r["claim"].splitlines() if ln.strip()), "")
            lines.append(f"- {r['author']} (comment={r['comment_id']}): {first_line[:200]}")

    if show_all:
        hidden = [r for r in thread_records if r["status"] != "open"]
        if hidden:
            lines.append("")
            lines.append(f"## Hidden by default ({len(hidden)})")
            for r in hidden:
                lines.append(
                    f"- [{STATUS_LABELS[r['status']]}] {r['path']}:{r['line']} — {r['author']} "
                    f"(comment={r['comment_id']}, thread={r['thread_id']})"
                )

    return "\n".join(lines)


# --------------------------------------------------------------------------
# reply/resolve
# --------------------------------------------------------------------------

RESOLVE_MUTATION = """
mutation($t:ID!) {
  resolveReviewThread(input:{threadId:$t}) {
    thread { id isResolved }
  }
}
"""


def classify_comment_target(repo: str, pr: int, comment_id: int) -> tuple[str, dict]:
    line_comment = gh_api_get(f"repos/{repo}/pulls/comments/{comment_id}")
    if line_comment is not None:
        return "line_comment", line_comment
    review = gh_api_get(f"repos/{repo}/pulls/{pr}/reviews/{comment_id}")
    if review is not None:
        return "review", review
    issue_comment = gh_api_get(f"repos/{repo}/issues/comments/{comment_id}")
    if issue_comment is not None:
        return "issue_comment", issue_comment
    raise RuntimeError(f"comment {comment_id} not found as a line comment, review, or issue comment in {repo}")


def find_thread_id(repo: str, pr: int, comment_id: int, index: dict[int, dict] | None = None) -> str | None:
    if index is None:
        owner, name = repo.split("/", 1)
        index = build_thread_index(fetch_threads(owner, name, pr))
    node = index.get(comment_id)
    return node["id"] if node else None


def resolve_thread(thread_id: str) -> None:
    _run_gh(["api", "graphql", "-f", f"t={thread_id}", "-f", f"query={RESOLVE_MUTATION}"])


def short_head_sha() -> str:
    return _git_out(["rev-parse", "--short", "HEAD"])


def inject_sha(body: str) -> str:
    """Replace the {sha} placeholder with the current short HEAD, so a reply
    like 'Fixed in {sha}: ...' can be written before the commit exists and the
    real hash is filled in at post time. Only shells out to git when needed."""
    if "{sha}" not in body:
        return body
    return body.replace("{sha}", short_head_sha())


def reply_endpoint(repo: str, pr: int, comment_id: int, body: str) -> tuple[str, str]:
    """Pick the correct POST endpoint for a comment id and return (path, body).
    The review-summary case gets a 'Re: review #<id>' prefix since its reply is
    a plain issue comment with no thread to anchor it."""
    target, _ = classify_comment_target(repo, pr, comment_id)
    if target == "line_comment":
        return f"repos/{repo}/pulls/{pr}/comments/{comment_id}/replies", body
    if target == "review":
        return f"repos/{repo}/issues/{pr}/comments", f"Re: review #{comment_id} — {body}"
    return f"repos/{repo}/issues/{pr}/comments", body


def perform_reply(
    repo: str,
    pr: int,
    comment_id: int,
    body: str,
    resolve: bool,
    dry_run: bool,
    thread_index: dict[int, dict] | None = None,
) -> dict:
    """Single reply (+ optional resolve). Returns a result dict; never raises
    for an expected per-item failure (so batch runs don't abort midway)."""
    body = body.strip()
    if not body:
        return {"comment_id": comment_id, "ok": False, "error": "empty body"}
    try:
        path, final_body = reply_endpoint(repo, pr, comment_id, body)
        thread_id = find_thread_id(repo, pr, comment_id, thread_index) if resolve else None
        if dry_run:
            return {"comment_id": comment_id, "ok": True, "dry_run": True,
                    "endpoint": path, "body": final_body, "resolve_thread": thread_id}
        result = gh_api_post(path, final_body)
    except RuntimeError as exc:
        return {"comment_id": comment_id, "ok": False, "error": str(exc)}

    # The reply is now posted. A resolve failure from here on must NOT flip the
    # result to ok=False — otherwise a retry re-POSTs the reply and duplicates
    # it. Report the resolve problem as a warning on an otherwise-successful reply.
    out = {"comment_id": comment_id, "ok": True, "url": result.get("html_url", result.get("url", ""))}
    if resolve:
        if thread_id is None:
            out["resolve_warning"] = "comment is not part of a review thread — nothing to resolve"
        else:
            try:
                resolve_thread(thread_id)
                out["resolved_thread"] = thread_id
            except RuntimeError as exc:
                out["resolve_warning"] = f"reply posted, but resolving thread {thread_id} failed: {exc}"
    return out


def read_source(source: str) -> str:
    """Read a `-`-means-stdin path, closing the file handle deterministically."""
    if source == "-":
        return sys.stdin.read()
    with open(source, encoding="utf-8") as fh:
        return fh.read()


def cmd_reply(args: argparse.Namespace) -> None:
    repo = resolve_repo(args.repo)
    body = read_source(args.body_file)
    body = inject_sha(body.strip())
    if not body:
        raise RuntimeError("reply body is empty")

    res = perform_reply(repo, args.pr, args.comment_id, body, args.resolve, args.dry_run)
    if not res["ok"]:
        raise RuntimeError(res["error"])
    if res.get("dry_run"):
        print(f"POST {res['endpoint']}\n---\n{res['body']}\n---")
        if args.resolve:
            print(f"\n(dry-run) would resolve thread: {res['resolve_thread'] or '<none found — comment is not part of a review thread>'}")
        return
    print(f"Replied: {res['url']}")
    if res.get("resolve_warning"):
        print(f"warning: {res['resolve_warning']}", file=sys.stderr)
    elif res.get("resolved_thread"):
        print(f"Resolved thread {res['resolved_thread']}")


def cmd_reply_batch(args: argparse.Namespace) -> None:
    """Post many replies (and resolve REAL threads) from one plan file — the
    repetitive tail of a review session. Plan is a JSON list of items:
        {"comment_id": 123, "resolve": true, "body": "Fixed in {sha}: ... file:line."}
    `resolve` defaults to false (NOISE replies stay open). `{sha}` in any body
    is filled with the current short HEAD once, so replies can be drafted before
    the fix commit exists. Per-item failures are reported, not fatal, so one bad
    id can't strand the rest; exits non-zero if any item failed."""
    repo = resolve_repo(args.repo)
    plan = json.loads(read_source(args.plan))
    if not isinstance(plan, list) or not plan:
        raise RuntimeError("plan must be a non-empty JSON list of {comment_id, body, resolve?} items")

    # Guard against non-object items up front so a malformed element yields a
    # per-item failure instead of an AttributeError that aborts the whole batch.
    def _dicts(items: list) -> list[dict]:
        return [it for it in items if isinstance(it, dict)]

    need_sha = any("{sha}" in (item.get("body") or "") for item in _dicts(plan))
    sha = short_head_sha() if need_sha else None
    # Fetch the thread index once (not once per item) when any item resolves.
    thread_index = None
    if any(item.get("resolve") for item in _dicts(plan)):
        owner, name = repo.split("/", 1)
        thread_index = build_thread_index(fetch_threads(owner, name, pr=args.pr))

    results = []
    for item in plan:
        if not isinstance(item, dict):
            results.append({"comment_id": None, "ok": False, "error": f"plan item is not an object: {item!r}"})
            continue
        cid = item.get("comment_id")
        body = (item.get("body") or "")
        if sha is not None:
            body = body.replace("{sha}", sha)
        if cid is None:
            results.append({"comment_id": None, "ok": False, "error": "missing comment_id"})
            continue
        try:
            cid_int = int(cid)
        except (TypeError, ValueError):
            results.append({"comment_id": cid, "ok": False, "error": f"comment_id is not an integer: {cid!r}"})
            continue
        results.append(perform_reply(repo, args.pr, cid_int, body,
                                     bool(item.get("resolve")), args.dry_run, thread_index))

    failures = 0
    for r in results:
        cid = r["comment_id"]
        if not r["ok"]:
            failures += 1
            print(f"FAIL  {cid}: {r['error']}")
        elif r.get("dry_run"):
            tail = f" + resolve {r['resolve_thread']}" if r.get("resolve_thread") else ""
            print(f"DRY   {cid}: POST {r['endpoint']}{tail}")
        else:
            tail = f" + resolved {r['resolved_thread']}" if r.get("resolved_thread") else ""
            if r.get("resolve_warning"):
                tail = f" (resolve skipped: {r['resolve_warning']})"
            print(f"OK    {cid}: {r['url']}{tail}")
    print(f"\n{len(results) - failures}/{len(results)} succeeded"
          + (f", {failures} failed" if failures else ""))
    if failures:
        sys.exit(1)


# --------------------------------------------------------------------------
# commit-msg — assemble the review commit message (pure formatter, no network)
# --------------------------------------------------------------------------

# GitHub URL fragment per comment kind (the digest's `kind` field). A line
# review comment anchors as #discussion_r<id>; an issue-level discussion as
# #issuecomment-<id>; a review summary as #pullrequestreview-<id>. Defaulting
# every id to discussion_r produces a dead anchor for the latter two.
ANCHOR_BY_KIND = {
    "review_thread": "discussion_r",
    "discussion": "issuecomment-",
    "review_summary": "pullrequestreview-",
}


def cmd_commit_msg(args: argparse.Namespace) -> None:
    """Emit the `review: address PR #<N> comments` commit message with a body
    line per addressed comment, each cc-ing its thread — the exact format step
    8/9 of the skill wants, without hand-building the URLs. Plan is a JSON list
    of {comment_id, fix, file?, kind?} items; `kind` (from the digest) selects
    the right URL anchor and defaults to a line review comment."""
    repo = resolve_repo(args.repo)
    plan = json.loads(read_source(args.plan))
    if not isinstance(plan, list) or not plan:
        raise RuntimeError("plan must be a non-empty JSON list of {comment_id, fix, file?, kind?} items")

    lines = [f"review: address PR #{args.pr} comments", ""]
    for item in plan:
        if not isinstance(item, dict):
            raise RuntimeError(f"plan item is not an object: {item!r}")
        cid = item.get("comment_id")
        fix = (item.get("fix") or "").strip()
        prefix = f"{item['file']}: " if item.get("file") else ""
        anchor = ANCHOR_BY_KIND.get(item.get("kind", "review_thread"), "discussion_r")
        url = f"https://github.com/{repo}/pull/{args.pr}#{anchor}{cid}" if cid else ""
        cc = f" (cc {url})" if url else ""
        lines.append(f"- {prefix}{fix}{cc}")
    print("\n".join(lines))


# --------------------------------------------------------------------------
# fetch/status commands
# --------------------------------------------------------------------------

def cmd_fetch(args: argparse.Namespace) -> None:
    repo = resolve_repo(args.repo)
    data = fetch_all(repo, args.pr)
    records = collect_records(data)

    if args.json:
        print(json.dumps({"meta": data["meta"], "entries": records}, indent=2, ensure_ascii=False))
    else:
        print(render_markdown(data["meta"], records, show_all=args.all))


def cmd_status(args: argparse.Namespace) -> None:
    repo = resolve_repo(args.repo)
    data = fetch_all(repo, args.pr)
    records = [r for r in collect_records(data) if r["kind"] == "review_thread"]

    counts = collections.Counter(r["status"] for r in records)
    print(f"PR #{args.pr}: {len(records)} review threads")
    for status in ("open", "answered_by_author", "resolved", "outdated"):
        print(f"  {status}: {counts.get(status, 0)}")

    open_records = [r for r in records if r["status"] == "open"]
    if open_records:
        print("\nOpen:")
        for r in open_records:
            print(f"  - {r['path']}:{r['line']} — {r['author']} (comment={r['comment_id']})")


# --------------------------------------------------------------------------
# sync command — check the PR branch out into an isolated worktree
# --------------------------------------------------------------------------

def _remove_worktree(wt: str) -> None:
    result = _git(["worktree", "remove", wt])
    if result.returncode != 0:
        raise RuntimeError(
            f"could not remove worktree {wt}: {result.stderr.strip()}. "
            f"If it has uncommitted fixes you still want, commit+push them from there first; "
            f"otherwise `git worktree remove --force {wt}`."
        )
    parent = os.path.dirname(wt)
    if os.path.isdir(parent) and not os.listdir(parent):
        try:
            os.rmdir(parent)
        except OSError:
            pass
    print(f"Removed worktree {wt}")


def cmd_sync(args: argparse.Namespace) -> None:
    """Check the PR head branch out into a dedicated git worktree so the
    verification pass reads the exact code the reviewers saw and fixes land on
    the right branch — WITHOUT touching the main checkout or its uncommitted
    work. No stash, no branch switch in the main tree: the current changes are
    never moved, so they can't end up "lost in a stash".

    The worktree lives at <repo>/.pr-review-worktrees/pr-<N> (inside the
    workspace so file tools can edit it; git-ignored locally so it never
    pollutes `git status`). It shares the object store with the main repo, so
    only tracked working files are duplicated, not history. `--cleanup` removes
    it once the fixes are committed and pushed.

    Special case: if the MAIN checkout is already on the PR branch, there is
    nothing to isolate from — you work there directly (fast-forwarded if clean).
    """
    repo = resolve_repo(args.repo)
    meta = fetch_pr_meta(repo, args.pr)
    branch = meta["headRefName"]
    wt = worktree_path(args.pr)

    if args.cleanup:
        cwd_abs, wt_abs = os.path.abspath(os.getcwd()), os.path.abspath(wt)
        # Compare on path boundaries (cwd == wt or cwd startswith wt + os.sep), not
        # raw string prefix — otherwise cwd inside pr-10 wrongly matches pr-1's path.
        if cwd_abs == wt_abs or cwd_abs.startswith(wt_abs + os.sep):
            raise RuntimeError(f"refusing to remove {wt} while cwd is inside it — cd out first.")
        _remove_worktree(wt)
        return

    if meta["state"] != "OPEN":
        print(f"note: PR #{args.pr} is {meta['state']} — checking it out for verification is fine, "
              f"but replies/pushes to a closed PR are usually pointless.", file=sys.stderr)

    # Main checkout already on the branch → work there, nothing to isolate.
    if current_branch() == branch:
        if args.dry_run:
            print(f"main checkout is already on '{branch}' — would work here directly"
                  + ("" if tracked_changes() else "; would ff-only to latest"))
            return
        fetched = _git(["fetch", "origin", branch])
        if fetched.returncode != 0:
            print(f"warning: couldn't fetch origin/{branch} ({fetched.stderr.strip()}) — "
                  f"verifying against local HEAD, which may be stale.", file=sys.stderr)
            print(f"Main checkout already on '{branch}' (offline; local state left as-is). Work here.")
            return
        if tracked_changes():
            behind = _git(["rev-list", "--count", f"HEAD..origin/{branch}"])
            behind_n = behind.stdout.strip() if behind.returncode == 0 else "0"
            if behind_n not in ("", "0"):
                print(f"warning: local HEAD is {behind_n} commit(s) behind origin/{branch} and can't "
                      f"ff (uncommitted changes present) — verification may read stale code. "
                      f"Commit/stash locally and ff, or verify against the freshest code.", file=sys.stderr)
            print(f"Main checkout already on '{branch}' (uncommitted changes present, left untouched). Work here.")
        else:
            ff = _git(["merge", "--ff-only", f"origin/{branch}"])
            note = "fast-forwarded to latest" if ff.returncode == 0 else "kept local commits (not fast-forwardable)"
            print(f"Main checkout already on '{branch}' ({note}). Work here.")
        return

    # Fetch first so a fork / deleted-branch failure aborts before any mutation.
    fetched = _git(["fetch", "origin", branch])
    if fetched.returncode != 0:
        raise RuntimeError(
            f"cannot fetch origin/{branch} — the PR head is likely on a fork or the branch is gone. "
            f"Check out the PR manually (e.g. `gh pr checkout {args.pr}`) before triaging. "
            f"stderr: {fetched.stderr.strip()}"
        )

    reg = registered_worktrees()
    existing_for_branch = next((p for p, b in reg.items() if b == f"refs/heads/{branch}"), None)

    if args.dry_run:
        if os.path.abspath(wt) in {os.path.abspath(p) for p in reg}:
            print(f"(dry-run) would reuse existing worktree {wt} and ff-only to latest")
        elif existing_for_branch:
            print(f"(dry-run) '{branch}' already checked out at {existing_for_branch} — would reuse it")
        else:
            verb = "check out existing local branch" if local_branch_exists(branch) else "create tracking branch"
            print(f"(dry-run) would {verb} '{branch}' in a new worktree at {wt}, ff-only to origin/{branch}. "
                  f"Main checkout untouched.")
        return

    ensure_local_exclude()

    # Reuse an already-registered worktree for this branch (ours or elsewhere).
    reuse = wt if os.path.abspath(wt) in {os.path.abspath(p) for p in reg} else existing_for_branch
    if reuse:
        ff = _git(["-C", reuse, "merge", "--ff-only", f"origin/{branch}"])
        note = "up to date with origin" if ff.returncode == 0 else "kept local commits (not fast-forwardable)"
        print(f"Reusing worktree for '{branch}' at {os.path.abspath(reuse)} ({note}).")
        print(f"  -> work there:   cd {os.path.abspath(reuse)}")
        print(f"  -> clean up after with: pr_review.py sync {args.pr} --cleanup")
        return

    if os.path.exists(wt):  # leftover dir not registered as a worktree
        _git(["worktree", "prune"])
        if os.path.exists(wt) and os.listdir(wt):
            raise RuntimeError(f"{wt} exists but is not a registered worktree — remove it manually and retry.")

    os.makedirs(os.path.dirname(wt), exist_ok=True)
    if local_branch_exists(branch):
        added = _git(["worktree", "add", wt, branch])
    else:
        added = _git(["worktree", "add", "--track", "-b", branch, wt, f"origin/{branch}"])
    if added.returncode != 0:
        raise RuntimeError(f"git worktree add failed: {added.stderr.strip()}")

    ff = _git(["-C", wt, "merge", "--ff-only", f"origin/{branch}"])
    if ff.returncode != 0:
        print(f"warning: worktree checked out but could not ff to origin/{branch} "
              f"(diverged local branch?): {ff.stderr.strip()} — it may not be at the latest PR head.",
              file=sys.stderr)

    print(f"Checked out '{branch}' in an isolated worktree — main checkout untouched, nothing stashed.")
    print(f"  -> work there:   cd {os.path.abspath(wt)}")
    print("  -> verify / edit / commit / push the fixes from inside that directory")
    print(f"  -> clean up after with: pr_review.py sync {args.pr} --cleanup")


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main() -> None:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--repo", help="owner/repo (default: autodetect from cwd via gh)")

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    fetch_p = sub.add_parser("fetch", parents=[common], help="Fetch and print a triage digest for a PR")
    fetch_p.add_argument("pr", type=int)
    fetch_p.add_argument("--json", action="store_true", help="machine-readable output instead of markdown")
    fetch_p.add_argument("--all", action="store_true", help="also show resolved/outdated/answered_by_author threads")
    fetch_p.set_defaults(func=cmd_fetch)

    sync_p = sub.add_parser("sync", parents=[common], help="Check out the PR branch in an isolated worktree (main checkout untouched)")
    sync_p.add_argument("pr", type=int)
    sync_p.add_argument("--dry-run", action="store_true", help="print what would happen without touching anything")
    sync_p.add_argument("--cleanup", action="store_true", help="remove the PR's worktree (after fixes are committed + pushed)")
    sync_p.set_defaults(func=cmd_sync)

    status_p = sub.add_parser("status", parents=[common], help="Print a short open/answered/resolved summary")
    status_p.add_argument("pr", type=int)
    status_p.set_defaults(func=cmd_status)

    reply_p = sub.add_parser("reply", parents=[common], help="Reply to a comment, auto-selecting the right endpoint")
    reply_p.add_argument("pr", type=int)
    reply_p.add_argument("comment_id", type=int)
    reply_p.add_argument("--body-file", required=True, help="path to the reply body, or - for stdin")
    reply_p.add_argument("--resolve", action="store_true", help="also resolve the review thread this comment belongs to")
    reply_p.add_argument("--dry-run", action="store_true", help="print what would be posted/resolved without doing it")
    reply_p.set_defaults(func=cmd_reply)

    batch_p = sub.add_parser("reply-batch", parents=[common], help="Post many replies (+resolve) from a JSON plan in one run")
    batch_p.add_argument("pr", type=int)
    batch_p.add_argument("--plan", required=True, help="JSON plan file [{comment_id, body, resolve?}, ...], or - for stdin")
    batch_p.add_argument("--dry-run", action="store_true", help="print planned posts/resolves without doing them")
    batch_p.set_defaults(func=cmd_reply_batch)

    commit_p = sub.add_parser("commit-msg", parents=[common], help="Assemble the review commit message from a JSON plan")
    commit_p.add_argument("pr", type=int)
    commit_p.add_argument("--plan", required=True, help="JSON plan file [{comment_id, fix, file?}, ...], or - for stdin")
    commit_p.set_defaults(func=cmd_commit_msg)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
