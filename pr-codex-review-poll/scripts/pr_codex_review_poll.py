#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from typing import Any

CODEX_LOGIN_PREFIX = "chatgpt-codex-connector"
SEVERITY_BADGE_RE = re.compile(r"\[(P\d)\s+Badge\]", re.IGNORECASE)
TITLE_FROM_BADGE_RE = re.compile(r"Badge\]\([^)]*\)\s*(.+)")
CLEAN_ISSUE_COMMENT_PATTERNS = (
    re.compile(r"^codex review:\s*did(?: not|n't)\s+find\s+(?:any\s+)?major\s+issues\b", re.IGNORECASE),
    re.compile(r"^codex review:\s*no\s+major\s+issues\s+found\b", re.IGNORECASE),
)


class ToolError(RuntimeError):
    pass


def _run(cmd: list[str]) -> str:
    """Run a shell command and raise a structured error on failure."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise ToolError(
            f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr.strip()}"
        )
    return proc.stdout


def _gh_json(args: list[str]) -> Any:
    """Run a single GitHub API call and decode the JSON response."""
    output = _run(["gh", "api", *args])
    return json.loads(output)


def _gh_graphql(query: str, variables: dict[str, Any]) -> Any:
    """Run a GitHub GraphQL query with simple scalar variables."""
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        if value is None:
            continue
        if isinstance(value, int):
            cmd.extend(["-F", f"{key}={value}"])
        else:
            cmd.extend(["-f", f"{key}={value}"])
    output = _run(cmd)
    return json.loads(output)


def _is_codex_login(login: str | None) -> bool:
    return bool(login) and str(login).lower().startswith(CODEX_LOGIN_PREFIX)


def _repo_owner_name() -> tuple[str, str]:
    """Return the current GitHub repo owner/name tuple."""
    data = json.loads(_run(["gh", "repo", "view", "--json", "nameWithOwner"]))
    owner, name = str(data["nameWithOwner"]).split("/", 1)
    return owner, name


def _pr_meta(pr_number: int | None) -> dict[str, Any]:
    """Return PR metadata for an explicit PR number or the current branch PR."""
    args = ["pr", "view"]
    if pr_number is not None:
        args.append(str(pr_number))
    args.extend(["--json", "number,headRefOid,url"])
    output = _run(["gh", *args])
    return json.loads(output)


def _parse_severity(body: str) -> str:
    match = SEVERITY_BADGE_RE.search(body)
    if match:
        return match.group(1).upper()
    lowered = body.lower()
    if " p3 " in f" {lowered} ":
        return "P3"
    if " low " in f" {lowered} ":
        return "LOW"
    return "UNKNOWN"


def _is_blocking_severity(severity: str) -> bool:
    normalized = severity.upper()
    if normalized in {"P1", "P2"}:
        return True
    if normalized in {"P3", "LOW"}:
        return False
    return True


def _extract_title(body: str) -> str:
    """Extract a compact finding title from a Codex review comment body."""
    for raw_line in body.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if "badge" in line.lower():
            match = TITLE_FROM_BADGE_RE.search(line)
            if match:
                title = match.group(1)
                title = re.sub(r"<[^>]+>", " ", title)
                title = re.sub(r"[*_`{}]", "", title).strip()
                if title:
                    return title
        title = re.sub(r"<[^>]+>", " ", line)
        title = re.sub(r"[*_`{}]", "", title).strip()
        if title:
            return title
    return "Codex finding"


def _has_explicit_clean_issue_comment(body: str) -> bool:
    """Match the standard GitHub Codex no-findings top-level PR comment."""
    normalized = " ".join(str(body).split())
    return any(pattern.search(normalized) for pattern in CLEAN_ISSUE_COMMENT_PATTERNS)


def _gh_paginated_json(path: str) -> list[dict[str, Any]]:
    """Fetch a paginated REST collection and flatten the emitted JSON arrays."""
    output = _run(["gh", "api", "--paginate", path])
    payload = output.strip()
    if not payload:
        return []

    decoder = json.JSONDecoder()
    items: list[dict[str, Any]] = []
    index = 0
    while index < len(payload):
        while index < len(payload) and payload[index].isspace():
            index += 1
        if index >= len(payload):
            break
        chunk, next_index = decoder.raw_decode(payload, index)
        if not isinstance(chunk, list):
            raise ToolError(f"Expected paginated GitHub API array for {path}")
        items.extend(item for item in chunk if isinstance(item, dict))
        index = next_index
    return items


def _list_reviews(owner: str, name: str, pr_number: int) -> list[dict[str, Any]]:
    """Return all PR reviews, not just the first REST page."""
    return _gh_paginated_json(f"repos/{owner}/{name}/pulls/{pr_number}/reviews?per_page=100")


def _list_review_comments(owner: str, name: str, pr_number: int) -> list[dict[str, Any]]:
    """Return all PR review comments, not just the first REST page."""
    return _gh_paginated_json(f"repos/{owner}/{name}/pulls/{pr_number}/comments?per_page=100")


def _list_issue_comments(owner: str, name: str, pr_number: int) -> list[dict[str, Any]]:
    """Return top-level PR issue comments, including `@codex review` requests."""
    return _gh_paginated_json(f"repos/{owner}/{name}/issues/{pr_number}/comments?per_page=100")


def _list_issue_reactions(owner: str, name: str, pr_number: int) -> list[dict[str, Any]]:
    """Return reactions on the PR issue body, including Codex no-findings thumbs-up."""
    return _gh_paginated_json(f"repos/{owner}/{name}/issues/{pr_number}/reactions?per_page=100")


def _is_head_scoped_review_request_issue_comment(body: str, head_sha: str) -> bool:
    normalized = str(body).lower()
    return "@codex review" in normalized and head_sha.lower() in normalized


def _issue_comment_metadata(comment: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": int(comment.get("id") or 0),
        "created_at": str(comment.get("created_at") or ""),
        "html_url": str(comment.get("html_url") or ""),
        "body": str(comment.get("body") or ""),
        "login": str((comment.get("user") or {}).get("login") or ""),
    }


def _head_scoped_review_requests_for_head(
    issue_comments: list[dict[str, Any]],
    head_sha: str,
) -> list[dict[str, Any]]:
    """Return non-Codex issue comments that request review for this exact head."""
    ordered_comments = sorted(
        issue_comments,
        key=lambda item: (str(item.get("created_at") or ""), int(item.get("id") or 0)),
    )
    matched: list[dict[str, Any]] = []
    for comment in ordered_comments:
        login = str((comment.get("user") or {}).get("login") or "")
        body = str(comment.get("body") or "")
        if _is_codex_login(login):
            continue
        if not _is_head_scoped_review_request_issue_comment(body, head_sha):
            continue
        request = _issue_comment_metadata(comment)
        request["request_mode"] = "head_scoped"
        matched.append(request)
    return matched


def _post_trigger_codex_issue_comments_for_head(
    issue_comments: list[dict[str, Any]],
    head_sha: str,
) -> list[dict[str, Any]]:
    """Collect Codex PR issue comments that follow a head-scoped review request."""
    ordered_comments = sorted(
        issue_comments,
        key=lambda item: (str(item.get("created_at") or ""), int(item.get("id") or 0)),
    )
    head_scoped_requests = _head_scoped_review_requests_for_head(
        issue_comments,
        head_sha,
    )
    if not head_scoped_requests:
        return []

    latest_trigger = head_scoped_requests[-1]
    latest_trigger_key = (
        str(latest_trigger.get("created_at") or ""),
        int(latest_trigger.get("id") or 0),
    )

    matched: list[dict[str, Any]] = []
    for comment in ordered_comments:
        comment_key = (
            str(comment.get("created_at") or ""),
            int(comment.get("id") or 0),
        )
        if comment_key <= latest_trigger_key:
            continue
        login = str((comment.get("user") or {}).get("login") or "")
        if not _is_codex_login(login):
            continue
        comment_meta = _issue_comment_metadata(comment)
        comment_meta["matched_review_request"] = dict(latest_trigger)
        matched.append(comment_meta)
    return matched


def _reaction_metadata(reaction: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": int(reaction.get("id") or 0),
        "created_at": str(reaction.get("created_at") or ""),
        "content": str(reaction.get("content") or ""),
        "login": str((reaction.get("user") or {}).get("login") or ""),
    }


def _post_trigger_codex_issue_reactions_for_request(
    reactions: list[dict[str, Any]],
    latest_trigger: dict[str, Any] | None,
) -> list[dict[str, Any]]:
    """Collect Codex reactions on the PR body after the latest head-scoped request."""
    if latest_trigger is None:
        return []

    latest_trigger_created_at = str(latest_trigger.get("created_at") or "")
    if not latest_trigger_created_at:
        return []

    matched: list[dict[str, Any]] = []
    for reaction in sorted(
        reactions,
        key=lambda item: (str(item.get("created_at") or ""), int(item.get("id") or 0)),
    ):
        created_at = str(reaction.get("created_at") or "")
        if not created_at:
            continue
        # GitHub reaction timestamps are second-granularity. Treat same-second
        # reactions as post-trigger so a fast Codex thumbs-up is not missed.
        if created_at < latest_trigger_created_at:
            continue
        login = str((reaction.get("user") or {}).get("login") or "")
        if not _is_codex_login(login):
            continue
        reaction_meta = _reaction_metadata(reaction)
        reaction_meta["matched_review_request"] = dict(latest_trigger)
        matched.append(reaction_meta)
    return matched


def _is_clean_codex_issue_reaction(reaction: dict[str, Any]) -> bool:
    return str(reaction.get("content") or "") == "+1"


def _is_progress_codex_issue_reaction(reaction: dict[str, Any]) -> bool:
    return str(reaction.get("content") or "").lower() == "eyes"


def _list_review_threads(owner: str, name: str, pr_number: int) -> list[dict[str, Any]]:
    """Return every review thread so findings can include thread status and URLs."""
    query = """
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          isResolved
          path
          comments(first: 100) {
            nodes {
              databaseId
              url
              author {
                login
              }
            }
          }
        }
      }
    }
  }
}
""".strip()
    threads: list[dict[str, Any]] = []
    after: str | None = None
    while True:
        payload = _gh_graphql(
            query,
            {"owner": owner, "name": name, "number": pr_number, "after": after},
        )
        review_threads = (
            payload.get("data", {})
            .get("repository", {})
            .get("pullRequest", {})
            .get("reviewThreads", {})
        )
        nodes = review_threads.get("nodes") or []
        if isinstance(nodes, list):
            threads.extend(nodes)
        page_info = review_threads.get("pageInfo") or {}
        if not page_info.get("hasNextPage"):
            break
        after = page_info.get("endCursor")
    return threads


def _thread_comment_map(threads: list[dict[str, Any]]) -> dict[int, dict[str, Any]]:
    """Index thread metadata by review comment database id."""
    by_comment_id: dict[int, dict[str, Any]] = {}
    for thread in threads:
        path = str(thread.get("path") or "")
        is_resolved = bool(thread.get("isResolved"))
        comments = ((thread.get("comments") or {}).get("nodes") or [])
        for comment in comments:
            database_id = comment.get("databaseId")
            if isinstance(database_id, int):
                by_comment_id[database_id] = {
                    "thread_id": str(thread.get("id") or ""),
                    "thread_path": path,
                    "thread_is_resolved": is_resolved,
                    "comment_url": str(comment.get("url") or ""),
                }
    return by_comment_id


def _build_snapshot(pr_number: int, head_sha: str | None = None) -> dict[str, Any]:
    """Build a head-scoped view of Codex findings for a PR.

    The result is intentionally fail-closed: if a Codex-authored comment cannot be
    mapped to a known low-severity badge, it remains blocking so the caller does
    not silently ignore an important review finding.
    """
    owner, name = _repo_owner_name()
    pr_meta = _pr_meta(pr_number)
    resolved_pr_number = int(pr_meta["number"])
    effective_head_sha = head_sha or str(pr_meta["headRefOid"])
    current_head_sha = str(pr_meta["headRefOid"])

    reviews = _list_reviews(owner, name, resolved_pr_number)
    codex_reviews: list[dict[str, Any]] = []
    for review in reviews:
        login = str((review.get("user") or {}).get("login") or "")
        if not _is_codex_login(login):
            continue
        codex_reviews.append(
            {
                "id": int(review.get("id") or 0),
                "commit_oid": str(review.get("commit_id") or ""),
                "state": str(review.get("state") or ""),
                "submitted_at": str(review.get("submitted_at") or ""),
                "html_url": str(review.get("html_url") or ""),
                "login": login,
                "body": str(review.get("body") or ""),
            }
        )
    codex_reviews = sorted(codex_reviews, key=lambda item: (item["submitted_at"], item["id"]))

    latest_for_head: dict[str, Any] | None = None
    for review in codex_reviews:
        if review["commit_oid"] == effective_head_sha:
            latest_for_head = review

    issue_comments = _list_issue_comments(owner, name, resolved_pr_number)
    head_scoped_review_requests_for_head = _head_scoped_review_requests_for_head(
        issue_comments,
        effective_head_sha,
    )
    latest_head_scoped_review_request_for_head = (
        head_scoped_review_requests_for_head[-1]
        if head_scoped_review_requests_for_head
        else None
    )
    post_trigger_codex_issue_comments_for_head = _post_trigger_codex_issue_comments_for_head(
        issue_comments,
        effective_head_sha,
    )
    issue_reactions = (
        _list_issue_reactions(owner, name, resolved_pr_number)
        if latest_head_scoped_review_request_for_head is not None
        else []
    )
    post_trigger_codex_issue_reactions_for_head = _post_trigger_codex_issue_reactions_for_request(
        issue_reactions,
        latest_head_scoped_review_request_for_head,
    )

    findings_for_head: list[dict[str, Any]] = []
    if latest_for_head is not None:
        comments = _list_review_comments(owner, name, resolved_pr_number)
        threads = _list_review_threads(owner, name, resolved_pr_number)
        thread_map = _thread_comment_map(threads)
        review_id = latest_for_head["id"]
        for comment in comments:
            login = str((comment.get("user") or {}).get("login") or "")
            if not _is_codex_login(login):
                continue
            comment_review_id = int(comment.get("pull_request_review_id") or 0)
            if comment_review_id != review_id:
                continue
            comment_id = int(comment.get("id") or 0)
            body = str(comment.get("body") or "")
            severity = _parse_severity(body)
            thread_info = thread_map.get(comment_id, {})
            findings_for_head.append(
                {
                    "comment_id": comment_id,
                    "review_id": comment_review_id,
                    "thread_id": str(thread_info.get("thread_id") or ""),
                    "thread_path": str(thread_info.get("thread_path") or ""),
                    "thread_is_resolved": bool(thread_info.get("thread_is_resolved")),
                    "severity": severity,
                    "blocking": _is_blocking_severity(severity),
                    "title": _extract_title(body),
                    "path": str(comment.get("path") or ""),
                    "line": comment.get("line"),
                    "url": str(comment.get("html_url") or ""),
                    "body": body,
                }
            )
    findings_for_head = sorted(
        findings_for_head,
        key=lambda item: (
            str(item.get("path") or ""),
            int(item.get("line") or 0),
            int(item.get("comment_id") or 0),
        ),
    )

    latest_codex_issue_comment_for_head: dict[str, Any] | None = None
    latest_codex_clean_issue_comment_for_head: dict[str, Any] | None = None
    latest_codex_issue_reaction_for_head: dict[str, Any] | None = None
    latest_codex_clean_issue_reaction_for_head: dict[str, Any] | None = None
    if post_trigger_codex_issue_comments_for_head:
        latest_codex_issue_comment_for_head = post_trigger_codex_issue_comments_for_head[-1]
        for comment in post_trigger_codex_issue_comments_for_head:
            if _has_explicit_clean_issue_comment(str(comment.get("body") or "")):
                latest_codex_clean_issue_comment_for_head = comment
    if post_trigger_codex_issue_reactions_for_head:
        latest_codex_issue_reaction_for_head = post_trigger_codex_issue_reactions_for_head[-1]
        for reaction in post_trigger_codex_issue_reactions_for_head:
            if _is_clean_codex_issue_reaction(reaction):
                latest_codex_clean_issue_reaction_for_head = reaction

    blocking_count = sum(1 for finding in findings_for_head if finding["blocking"])
    non_blocking_count = len(findings_for_head) - blocking_count
    if findings_for_head:
        status = "findings"
    elif (
        latest_codex_clean_issue_comment_for_head is not None
        or latest_codex_clean_issue_reaction_for_head is not None
    ):
        status = "no_findings"
    elif latest_codex_issue_comment_for_head is not None or (
        latest_codex_issue_reaction_for_head is not None
        and not _is_progress_codex_issue_reaction(latest_codex_issue_reaction_for_head)
    ):
        status = "ambiguous"
    else:
        status = "pending"
    has_head_scoped_review_request_for_head = (
        latest_head_scoped_review_request_for_head is not None
    )

    return {
        "repo": f"{owner}/{name}",
        "pr_number": resolved_pr_number,
        "pr_url": str(pr_meta.get("url") or ""),
        "head_sha": effective_head_sha,
        "status": status,
        "current_pr_head_sha": current_head_sha,
        "latest_codex_review_for_head": latest_for_head,
        "has_head_scoped_review_request_for_head": has_head_scoped_review_request_for_head,
        "latest_head_scoped_review_request_for_head": latest_head_scoped_review_request_for_head,
        "head_scoped_review_requests_for_head": head_scoped_review_requests_for_head,
        "post_trigger_codex_issue_comments_for_head": post_trigger_codex_issue_comments_for_head,
        "post_trigger_codex_issue_reactions_for_head": post_trigger_codex_issue_reactions_for_head,
        "latest_codex_issue_comment_for_head": latest_codex_issue_comment_for_head,
        "latest_codex_clean_issue_comment_for_head": latest_codex_clean_issue_comment_for_head,
        "latest_codex_issue_reaction_for_head": latest_codex_issue_reaction_for_head,
        "latest_codex_clean_issue_reaction_for_head": latest_codex_clean_issue_reaction_for_head,
        "findings_for_head": findings_for_head,
        "counts": {
            "findings": len(findings_for_head),
            "blocking": blocking_count,
            "non_blocking": non_blocking_count,
        },
    }


def _cmd_snapshot(args: argparse.Namespace) -> int:
    """Print a single head-scoped snapshot and exit."""
    pr_meta = _pr_meta(args.pr)
    pr_number = int(pr_meta["number"])
    snapshot = _build_snapshot(pr_number, args.head_sha)
    print(json.dumps(snapshot, indent=2, sort_keys=True))
    return 0


def _cmd_poll(args: argparse.Namespace) -> int:
    """Poll until Codex reviews the target head or the timeout expires."""
    pr_meta = _pr_meta(args.pr)
    pr_number = int(pr_meta["number"])
    head_sha = args.head_sha or str(pr_meta["headRefOid"])
    start = time.monotonic()
    interval = int(args.interval)
    timeout = int(args.timeout)

    while True:
        snapshot = _build_snapshot(pr_number, head_sha)
        if snapshot["status"] != "pending":
            print(json.dumps(snapshot, indent=2, sort_keys=True))
            return 0
        if not snapshot.get("has_head_scoped_review_request_for_head"):
            snapshot["poll_blocker"] = "missing_head_scoped_review_request"
            print(json.dumps(snapshot, indent=2, sort_keys=True))
            return 2

        elapsed = time.monotonic() - start
        if elapsed >= timeout:
            snapshot["poll_timeout_seconds"] = timeout
            print(json.dumps(snapshot, indent=2, sort_keys=True))
            return 2

        print(
            f"waiting for codex review on head {head_sha} (elapsed={int(elapsed)}s)",
            file=sys.stderr,
        )
        time.sleep(interval)


def _build_parser() -> argparse.ArgumentParser:
    """Build the CLI parser for the snapshot and poll subcommands."""
    parser = argparse.ArgumentParser(description="Read-only PR Codex review poll helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot = subparsers.add_parser("snapshot", help="Print head-scoped Codex review snapshot")
    snapshot.add_argument("--pr", type=int, default=None, help="PR number (defaults to current branch PR)")
    snapshot.add_argument("--head-sha", default=None, help="Target head sha (defaults to PR head)")
    snapshot.set_defaults(func=_cmd_snapshot)

    poll = subparsers.add_parser("poll", help="Poll until Codex review exists for target head sha")
    poll.add_argument("--pr", type=int, default=None, help="PR number (defaults to current branch PR)")
    poll.add_argument("--head-sha", default=None, help="Target head sha (defaults to PR head)")
    poll.add_argument("--interval", type=int, default=30, help="Polling interval seconds")
    poll.add_argument("--timeout", type=int, default=1800, help="Polling timeout seconds")
    poll.set_defaults(func=_cmd_poll)

    return parser


def main() -> int:
    """Entrypoint for the read-only Codex review polling helper."""
    parser = _build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except ToolError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
