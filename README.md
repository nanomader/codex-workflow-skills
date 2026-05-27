# Codex Workflow Skills

Reusable Codex skills for repository workflows: prompt rewriting, bug triage,
decision scouting, local review, implementation planning, and PR review polling.

## Skills

- `anti-hivemind-prompt-rewriter`: rewrites prompts so they produce less
  generic answers. Use it for strategy, product, coding, writing, or personal
  prompts where you want clearer assumptions and more distinct options.
- `bug-triage-analysis`: checks whether a bug report is real before changing
  code. Use it when you want evidence, likely root cause, fix options, and a
  plan-ready handoff.
- `decision-gap-scout`: finds important unanswered decisions in docs or plans.
  Use it before implementation when you want to know what still needs to be
  decided.
- `local-codex-review`: runs a bounded local review of a git diff through
  Codex. Use it for uncommitted changes, branch diffs, or a single commit.
- `plan-author-review-loop`: creates or revises an implementation plan and
  reviews it against the current repo. Use it before coding when the work needs
  a clear plan.
- `pr-codex-review-poll`: waits for GitHub Codex review results on the current
  PR head. Use it after a head-scoped `@codex review` request has already been
  posted.

## License

MIT. You can use, modify, distribute, and sell work based on these skills as
long as the license notice is preserved.
