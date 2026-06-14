# Repository Operating Contract For Coding Agents

You are working in this repository. Treat this file and `README.md` as active
operating contracts, not passive documentation.

Your job is to make bounded, inspectable repository changes. Do not optimize for
agreement, speed, or broad autonomy. Optimize for correctness, explicit scope,
deterministic validation, saved artifacts, and clear stop conditions.

## Scope

This contract applies only to this repository. Do not treat these rules as
global policy for unrelated repos.

When a more specific contract exists under `repository_contracts/`, `docs/`, or
another named canonical location, the more specific contract wins. If a summary
conflicts with a canonical contract, update the summary in the same change.

## Decision Order

When tradeoffs are real, prefer:

1. Correctness
2. Determinism
3. Debuggability
4. Explicit contracts
5. Small scope
6. Simplicity
7. Convenience

## Repo Truths

Fill these in for this repository:

- Current project phase:
- Supported runtime or platform boundary:
- Primary source of truth for product behavior:
- Primary source of truth for developer workflow:
- Validation entrypoint:
- Release or merge gate:
- Files or surfaces that require extra care:
- Unsupported or out-of-scope areas:

## Change Discipline

Before changing files, identify:

- objective;
- current gap;
- selected slice;
- primary invariant or support boundary;
- canonical owner or source of truth;
- planned files;
- no-touch boundaries;
- tests or deterministic checks;
- review and stop rules.

Do not turn one broad goal into one broad patch. For larger work, create a lane
markdown file and select exactly one slice at a time.

## Lane Workflow For Larger Work

Use a lane file when work is larger than one bounded change.

The lane file must track:

- objective and scope;
- known slices;
- selected current slice;
- evidence pack;
- locked decisions;
- no-touch boundaries;
- risk tier;
- planned validation;
- PR numbers and head SHAs when applicable;
- review state;
- churn notes;
- merge, close, supersede, block, or resume decisions;
- next slice or stop reason.

A persistent agent goal may own the lane sequence. It must not own the lane as
one broad patch.

## Slice Ready Definition

A slice is ready for implementation only when it has:

- one primary invariant or support boundary;
- one canonical owner or source of truth;
- concrete files expected to change;
- explicit files or surfaces not to touch;
- deterministic validation commands;
- first failing test shape when fixing a bug;
- caller-level smoke test when shared behavior changes;
- artifact, schema, or docs updates when contracts move;
- stop conditions that return to planning before another patch.

If these cannot be named, the next step is planning or triage, not
implementation.

## Planning Rules

Plans must include:

1. objective
2. evidence pack
3. current gap or problem statement
4. locked decisions
5. scope in and out
6. no-touch boundaries
7. implementation steps with concrete files
8. tests and deterministic checks
9. review-churn escape hatch
10. risks and mitigations
11. done definition

Verify plan claims against the repo. Do not rely on chat memory when a file,
command, test, or artifact can answer the question.

## Implementation Rules

Implement only the selected slice.

Stop and update the plan before continuing when the diff:

- touches unplanned files;
- adds a new contract, schema, artifact, parser, validator, prompt, report, or
  public behavior not named in the plan;
- changes validation strength or release evidence outside the slice;
- moves behavior across ownership boundaries;
- makes the slice invariant too broad to review directly;
- invalidates a no-touch boundary.

Useful discovery during implementation is allowed. Hidden scope drift is not.

## Validation Rules

Run the cheapest deterministic checks first.

Record:

- command;
- result;
- relevant output;
- reason this check proves the slice invariant.

Do not use broad real runs as the first debugger when a focused unit test,
fixture, replay, parser check, or smoke test would isolate the invariant.

## Local Review Rules

Use local diff review when the slice touches risky boundaries such as:

- contracts;
- schemas;
- validators;
- parser or evidence admission;
- state machines;
- orchestration;
- security or data-loss surfaces;
- generated artifacts or readers;
- shared policy helpers.

Local review must receive an explicit diff packet and write saved findings. Do
not let the reviewer inspect unrelated files or patch code during review.

Recommended severity policy:

- `P1` and `P2`: blocking by default;
- `P3` and `LOW`: non-blocking by default, unless the repo contract says
  otherwise;
- unknown severity: blocking until triaged.

## PR Review Rules

When requesting AI PR review, scope the request to the exact current head SHA.

Use a request shape like:

```text
@codex review

Review the current PR head <full 40-character SHA> only.
```

Do not treat review output from older heads as applying to the current patch. Do
not treat a plain `@codex review` as head-scoped.

Polling and reading review output is read-only. Triage and fixes are separate
steps.

## Review-Churn Stop Rules

Repeated review findings are process evidence.

Stop patching and checkpoint when two review passes produce similar actionable
findings in the same file, function, invariant, helper, contract boundary, or
test seam.

The checkpoint must answer:

- What invariant keeps failing?
- Is the planned owner or source of truth wrong?
- Are findings being fixed by comment order instead of by invariant?
- Should the PR be smaller?
- Should the PR be superseded?
- What test or fixture would have caught the issue earlier?

Do not reset churn risk merely because a new PR number exists.

## Final Response Requirements

When completing work, report:

- selected slice;
- files changed;
- invariant preserved;
- validation run;
- review artifacts created;
- remaining risks;
- stop reason or next slice.

Do not claim reliability, speed, review quality, or broad support unless the
repo has evidence for that claim.
