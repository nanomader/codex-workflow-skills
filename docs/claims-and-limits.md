# Claims and Limits

This repo is a starter kit for bounded Codex-assisted repository work. It should
not be marketed as a complete framework, a benchmark, or a replacement for human
review.

## Claims That Are Defensible From This Repo

You can say:

- the repo contains reusable Codex skills for planning, local diff review, bug
  triage, decision scouting, and PR review polling;
- local review uses an explicit diff packet and schema-shaped output;
- plan review uses explicit plan structure, evidence, boundaries, and review
  termination rules;
- PR review polling is read-only and tied to the exact current PR head SHA;
- templates show how to split broad work into selected slices;
- tests cover wrapper behavior and PR poller logic.

You can also say the workflow makes work more inspectable, because plans,
diffs, findings, PR heads, and stop reasons can be saved as artifacts.

## Claims That Need More Evidence

Do not claim this workflow is more reliable, faster, or better at review quality
without evidence.

Reliability evidence would need data such as:

- number of slices run with the workflow;
- defects found before merge;
- defects that escaped after merge;
- plan-to-diff drift caught before push;
- PRs replanned, split, closed, or superseded because churn rules fired.

Speed evidence would need data such as:

- wall-clock time;
- human active time;
- model or queue wait time;
- review-loop count;
- time spent on planning and templates;
- time saved by avoiding wrong patches.

Review-quality evidence would need data such as:

- accepted findings;
- rejected findings;
- local-review findings caught before PR review;
- PR-review findings caught after local review;
- tests added because of findings;
- repeated finding clusters.

## What The Repo Does Not Do

- It does not replace human review.
- It does not prove a model finding is true.
- It does not merge or resolve PR review threads.
- It does not implement code, manage branches, or open PRs by itself.
- It does not include a complete major-lane gate.
- It does not include a public churn-ledger CLI.
- It does not guarantee Codex, GitHub, or `gh` output formats will stay stable.

## Version Drift

The wrappers depend on behavior from Codex CLI, GitHub Codex review, GitHub API
responses through `gh`, shell tools, and model output. Keep wrapper tests and
small fixtures current when those tools change.

When behavior drifts, prefer updating the wrapper, schema, parser, or docs over
adding hidden fallbacks.

## Privacy

Diff packets, plan packets, findings, and PR poll output may contain private
code, customer names, paths, issue details, or internal architecture. Public
demos should use toy repositories or redacted artifacts.

Do not paste private review artifacts into public posts.

## Review Is A Signal

AI review output is a signal. It should feed triage and validation. It should
not become the source of truth for correctness.

A clean review is not proof that the patch is correct. A repeated finding is not
proof that one root cause exists. It is evidence that the workflow should stop
and inspect the boundary.

## Night Shift Language

If you describe multi-hour or overnight agent work, make the control boundary
explicit:

> I gave Codex a lane, not a blank check.

The useful claim is bounded execution with artifacts and stop rules, not blind
unattended trust.
