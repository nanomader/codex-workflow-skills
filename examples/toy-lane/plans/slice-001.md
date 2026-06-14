# Slice Plan: slice-001 duplicate keys fail closed

## Objective

Reject duplicate top-level keys in the toy config parser.

## Evidence Pack

- Files read: `src/config_parser.py`, `tests/test_config_parser.py`
- Symbols checked: `parse_config`
- Tests checked: valid key/value parsing
- Docs checked: `docs/config-format.md`
- Unknowns: none for this toy example

## Current Gap / Problem Statement

The parser currently allows a later duplicate key to overwrite an earlier value.
That makes the accepted config depend on line order and hides the ambiguity from
callers.

## Locked Decisions

- Duplicate keys should raise `ConfigError`.
- Existing valid single-key configs must keep passing.

## Scope In / Out

In scope:

- duplicate top-level key rejection;
- tests for adjacent and non-adjacent duplicates.

Out of scope:

- nested sections;
- environment-variable expansion;
- comment parsing changes.

## No-Touch Boundaries

- Do not alter config file discovery.
- Do not change public CLI flags.
- Do not add a parser dependency.

## Primary Invariant

One config key maps to one source line. Duplicate keys fail closed.

## Canonical Owner / Source Of Truth

`config_parser.parse_config` owns duplicate-key detection.

## Implementation Steps

1. `src/config_parser.py`: track seen keys and raise `ConfigError` on duplicates.
2. `tests/test_config_parser.py`: add adjacent duplicate and non-adjacent
   duplicate tests.
3. `docs/config-format.md`: state that duplicate keys are invalid.

## Tests And Checks

- First failing test shape: duplicate key fixture should raise `ConfigError`.
- Focused unit tests: `pytest tests/test_config_parser.py -q`
- Caller-level smoke test: not required for this toy parser-only slice.
- `git diff --check`: required before review.

## Review-Churn Escape Hatch

Stop implementation if review finds another accepted duplicate-key shape, such
as spacing, comments, blank lines, or escaped key text that the tests do not
cover.

## Risks And Mitigations

- Risk: only adjacent duplicates are tested.
  - Mitigation: include a non-adjacent duplicate fixture.

## Done Definition

- Duplicate-key tests fail before the fix and pass after it.
- Existing valid config tests still pass.
- Local review has no blocking duplicate-key finding.
