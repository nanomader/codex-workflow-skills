# Workflow

This workflow is for repository work that is too large or risky to treat as one
open-ended chat task. It turns a broad goal into one selected slice, explicit
artifacts, and stop rules.

Use the full lane workflow when work involves multiple PRs, runtime contracts,
schemas, validators, review churn, or a persistent agent goal. For small docs
edits or simple local fixes, use the relevant focused skill and normal tests.

## Core Shape

```text
operating contract
-> lane markdown
-> selected slice
-> slice plan
-> deterministic validation
-> local diff review
-> head-scoped PR review
-> triage
-> churn checkpoint
-> merge, close, or supersede
```

## Operating Contract

Start with an `AGENTS.md` or similar repo operating contract. It should say what
the repo values, which docs are authoritative, what needs validation, and when
the agent must stop.

The operating contract should be repo-specific. Do not copy another repo's
support claims, release rules, or architecture boundaries unless they are true
for the target repo.

## Lane Markdown

Use a lane file when the goal spans multiple implementation slices. The lane
keeps track of the broad objective and the current slice. It is not a substitute
for per-slice planning.

The lane should record:

- objective and scope;
- known slices and current status;
- selected current slice;
- evidence pack;
- locked decisions;
- no-touch boundaries;
- planned validation;
- PR numbers and head SHAs when applicable;
- review state and churn notes;
- next slice or stop reason.

## Selected Slice

Only one slice should be active during implementation. The slice should have one
primary invariant or support boundary and one canonical owner or source of truth.

If the slice cannot name those things, it is not ready for implementation. The
next step is planning, decision scouting, or bug triage.

## Slice Plan

Use `templates/slice-plan.md` or `plan-author-review-loop` to create a plan with:

- evidence pack;
- current gap;
- locked decisions;
- scope in and out;
- no-touch boundaries;
- concrete files;
- tests and deterministic checks;
- review-churn escape hatch;
- done definition.

The plan should be updated before push when implementation touches unplanned
files, changes ownership boundaries, or expands the invariant.

## Implementation

This repo does not provide an implementation runner or branch manager. Implement
the selected slice in the target repo with your normal agent, editor, and git
workflow, bounded by the lane and slice plan.

## Deterministic Validation

Run the cheapest deterministic checks before expensive review. Record what was
run and why it proves the selected slice.

Examples:

- unit tests for the changed helper;
- parser or schema fixture tests;
- caller-level smoke tests for shared behavior;
- `git diff --check`;
- deterministic regeneration checks for generated files.

Broad real runs are useful as confirmation or discovery. They should not be the
first debugger when a focused fixture or smoke test can isolate the invariant.

## Local Diff Review

Use `local-codex-review` when the slice touches risky boundaries such as
contracts, schemas, validators, parser logic, state machines, runtime truth,
security-sensitive behavior, or shared policy helpers.

The local review receives a diff packet and writes findings as artifacts. It
does not get shell access or permission to patch code.

## Head-Scoped PR Review

When using GitHub Codex review, request review for the exact current head SHA.
Then use `pr-codex-review-poll` to consume only review output tied to that SHA.

Reading review output, deciding whether a finding is real, and fixing code are
separate steps.

## Review Churn

Repeated review findings are process evidence. If findings cluster around the
same file, helper, invariant, contract boundary, or test seam, stop before the
next narrow patch.

Use `templates/churn-checkpoint.md` to decide whether to patch by invariant,
split the PR, replan, supersede, or ask for human input.

## Done

A slice is done only when its validation, review state, artifacts, and lane
status all agree. Merge, close, supersede, or explicitly block the slice before
selecting the next one.
