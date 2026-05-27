from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace


def _load_module():
    script_path = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "pr_codex_review_poll.py"
    )
    spec = importlib.util.spec_from_file_location(
        "pr_codex_review_poll",
        script_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _issue_comment(
    *,
    comment_id: int,
    created_at: str,
    login: str,
    body: str,
) -> dict[str, object]:
    return {
        "id": comment_id,
        "created_at": created_at,
        "html_url": f"https://example.test/comments/{comment_id}",
        "body": body,
        "user": {"login": login},
    }


def _issue_reaction(
    *,
    reaction_id: int,
    created_at: str,
    login: str,
    content: str,
) -> dict[str, object]:
    return {
        "id": reaction_id,
        "created_at": created_at,
        "content": content,
        "user": {"login": login},
    }


def test_plain_review_request_does_not_match_clean_codex_comment():
    module = _load_module()
    comments = [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review",
        ),
        _issue_comment(
            comment_id=2,
            created_at="2026-04-19T13:50:04Z",
            login="chatgpt-codex-connector",
            body="Codex Review: Didn't find any major issues. More of your lovely PRs please.",
        ),
    ]

    matched = module._post_trigger_codex_issue_comments_for_head(
        comments,
        "deadbeef",
    )

    assert matched == []


def test_plain_review_request_is_not_a_head_scoped_request():
    module = _load_module()
    comments = [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review",
        ),
    ]

    requests = module._head_scoped_review_requests_for_head(
        comments,
        "deadbeef",
    )

    assert requests == []


def test_head_scoped_request_matches_clean_codex_comment_for_current_head():
    module = _load_module()
    comments = [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review\n\nHead: deadbeef",
        ),
        _issue_comment(
            comment_id=2,
            created_at="2026-04-19T13:50:04Z",
            login="chatgpt-codex-connector",
            body="Codex Review: Didn't find any major issues.",
        ),
        _issue_comment(
            comment_id=3,
            created_at="2026-04-19T13:51:00Z",
            login="repo-owner",
            body="@codex review",
        ),
    ]

    matched = module._post_trigger_codex_issue_comments_for_head(
        comments,
        "deadbeef",
    )

    assert len(matched) == 1
    assert matched[0]["id"] == 2
    assert matched[0]["matched_review_request"]["id"] == 1
    assert matched[0]["matched_review_request"]["request_mode"] == "head_scoped"
    assert module._has_explicit_clean_issue_comment(matched[0]["body"]) is True


def test_head_scoped_request_ignores_clean_comment_before_latest_head_request():
    module = _load_module()
    comments = [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:00Z",
            login="repo-owner",
            body="@codex review\n\nHead: deadbeef",
        ),
        _issue_comment(
            comment_id=2,
            created_at="2026-04-19T13:46:00Z",
            login="chatgpt-codex-connector",
            body="Codex Review: Didn't find any major issues.",
        ),
        _issue_comment(
            comment_id=3,
            created_at="2026-04-19T13:47:00Z",
            login="repo-owner",
            body="@codex review\n\nHead: deadbeef",
        ),
    ]

    matched = module._post_trigger_codex_issue_comments_for_head(
        comments,
        "deadbeef",
    )

    assert matched == []


def test_head_scoped_request_ignores_older_plain_review_request():
    module = _load_module()
    comments = [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:40:00Z",
            login="repo-owner",
            body="@codex review",
        ),
        _issue_comment(
            comment_id=2,
            created_at="2026-04-19T13:41:00Z",
            login="chatgpt-codex-connector",
            body="Codex Review: Didn't find any major issues.",
        ),
        _issue_comment(
            comment_id=3,
            created_at="2026-04-19T13:45:00Z",
            login="repo-owner",
            body="@codex review\n\nhead deadbeef",
        ),
        _issue_comment(
            comment_id=4,
            created_at="2026-04-19T13:46:00Z",
            login="chatgpt-codex-connector",
            body="Codex Review: Didn't find any major issues.",
        ),
    ]

    matched = module._post_trigger_codex_issue_comments_for_head(
        comments,
        "deadbeef",
    )

    assert [comment["id"] for comment in matched] == [4]
    assert matched[0]["matched_review_request"]["id"] == 3
    assert matched[0]["matched_review_request"]["request_mode"] == "head_scoped"


def test_build_snapshot_reports_missing_head_scoped_request():
    module = _load_module()
    module._repo_owner_name = lambda: ("owner", "repo")
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
        "url": "https://example.test/pull/123",
    }
    module._list_reviews = lambda owner, name, pr_number: []
    module._list_issue_comments = lambda owner, name, pr_number: [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review",
        ),
        _issue_comment(
            comment_id=2,
            created_at="2026-04-19T13:50:04Z",
            login="chatgpt-codex-connector",
            body="Codex Review: Didn't find any major issues.",
        ),
    ]
    module._list_issue_reactions = lambda owner, name, pr_number: []

    snapshot = module._build_snapshot(123, "deadbeef")

    assert snapshot["status"] == "pending"
    assert snapshot["has_head_scoped_review_request_for_head"] is False
    assert snapshot["latest_head_scoped_review_request_for_head"] is None


def test_build_snapshot_reports_present_head_scoped_request():
    module = _load_module()
    module._repo_owner_name = lambda: ("owner", "repo")
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
        "url": "https://example.test/pull/123",
    }
    module._list_reviews = lambda owner, name, pr_number: []
    module._list_issue_comments = lambda owner, name, pr_number: [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review\n\nReview the current PR head deadbeef only.",
        ),
    ]
    module._list_issue_reactions = lambda owner, name, pr_number: []

    snapshot = module._build_snapshot(123, "deadbeef")

    assert snapshot["status"] == "pending"
    assert snapshot["has_head_scoped_review_request_for_head"] is True
    assert snapshot["latest_head_scoped_review_request_for_head"]["id"] == 1


def test_build_snapshot_treats_codex_issue_plus_one_after_head_request_as_no_findings():
    module = _load_module()
    module._repo_owner_name = lambda: ("owner", "repo")
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
        "url": "https://example.test/pull/123",
    }
    module._list_reviews = lambda owner, name, pr_number: []
    module._list_issue_comments = lambda owner, name, pr_number: [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review\n\nReview the current PR head deadbeef only.",
        ),
    ]
    module._list_issue_reactions = lambda owner, name, pr_number: [
        _issue_reaction(
            reaction_id=10,
            created_at="2026-04-19T13:46:00Z",
            login="chatgpt-codex-connector[bot]",
            content="+1",
        ),
    ]

    snapshot = module._build_snapshot(123, "deadbeef")

    assert snapshot["status"] == "no_findings"
    assert snapshot["latest_codex_clean_issue_reaction_for_head"]["content"] == "+1"
    assert (
        snapshot["latest_codex_clean_issue_reaction_for_head"]["matched_review_request"]["id"]
        == 1
    )


def test_build_snapshot_ignores_codex_issue_plus_one_before_latest_head_request():
    module = _load_module()
    module._repo_owner_name = lambda: ("owner", "repo")
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
        "url": "https://example.test/pull/123",
    }
    module._list_reviews = lambda owner, name, pr_number: []
    module._list_issue_comments = lambda owner, name, pr_number: [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review\n\nReview the current PR head deadbeef only.",
        ),
    ]
    module._list_issue_reactions = lambda owner, name, pr_number: [
        _issue_reaction(
            reaction_id=10,
            created_at="2026-04-19T13:45:20Z",
            login="chatgpt-codex-connector[bot]",
            content="+1",
        ),
    ]

    snapshot = module._build_snapshot(123, "deadbeef")

    assert snapshot["status"] == "pending"
    assert snapshot["latest_codex_clean_issue_reaction_for_head"] is None


def test_build_snapshot_ignores_non_codex_issue_plus_one_after_head_request():
    module = _load_module()
    module._repo_owner_name = lambda: ("owner", "repo")
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
        "url": "https://example.test/pull/123",
    }
    module._list_reviews = lambda owner, name, pr_number: []
    module._list_issue_comments = lambda owner, name, pr_number: [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review\n\nReview the current PR head deadbeef only.",
        ),
    ]
    module._list_issue_reactions = lambda owner, name, pr_number: [
        _issue_reaction(
            reaction_id=10,
            created_at="2026-04-19T13:46:00Z",
            login="repo-owner",
            content="+1",
        ),
    ]

    snapshot = module._build_snapshot(123, "deadbeef")

    assert snapshot["status"] == "pending"
    assert snapshot["latest_codex_clean_issue_reaction_for_head"] is None


def test_build_snapshot_keeps_codex_eyes_reaction_pending():
    module = _load_module()
    module._repo_owner_name = lambda: ("owner", "repo")
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
        "url": "https://example.test/pull/123",
    }
    module._list_reviews = lambda owner, name, pr_number: []
    module._list_issue_comments = lambda owner, name, pr_number: [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review\n\nReview the current PR head deadbeef only.",
        ),
    ]
    module._list_issue_reactions = lambda owner, name, pr_number: [
        _issue_reaction(
            reaction_id=10,
            created_at="2026-04-19T13:46:00Z",
            login="chatgpt-codex-connector[bot]",
            content="eyes",
        ),
    ]

    snapshot = module._build_snapshot(123, "deadbeef")

    assert snapshot["status"] == "pending"
    assert snapshot["latest_codex_issue_reaction_for_head"]["content"] == "eyes"


def test_build_snapshot_marks_unknown_codex_issue_reaction_as_ambiguous():
    module = _load_module()
    module._repo_owner_name = lambda: ("owner", "repo")
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
        "url": "https://example.test/pull/123",
    }
    module._list_reviews = lambda owner, name, pr_number: []
    module._list_issue_comments = lambda owner, name, pr_number: [
        _issue_comment(
            comment_id=1,
            created_at="2026-04-19T13:45:21Z",
            login="repo-owner",
            body="@codex review\n\nReview the current PR head deadbeef only.",
        ),
    ]
    module._list_issue_reactions = lambda owner, name, pr_number: [
        _issue_reaction(
            reaction_id=10,
            created_at="2026-04-19T13:46:00Z",
            login="chatgpt-codex-connector[bot]",
            content="confused",
        ),
    ]

    snapshot = module._build_snapshot(123, "deadbeef")

    assert snapshot["status"] == "ambiguous"
    assert snapshot["latest_codex_issue_reaction_for_head"]["content"] == "confused"


def test_poll_stops_when_head_scoped_request_is_missing(capsys):
    module = _load_module()
    module._pr_meta = lambda pr_number: {
        "number": pr_number,
        "headRefOid": "deadbeef",
    }
    module._build_snapshot = lambda pr_number, head_sha: {
        "pr_number": pr_number,
        "head_sha": head_sha,
        "status": "pending",
        "has_head_scoped_review_request_for_head": False,
    }

    result = module._cmd_poll(
        SimpleNamespace(pr=123, head_sha="deadbeef", interval=30, timeout=1800)
    )
    output = json.loads(capsys.readouterr().out)

    assert result == 2
    assert output["status"] == "pending"
    assert output["poll_blocker"] == "missing_head_scoped_review_request"
