---
name: bug-triage-analysis
description: Analyze a bug report against the current codebase without changing files, determine whether it is real, perform bounded recon of the affected surface, and propose fix options with tradeoffs.
---

# Bug Triage Analysis

## Overview

Validate a bug report against the current repository without modifying files.
Determine whether the bug is confirmed, contradicted, or missing required
inputs. Then inspect the smallest relevant boundary and propose concrete fix
options.

## Workflow

1. Parse the bug report.
- Extract expected behavior, observed behavior, scope, environment, and
  reproduction steps.
- If the input is a code-review finding, extract severity, file, line, claimed
  invariant, and whether earlier findings touched the same file, function,
  contract boundary, or test seam.
- If key inputs are missing, list the exact missing items.

2. Locate relevant code paths.
- Use `rg` for text search and `ast-grep` for structural matches when syntax
  awareness matters.
- Identify entrypoints, config, tests, fixtures, and docs related to the
  behavior.

3. Validate against the current implementation.
- Compare expected behavior with current code and tests.
- Reproduce locally when deterministic reproduction is practical.
- Look for falsification evidence as well as confirming evidence.
- If reproduction is impractical, state the smallest deterministic evidence that
  would confirm or reject the report.

4. Classify the bug surface.
- Use categories that fit the repository, such as shared policy, validator,
  parser, adapter, state transition, persistence, reporting, external
  integration, setup/runtime, UI workflow, documentation contract, or test
  fixture drift.
- If repeated review findings touch the same file, function, invariant, or test
  seam, classify that as possible boundary drift before recommending another
  local patch.

5. Perform bounded boundary recon.
- Keep the review local to the relevant boundary, not the whole repository.
- Identify:
  - the invariant or contract the code should preserve
  - the canonical source of truth for that rule
  - sibling callers, validators, renderers, reporters, or tests that depend on
    the same rule
  - admitted inputs, states, or consumers that must keep working
  - rejected shapes, states, or failures that must stay blocked
  - adjacent same-helper forms that share the seam
  - tests that would have caught the bug before a fix
  - why existing tests or review passes missed it
- Recommend bounded adjacent fixes or test additions unless the recon finds a
  real cross-surface architecture gap.

6. Decide bug status.
- `Confirmed`: code, tests, or reproduction prove the bug.
- `Not reproducible`: code or tests contradict the report.
- `Needs info`: required inputs are missing.

7. Propose fix options.
- Provide 2-4 options with pros, cons, risk, and effort notes.
- Include the smallest aligned fix and a bounded seam repair when they are
  genuinely different.
- Include a broader architecture option only when the evidence supports it.
- Make a clear recommendation.

8. Emit a plan-ready handoff.
- Keep it compact enough to paste into a planning request.
- Include the recommended option, invariant, source of truth, sibling
  consumers, admitted/rejected shapes, first failing test shape, direct test
  obligations, caller smoke obligations, and docs/contracts that must move.
- If review churn was detected, include the design-checkpoint conclusion before
  recommending another patch.

## Output Format

- Confidence: `0.0`-`1.0`
- Root-cause hypothesis
- Status: `Confirmed | Not reproducible | Needs info`
- Configuration status: `Configured | Not configured | Unknown`
- High-level overview
- How it could happen
- Bug surface classification
- Nearby boundary review
  - Invariant:
  - Canonical source of truth:
  - Sibling consumers:
  - Admitted shapes, states, or consumers:
  - Rejected shapes or states:
  - Adjacent same-helper forms:
  - Adjacent drift or hardening opportunities:
- First failing test shape
  - Input/state:
  - Expected failure before fix:
  - Expected pass after fix:
  - Test location:
  - False-positive/false-negative protection:
- Why tests missed this
- Evidence
  - Code references with file paths and line numbers where possible
  - Command output snippets when relevant
- Fix options
  - Option A: summary, pros, cons, risk
  - Option B: summary, pros, cons, risk
- Recommendation
- Plan-ready handoff
- Missing info, only when status is `Needs info`

## Constraints

- Do not modify files.
- Do not make commits.
- If a claim is uncertain, say so and state what evidence would resolve it.
- Do not turn nearby recon into a whole-repo audit.
- Default to bounded adjacent fixes and tests.
- Escalate to architecture only when the recon finds a real cross-surface
  contract gap.
