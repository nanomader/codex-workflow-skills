# Slice Plan: <slice id>

## Objective

<What will this slice change?>

## Evidence Pack

- Files read:
- Symbols or APIs checked:
- Tests checked:
- Docs or contracts checked:
- Command output used:
- Unknowns:

## Current Gap / Problem Statement

<What is wrong, missing, ambiguous, or risky today?>

## Locked Decisions

- <decision>

## Scope In / Out

In scope:

- <specific behavior/file/test/doc>

Out of scope:

- <specific behavior/file/test/doc>

## No-Touch Boundaries

- <file, surface, support claim, fallback path, or abstraction not to change>

## Primary Invariant

<One invariant or support boundary this slice preserves or introduces.>

## Canonical Owner / Source Of Truth

<The file, helper, schema, contract, artifact, or API that owns the invariant.>

## Implementation Steps

1. <file>: <change>
2. <file>: <change>
3. <file>: <change>

## Tests And Checks

- First failing test shape:
- Focused unit or fixture tests:
- Caller-level smoke test:
- Regeneration or fixture checks:
- `git diff --check`:

## Review-Churn Escape Hatch

Stop implementation and return to planning when:

- a review finding repeats around the same file, helper, invariant, contract
  boundary, or test seam;
- implementation touches unplanned files;
- the canonical owner changes;
- the diff becomes broader than the selected slice;
- validation requires a broader real run before focused checks pass.

## Risks And Mitigations

- Risk:
  - Mitigation:

## Done Definition

- The selected invariant is implemented.
- Focused tests pass.
- Caller-level smoke passes when shared behavior changed.
- Docs/contracts/templates move with the behavior when needed.
- Review artifacts are saved when review is required.
- The lane file records merge, close, supersede, block, or next-slice state.
