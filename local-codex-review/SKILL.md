---
name: local-codex-review
description: Run a local code review by delegating to the Codex CLI with explicit git diff context. Use when the user wants review of uncommitted changes, a branch diff, or a specific commit.
---

# Local Codex Review

Use this skill when the user wants a local code review and the review itself
should run through `codex exec` with an explicit target diff.

The wrapper is repo-agnostic. It reviews only the supplied diff or commit
content, writes findings to an artifact, and returns structured findings.

## Required Behavior

1. Do not perform the review in-band unless the wrapper fails.
2. Run `scripts/local_review.sh` immediately.
3. For long-running execution, launch the script in a PTY session and poll it
   until completion instead of issuing one opaque blocking subprocess call.
4. Pass the user's free-form change description through `--context-text` when
   provided.
5. Choose exactly one review target:
- `--uncommitted` for local staged, unstaged, and untracked changes
- `--tracked-head` for tracked-file changes from `git diff HEAD`
- `--base-ref <branch>` for the current branch diff against a base branch
- `--commit <sha>` for one commit
6. Prefer `--uncommitted` when the user does not specify a target.
7. Use `--blocking-only` for implementation-gate reviews unless the user wants
   all severities.
8. After the command finishes, return the findings text or the saved findings
   path, then add a short summary if useful.

## Defaults

- Base branch: `origin/main`
- Sandbox for the subprocess: `read-only`
- Codex profile: unset unless `CODEX_LOCAL_REVIEW_PROFILE` is set
- Model: Codex CLI default unless `CODEX_LOCAL_REVIEW_MODEL` is set
- Reasoning: `medium`
- Findings artifact: `.codex/reports/local_review/<timestamp>_<target>.md`
- JSON artifact: optional via `--json-out`
- `--print-json`: prints the final JSON payload while still writing Markdown
  findings
- The wrapper computes the git diff, runs `codex exec --output-schema`,
  validates the review schema, and renders Markdown findings from the JSON.
- The inner review run is bounded to the supplied diff only. It disables shell
  access and `apply_patch` so the model cannot inspect unrelated files or make
  changes.
- Uncommitted mode includes staged diff, unstaged diff, and untracked text files.
  Binary untracked files are listed but omitted from the patch body.
- `--exclude-path <path-or-glob>` removes generated or already-verified paths
  from the review payload only.
- `--blocking-only` is shorthand for `--min-severity P2`.
- The wrapper fails fast when the patch payload exceeds
  `CODEX_LOCAL_REVIEW_MAX_PATCH_BYTES` or `--max-patch-bytes`.

## Severity Notes

- The shared schema emits `P1`, `P2`, `P3`, and `LOW`.
- The caller or repo workflow decides which severities block.
- A common gate is `P1`/`P2` blocking and `P3`/`LOW` non-blocking.

## Repeated Findings Checkpoint

If two review passes produce similar actionable findings in the same file,
function, invariant, or test seam, stop applying narrow patches. Summarize the
pattern and inspect whether the correct fix is a simpler ownership boundary,
shared helper, fixture redesign, or contract clarification.

## Commands

Run from this repository root, where `local-codex-review/` is present:

```bash
local-codex-review/scripts/local_review.sh \
  --uncommitted \
  --blocking-only \
  --context-text "Review this refactor for regressions in fallback behavior."
```

Branch diff against `origin/main`:

```bash
local-codex-review/scripts/local_review.sh \
  --base-ref origin/main \
  --blocking-only \
  --context-text "Review this branch for missing tests and behavioral regressions." \
  --json-out /tmp/local-review.json
```

Tracked changes only, with JSON to stdout for another script:

```bash
local-codex-review/scripts/local_review.sh \
  --tracked-head \
  --print-json \
  --findings-out /tmp/local-review-findings.md \
  --json-out /tmp/local-review.json
```

Specific commit:

```bash
local-codex-review/scripts/local_review.sh \
  --commit abc1234 \
  --context-text "Check for missing tests and behavioral regressions."
```

## Environment Overrides

- `CODEX_LOCAL_REVIEW_BASE` overrides the default base branch.
- `CODEX_LOCAL_REVIEW_SANDBOX` overrides the subprocess sandbox.
- `CODEX_LOCAL_REVIEW_PROFILE` sets a Codex profile.
- `CODEX_LOCAL_REVIEW_MODEL` sets the model.
- `CODEX_LOCAL_REVIEW_REASONING` overrides the reasoning effort.
- `CODEX_LOCAL_REVIEW_MIN_SEVERITY` overrides the default findings floor.
- `CODEX_LOCAL_REVIEW_HEARTBEAT_SECONDS` overrides progress interval.
- `CODEX_LOCAL_REVIEW_TIMEOUT_SECONDS` overrides subprocess timeout.
- `CODEX_LOCAL_REVIEW_MAX_PATCH_BYTES` overrides the patch payload ceiling.
- `CODEX_LOCAL_REVIEW_TITLE` sets an optional review title for commit reviews.
- `CODEX_LOCAL_REVIEW_FINDINGS_DIR` overrides the findings artifact directory.
- `CODEX_LOCAL_REVIEW_CODEX_BIN` overrides the `codex` binary path.
