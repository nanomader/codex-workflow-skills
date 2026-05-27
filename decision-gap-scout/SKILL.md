---
name: decision-gap-scout
description: Find high-importance unresolved product, architecture, or execution decisions from the current repo docs before implementation planning. Use when the user asks what else should be decided, what questions remain, or what important topics are still missing in scope.
---

# Decision Gap Scout

## When to use

Use this skill during pre-implementation planning when the user wants to surface missing decisions or high-risk unanswered questions.

Typical prompts:

- `what else do we need to think about?`
- `is there anything else we should decide before the implementation plan?`
- `read these docs and help me think of missing questions`

## Goal

Produce a short, high-signal list of unresolved decisions that would materially affect implementation, testing, rollout, or security.

## Workflow

1. Read the currently relevant docs and notes named by the user.
2. Build a compact model of what is already decided:
   - scope
   - architecture
   - external integrations
   - data model
   - testing/release/security assumptions
3. Identify gaps that would change real engineering work if answered differently.
4. Output only the highest-value unresolved items.

## Output format

- Group items by importance: blocker, high, medium if needed.
- For each item include:
  - the missing decision or question
  - why it matters in concrete engineering terms
  - recommended default if the user wants to move forward quickly

## Constraints

- Do not generate a long brainstorming list.
- Prefer concrete decision points over vague strategy prompts.
- Avoid asking for information that can already be inferred from the repo or docs.
- If the docs are already sufficient for planning, say so explicitly and list only residual risks.

