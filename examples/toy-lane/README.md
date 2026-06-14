# Toy Lane Example

This example shows the workflow shape without using a private or project-specific
repository.

The toy goal is to harden a small configuration parser. The lane splits the goal
into selected slices, records the plan, saves example review artifacts, and uses
a churn checkpoint when review feedback repeats around the same invariant.

Files:

- `lane.md`: broad goal, known slices, selected current slice, validation, and
  review state.
- `plans/slice-001.md`: one selected slice plan.
- `artifacts/local-review-findings.example.md`: saved local review findings.
- `artifacts/pr-poll-snapshot.example.json`: head-scoped PR poll example.
- `churn-checkpoint.example.md`: what to write when review findings repeat.

This example is intentionally small. It is not evidence that the workflow
improves speed, reliability, or review quality. It exists to make the artifacts
concrete.

## Demo Claim

The demo claim is:

> A broad goal becomes a selected slice, the slice gets a plan, review output is
> saved as an artifact, and repeated findings trigger a checkpoint instead of
> another narrow patch.
