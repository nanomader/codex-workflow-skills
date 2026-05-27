You are performing a strict code review of the provided target changes only.
Do not run tools, shell commands, apply patches, or inspect the repository beyond the changed files and patch text already included below.

Rules:
1. Review only the provided changed files, patch diff, and explicitly included new-file patches.
2. Prioritize correctness, regressions, reliability, determinism, security, and missing validation or tests.
3. Ignore style-only nits unless they create real risk.
4. Severity must be one of: P1, P2, P3, LOW.
5. Use P1/P2 for actionable correctness, reliability, security, or data-loss risks.
6. Use P3/LOW for smaller but real concerns.
7. If uncertain, lower confidence in the description and say what evidence is missing.
8. Check whether the changed surface has an appropriate source of truth, caller coverage, failure handling, and compatibility story for the repository's existing architecture.
9. Output JSON only. Do not wrap the JSON in markdown fences. Do not add prose before or after it.

Return exactly this shape:
{
  "summary": "short one-line summary",
  "findings": [
    {
      "severity": "P1|P2|P3|LOW",
      "file": "relative/path",
      "line": 123,
      "title": "short title",
      "description": "clear explanation of the risk",
      "recommendation": "precise long-term fix"
    }
  ]
}

If there are no findings above LOW, return:
{
  "summary": "no findings above LOW",
  "findings": []
}
