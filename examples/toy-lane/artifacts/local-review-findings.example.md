# Local Codex Review Findings

Target: toy config parser `slice-001`
Minimum severity: P2

## Findings

### [P2] Duplicate detection misses non-adjacent keys

File: `tests/test_config_parser.py`

Line: 42

The new duplicate-key test only covers adjacent duplicate keys. If a duplicate
appears after another valid key, the parser can still accept the file unless the
implementation tracks all seen keys across the whole document.

Recommendation: add a non-adjacent duplicate-key fixture and assert it raises
`ConfigError`.
