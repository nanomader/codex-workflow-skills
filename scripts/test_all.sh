#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

bash local-codex-review/scripts/test_local_review.sh
bash plan-author-review-loop/scripts/test_plan_review.sh

if command -v pytest >/dev/null 2>&1; then
  pytest -q pr-codex-review-poll/tests/test_pr_codex_review_poll.py
elif python3 -m pytest --version >/dev/null 2>&1; then
  python3 -m pytest -q pr-codex-review-poll/tests/test_pr_codex_review_poll.py
else
  echo "pytest is required for pr-codex-review-poll tests." >&2
  exit 2
fi
