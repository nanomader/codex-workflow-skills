# Lane: Toy Config Parser Hardening

## Objective

Make a toy config parser reject ambiguous duplicate keys and preserve current
valid single-key behavior.

## Scope

In scope:

- duplicate-key detection;
- focused parser fixture tests;
- saved review artifacts for the selected slice.

Out of scope:

- full config language redesign;
- nested sections;
- performance work;
- release claims.

## Known Slices

| Slice | Status | Invariant | Owner/source of truth | PR | Head SHA | Stop reason |
| --- | --- | --- | --- | --- | --- | --- |
| `slice-001` | selected | duplicate keys fail closed | `config_parser.parse_config` | `42` | `1111111111111111111111111111111111111111` | |
| `slice-002` | candidate | comments stay ignored | `config_parser.parse_config` | | | not selected |

## Selected Current Slice

- Slice id: `slice-001`
- Why this slice is selected now: duplicate keys can hide the value actually used.
- Why later slices are not included: comment handling is separate and should not
  widen this review.

## Evidence Pack

- Relevant files: `src/config_parser.py`, `tests/test_config_parser.py`
- Relevant tests: duplicate-key fixture test, valid single-key fixture test
- Relevant docs/contracts: `docs/config-format.md`
- Unknowns: none for this toy example

## Locked Decisions

- Duplicate keys are invalid, not last-write-wins.

## No-Touch Boundaries

- Do not add nested section support.
- Do not change public config file extension.
- Do not change comment parsing in this slice.

## Validation Ladder

1. `pytest tests/test_config_parser.py -q`
2. `git diff --check`
3. Local diff review when the parser diff is ready.

## Review State

- Local review required: yes, parser behavior changed.
- Local review artifact: `artifacts/local-review-findings.example.md`
- PR review requested for full head SHA: yes
- PR poll status: `findings`

## Churn Notes

- Repeated finding cluster: duplicate-key fixture only covers adjacent keys.
- Affected invariant: duplicate keys fail closed regardless of spacing.
- Required checkpoint: `churn-checkpoint.example.md`

## Next Decision

- Stop and add non-adjacent duplicate-key fixture before another push.
