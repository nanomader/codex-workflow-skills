---
name: plan-author-review-loop
description: Create a Markdown implementation plan, review it against the repo with an in-band fresh-eyes pass by default, and escalate to AI plan review only when risk or the user request justifies it.
metadata:
  short-description: Fast plan draft and review
---

# Plan Author + Review

## When to Use

Use this skill when the user asks to:

- create a plan for proposed changes
- review or revise an implementation plan
- choose an appropriate plan-review depth before implementation
- repeat review/update only when explicitly requested or when the change is
  risky enough to justify independent plan review

## Inputs

Required:

- proposed change request from the user

Optional:

- target plan file name/path
- constraints such as no code changes, branch rules, or manual smoke tests
- bug triage output, review findings, or a plan-ready handoff block

## Constraints

- Planning mode only: do not implement product code while running this skill.
- Keep plan files in the current working directory by default unless the user
  gives another path.
- Treat the active `cwd` as the plan workspace. It may be a linked worktree.
- Verify plan claims against current repo state using deterministic commands.
- Findings must be sorted by severity: `BLOCKER`, `P1`, `P2`, `LOW`.
- Only keep findings that require changing the plan text.
- If critical context is missing, ask concise clarification questions.
- If blocked by unknowns, stop with exact blockers and required inputs.
- Pick the cheapest review intensity that preserves quality and state the
  selected tier in the final summary.

## Review Intensity

Default to in-band fresh-eyes review. Escalate only when the change needs it:

1. `docs/support-only`: deterministic plan sanity check only.
2. `simple bounded code`: deterministic commands plus an in-band fresh-eyes
   checklist.
3. `contract/runtime`: in-band fresh-eyes review plus deterministic evidence.
   Use one AI plan review only when the change alters an artifact, validator,
   schema, prompt contract, state transition, public API, or similar runtime
   boundary.
4. `high-risk hard break`: use AI plan review when the user asks for it or when
   the plan changes product contracts enough that independent review is cheaper
   than a bad implementation round trip.

## Fast Plan Review Wrapper

When AI plan review is justified, use the bundled wrapper:

```bash
plan-author-review-loop/scripts/plan_review.sh \
  --plan-file <PLAN.md> \
  --blocking-only \
  --context-text "Short change context and review focus."
```

Wrapper defaults:

- model: Codex CLI default unless `CODEX_PLAN_REVIEW_MODEL` is set
- reasoning: `medium`
- Codex profile: unset unless `CODEX_PLAN_REVIEW_PROFILE` is set
- read-only sandbox
- shell tools disabled unless `--allow-readonly-tools` is passed
- `apply_patch` disabled
- findings saved under `${CODEX_HOME:-$HOME/.codex}/reports/plan_review/`
- unrelated dirty worktree paths rejected unless `--allow-dirty` is passed
- payload-size guard enabled
- heartbeat and timeout while the child review runs

Use the wrapper selectively:

- Skip it for normal docs, support, and simple bounded code work.
- For contract/runtime work, use one `--blocking-only` pass only when the
  boundary is dangerous enough to justify the latency.
- For high-risk hard breaks, prefer one `--blocking-only` pass unless the user
  explicitly asks to loop to LOW.

Use `--allow-readonly-tools` only when the plan needs independent repo
inspection that cannot be verified from the supplied plan, evidence pack, and
deterministic commands already run by the parent agent.

Use `--allow-dirty` only when unrelated local edits are intentional review
context. A newly written or edited plan file is allowed by default.

## Downstream Review Budget

When this plan will feed implementation plus PR review, keep this skill focused
on plan correctness:

- Do not run a local code review of the implementation target while authoring
  the plan unless the user explicitly asks.
- Do not make normal work pay for both AI plan review and local implementation
  review when PR review will also run.
- Use in-band plan review as the default.
- If high-risk work gets AI plan review, the implementation step should avoid
  restarting an open-ended local review cycle unless new evidence appears.

Environment overrides:

- `CODEX_PLAN_REVIEW_PROFILE` sets a Codex profile.
- `CODEX_PLAN_REVIEW_MODEL` sets the model.
- `CODEX_PLAN_REVIEW_REASONING` overrides reasoning effort.
- `CODEX_PLAN_REVIEW_TIMEOUT_SECONDS` overrides subprocess timeout.
- `CODEX_PLAN_REVIEW_MAX_PAYLOAD_BYTES` overrides the payload-size guard.

## Required Plan Structure

The plan must include these sections:

1. objective
2. evidence pack
3. current gap/problem statement
4. locked decisions
5. scope in/out
6. no-touch boundaries
7. implementation steps with concrete files
8. tests
9. review-churn escape hatch
10. risks and mitigations
11. done definition

The evidence pack must list repo docs, code paths, symbols, tests, command
outputs, and unknowns used to draft the plan. If the plan was created from bug
triage, preserve the triage status, confidence, root-cause hypothesis, and
plan-ready handoff.

No-touch boundaries must name files, surfaces, support claims, fallback paths,
and abstractions that are intentionally out of scope.

The review-churn escape hatch must define when implementation should stop
patching and return to analysis or planning.

For contract, schema, parser, validator, state-machine, orchestration, or
workflow changes, the plan should also name:

- invariant or support boundary being preserved
- canonical source of truth
- dependent consumers or surfaces that must share that truth
- direct tests for canonical logic
- caller-level smoke tests
- contracts, artifacts, docs, or generated files that must move with the change
- first failing test shape and why existing tests missed it
- smallest aligned fix and why broader options are not needed now, unless the
  plan intentionally chooses the broader seam repair

## Review Checklist

Check each review pass for:

1. correctness vs current code paths/files
2. test realism and determinism
3. missing acceptance criteria
4. hidden ambiguity in steps
5. unsafe assumptions about environment/tooling
6. contradictions with locked decisions/user constraints
7. missing rollback/safety constraints when relevant
8. one canonical source of truth for changed policy or runtime behavior
9. duplicate truth across callers, adapters, validators, reporting, or docs
10. direct tests plus caller-level smoke tests for shared behavior
11. negative tests for validators, parsers, schemas, and failure classifiers
12. deterministic regeneration/check commands for generated files or fixtures

## Workflow

1. Build context from repo and user request.
2. Select and record the review-intensity tier.
3. Create or update the plan markdown file.
4. Do deterministic review manually as a fresh-eyes pass.
5. If the selected tier justifies AI plan review, run the wrapper.
6. For each finding above LOW, apply or explicitly reject the recommended
   option with a reason.
7. Re-run AI review only when explicitly requested or when the escalation
   decision said this plan must loop to clean.
8. Provide the final summary.

## Loop Termination Rules

- Primary default: stop after the in-band fresh-eyes pass when findings above
  LOW have been applied or explicitly rejected with a reason.
- AI review: stop after one blocking-only pass unless the user explicitly asked
  to loop.
- Loop-to-clean: stop only when max finding severity is LOW.
- Safety: if the same unresolved finding repeats after 3 consecutive loops,
  report the blocker and ask for a user decision.
- Practical ceiling: if 8 loops are reached, report remaining findings and
  required user input.
- Review churn: if review repeatedly flags the same invariant, file, helper,
  contract boundary, or test seam, revise the design checkpoint before another
  plan patch.

## Output Format

1. `Plan file`: `<path>`
2. `Review result`: `No findings above LOW` or remaining blockers
3. `Applied recommended options`: short before/after bullets
4. `High-level plan overview`: objective, execution flow, and tests
5. `Review intensity`: selected tier and why it is sufficient
6. `Review-churn guard`: when implementation must return to analysis/planning
