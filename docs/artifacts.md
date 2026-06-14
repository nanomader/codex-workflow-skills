# Artifacts

This workflow treats artifacts as the durable state of agent-assisted repo work.
Chat history may explain intent, but files, commands, findings, and review heads
are what let a future person reconstruct the decision path.

## Operating Contract

An `AGENTS.md`, `README.md`, or equivalent repo file that tells agents how to
work in the repository. It should define priorities, scope boundaries,
validation rules, review policy, and stop conditions.

## Lane File

A markdown file that tracks a broad goal across slices. It records the objective,
known slices, selected current slice, evidence, PR/head state, review state,
churn, and the next decision.

The lane file is active workflow state when a persistent agent goal depends on
it. Treat edits to active lane state with the same care as code that affects a
gate.

## Slice Plan

A per-slice plan that makes the selected implementation unit reviewable. It
names one invariant, owner or source of truth, concrete files, tests, no-touch
boundaries, and stop rules.

## Diff Packet

The bounded input sent to local review. In this repo, `local-codex-review`
builds the packet from:

- review target mode, such as uncommitted changes, tracked diff, branch diff, or
  commit;
- branch, base ref, or commit metadata;
- changed file list;
- patch body;
- caller-supplied context text;
- excluded paths;
- minimum severity;
- output schema;
- findings output path.

The point is to review the intended diff, not to give a model an open-ended repo
session.

## Saved Findings

Review output written to Markdown and optionally JSON. Saved findings can be
read later, attached to a checkpoint, compared with later review passes, or used
as bug-triage input.

Schemas only constrain shape. They do not make a finding true.

## PR Poll Snapshot

The output from a head-scoped PR review poll. It should identify the PR, current
head SHA, poll status, and findings or clean response for that exact head.

Do not treat stale review cycles from earlier heads as current evidence.

## Churn Checkpoint

A markdown note created when review findings repeat around the same file,
helper, invariant, contract boundary, or test seam. It groups findings by
invariant and records the next decision: patch, replan, split, supersede, or
stop for human input.

## Stop Reason

A durable explanation of why work stopped. Examples:

- validation failed;
- review found a blocking issue;
- churn required replanning;
- scope drift required plan update;
- the slice was merged, closed, or superseded;
- a human decision is required.

A clear stop reason is more useful than a long chat summary.
