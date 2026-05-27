---
name: pr-codex-review-poll
description: Poll GitHub for Codex review comments on the current PR head, display head-scoped findings, explain each finding in plain language, and stop before verification or fixes.
metadata:
  short-description: Read-only poller for head-scoped Codex PR review findings
---

# PR Codex Review Poll

## When to Use

Use this skill after a head-scoped GitHub Codex review request has already been
posted on an open PR and you want to:

- wait for GitHub Codex to review the exact current PR head
- display findings for that head only
- explain each finding in plain language
- stop before bug verification, fixes, replies, or thread resolution

If the next step is deciding whether a finding is real, hand it off to
`bug-triage-analysis`.

## Locked Behavior

1. Read-only only.
- Do not edit files.
- Do not reply on GitHub.
- Do not resolve review threads.
- Do not post `@codex review`; assume the owning PR workflow already did that.
- Do not repair a missing or plain review request. Report the missing
  precondition and stop.

2. Head-scoped only.
- Only consume Codex review output tied to the exact current PR head SHA.
- Ignore older Codex review cycles on earlier commits.
- A clean top-level Codex comment counts only when it follows a request comment
  that includes the exact target head SHA.
- A Codex-authored `+1` reaction on the PR issue body also counts as clean only
  when it was created after the latest request comment for the exact head SHA.
- A Codex-authored `eyes` reaction is progress only. Keep polling.
- Plain `@codex review` requests do not satisfy this poller contract.
- Short-SHA requests do not satisfy this poller contract. The request must
  include the full 40-character head SHA.
- Extra prose around `@codex review` is not reliable control input for GitHub
  Codex Review. Treat it as human context only.

3. Defaults.
- Poll every 30 seconds.
- Timeout after 30 minutes.
- Severity mapping:
  - `P1`, `P2` => blocking
  - `P3`, `LOW` => non-blocking
  - unknown/unparsed => blocking

## Required Tools

- authenticated `gh`
- `python3`

## Helper Script

Run the helper relative to this repository root:

```bash
python3 pr-codex-review-poll/scripts/pr_codex_review_poll.py snapshot --pr <number>
python3 pr-codex-review-poll/scripts/pr_codex_review_poll.py poll --pr <number> --head-sha <sha> --interval 30 --timeout 1800
```

If the current working directory is the skill directory itself, use:

```bash
python3 scripts/pr_codex_review_poll.py snapshot --pr <number>
python3 scripts/pr_codex_review_poll.py poll --pr <number> --head-sha <sha> --interval 30 --timeout 1800
```

## Workflow

1. Identify the PR and current head SHA.
- Run `snapshot`.
- If `--pr` is omitted, the script uses the current branch PR.

2. Confirm a head-scoped review request already exists.
- A valid request includes the full head SHA:

```text
@codex review

Review the current PR head <sha> only.
```

- Check `has_head_scoped_review_request_for_head`.
- If no head-scoped request exists, stop and report the missing precondition.
- If a short-SHA request exists, report that the owning workflow should edit or
  replace it with the full SHA.

3. Poll until GitHub Codex responds for that exact head SHA.

4. Interpret the result.
- `status=pending`: Codex has not returned head-scoped findings or a recognized
  clean response yet.
- `status=no_findings`: Codex returned a recognized clean response for the exact
  head.
- `status=findings`: list every finding with severity, title, path/line, URL,
  and a one-sentence explanation of the claimed risk.
- `status=ambiguous`: Codex responded, but the response did not satisfy the
  clean or findings contract. Report the ambiguity and stop.

5. Stop.
- Do not decide whether findings are correct in this skill.
- Do not fix code in this skill.

## Output Expectations

1. PR number and head SHA reviewed
2. Poll status: `pending | no_findings | findings | ambiguous`
3. If findings exist, one flat bullet per finding with severity, title,
   path/line, URL, and a plain-language explanation

## Notes

- This skill only reports what Codex said for the current PR head.
- The PR creation or implementation workflow owns posting the review request.
