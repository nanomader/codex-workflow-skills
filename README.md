# Codex Workflow Skills

Bounded Codex repo work, one inspectable slice at a time.

This repo is a starter kit for making long-running Codex-assisted repository
work scoped, inspectable, and less chat-shaped. It combines reusable Codex
skills with workflow templates for plans, diffs, review artifacts, exact-head
PR polling, and stop rules.

It is not:

- a claim that AI replaces code review;
- a benchmark suite;
- a complete orchestration framework;
- permission to let an agent patch indefinitely.

It is:

- operating contracts such as `AGENTS.md` and `README.md`;
- lane markdown for broad goals;
- one selected slice at a time;
- explicit plan and diff packets;
- deterministic validation before expensive review;
- schema-validated review artifacts;
- head-scoped PR review polling;
- review-churn stop rules.

## The Problem

Long-running agent work fails when the goal stays broad, the boundary keeps
moving, and the only durable state is chat history.

The fix is not "let the agent run longer." The fix is to make every slice small
enough to inspect and every important decision recoverable from files, commands,
and artifacts.

## Core Loop

1. Write or update the repo operating contract.
2. Create a lane markdown file for the broad goal.
3. Select exactly one slice.
4. Write a slice plan with evidence, scope, no-touch boundaries, tests, and
   stop rules.
5. Implement only that slice using your normal target-repo agent workflow.
6. Run deterministic validation.
7. Run local diff review when the boundary is risky.
8. Push a PR and request Codex review for the exact head SHA.
9. Poll only that head.
10. Triage findings before fixing.
11. If findings repeat around the same invariant, stop patching and replan.
12. Merge, close, or supersede before selecting the next slice.

## Mechanisms

### Operating Contracts

`AGENTS.md` and `README.md` are active instructions for repo work, not passive
docs. They should explain decision order, scope rules, validation gates, review
policy, and stop conditions.

### Lane Markdown

A lane file tracks objective, selected slice, scope, evidence, PRs, head SHAs,
review state, churn, and stop reasons. It keeps a broad goal coherent without
turning it into one broad patch.

### Slice Invariant

Each slice names one invariant or support boundary and one canonical owner or
source of truth. If that cannot be named, the next step is planning or triage,
not implementation.

### Diff Packets

Local review receives explicit changed files, patch text, context, severity
floor, schema, and output artifact path. The review model does not get an open
tool session over the repository.

### Saved Findings

Review output is written to Markdown and optionally JSON, so findings can be
read, compared, checkpointed, or attached to later review context.

### Head-Scoped PR Polling

PR review output is consumed only when it applies to the exact current head SHA.
Older review cycles stay stale even if they appear recent in the GitHub UI.

### Churn Stop Rules

Repeated findings are process evidence. The next action may be checkpoint,
replan, split, or supersede, not another narrow patch.

## Using This Checkout

You can clone this repo and point an agent at it as a workflow reference. The
agent should still work from the target repository when running review, triage,
or PR polling commands.

For each skill, read the relevant `<skill>/SKILL.md` first and resolve
`<skills-checkout>` to this checkout path. The skill docs explain which commands
run from the target repo and which outputs are artifacts.

Copy templates into the target repo only after adapting them to that repo's real
tests, ownership boundaries, review rules, and release process.

## Quick Start

Use these templates for one bounded slice:

1. Copy `templates/AGENTS.operating-contract.md` into the target repo and adapt
   it to that repo.
2. Copy `templates/lane.md` when the goal is larger than one simple change.
3. Select one slice in the lane.
4. Copy `templates/slice-plan.md` into `plans/<slice>.md`.
5. Run the repo's deterministic validation commands.
6. Run local review when the slice touches a risky boundary:

```bash
<skills-checkout>/local-codex-review/scripts/local_review.sh \
  --uncommitted \
  --blocking-only \
  --context-text "Review this selected slice for correctness regressions."
```

7. If using GitHub Codex review, request review for the exact head SHA with
   `templates/head-scoped-codex-review-request.md`. Get the full SHA from the
   target repo:

```bash
git rev-parse HEAD
```

8. Poll the PR review after the head-scoped request exists:

```bash
python3 <skills-checkout>/pr-codex-review-poll/scripts/pr_codex_review_poll.py \
  poll --pr <number> --head-sha <full-sha>
```

9. If review findings repeat around one file, helper, invariant, or test seam,
   use `templates/churn-checkpoint.md` before another push.

## Components

| Component | Role in the workflow | Artifact |
| --- | --- | --- |
| `plan-author-review-loop` | Plan packet and plan review | plan `.md`, findings `.md` or `.json` |
| `local-codex-review` | Bounded diff review | `.codex/reports/local_review/...` |
| `pr-codex-review-poll` | Head-scoped PR review reader | JSON snapshot or poll output |
| `bug-triage-analysis` | Validate bug reports or findings before fixing | plan-ready handoff |
| `decision-gap-scout` | Surface missing decisions before implementation | decision list |
| `anti-hivemind-prompt-rewriter` | Improve broad prompts before planning | rewritten prompt |

## Current Implementation Status

- Local diff review wrapper: implemented.
- Plan review wrapper: implemented.
- PR head poller: implemented.
- Workflow templates: included in `templates/`.
- Toy lane example: included in `examples/toy-lane/`.
- Churn ledger CLI: not included.
- Major workflow gate: not included.
- Implementation runner or branch automation: not included.
- Reliability, speed, or review-quality benchmark: not included.

## Limitations

- Schemas constrain output shape, not truth.
- AI review is a signal, not the authority for correctness.
- Review quality depends on model behavior and supplied context.
- Head-scoped polling depends on GitHub and Codex review behavior.
- Diff, plan, review, and poll artifacts can contain private code or internal
  context. Use toy or redacted examples for public demos.
- This repo is a starter kit, not a complete framework.

## More Documentation

- [Workflow](docs/workflow.md)
- [Artifacts](docs/artifacts.md)
- [Claims and Limits](docs/claims-and-limits.md)
- [Toy Lane Example](examples/toy-lane/README.md)

## Tests

Run the local validation suite from this checkout:

```bash
scripts/test_all.sh
```

The suite uses fake Codex binaries for wrapper behavior and pytest for the PR
review poller unit tests. It requires `bash`, `git`, `jq`, `python3`, and
`pytest`.

## License

MIT. You can use, modify, distribute, and sell work based on these skills as
long as the license notice is preserved.
