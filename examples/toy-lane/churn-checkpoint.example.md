# Review Churn Checkpoint

## Trigger

- PR: `42`
- Head SHA: `1111111111111111111111111111111111111111`
- Finding count or repeated pattern: duplicate-key tests missed another accepted
  shape.
- Threshold crossed: repeated same-invariant finding.

## Repeated Finding Cluster

| Pass/head | Severity | File/line | Title | URL |
| --- | --- | --- | --- | --- |
| local review | P2 | `tests/test_config_parser.py:42` | Duplicate detection misses non-adjacent keys | `https://example.invalid/review/comment/1` |

## Affected Invariant

Duplicate keys fail closed regardless of spacing or intervening keys.

## Owner / Source Of Truth

`config_parser.parse_config`

## Why Narrow Patching May Be Wrong

- The first test only covered the trigger shape, not the invariant.
- A second patch that adds only one more fixture could miss comments or blank
  lines unless the test table names the accepted and rejected forms.

## Options

### Patch By Invariant

- Add adjacent, non-adjacent, blank-line-separated, and comment-separated
  duplicate fixtures.
- Keep the implementation in `parse_config`.

### Replan

- Not required for this toy example unless key parsing itself is ambiguous.

### Supersede PR

- Not required for this toy example.

## Decision

Chosen option: patch by invariant.

Reason: the owner is still clear and the missing test set is small.

## Required Validation Before Next Push

- `pytest tests/test_config_parser.py -q`
- local review with duplicate-key context
