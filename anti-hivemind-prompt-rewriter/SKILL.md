---
name: anti-hivemind-prompt-rewriter
description: Rewrite user-supplied prompts to reduce generic, dominant-mode LLM output using the Artificial Hivemind guide. Use when the user wants a prompt rewritten for better diversity, clearer assumptions, stronger constraints, more distinct solution directions, improved evaluation criteria, or less cliche-heavy coding, product, strategy, writing, or personal-growth output.
---

# Anti-Hivemind Prompt Rewriter

Rewrite a user prompt so it is less likely to collapse into generic LLM output while preserving the user's actual goal, constraints, domain, and tone.

Keep the full guide in this skill in working context when rewriting. Do not reduce the method to shallow paraphrase.

## Workflow

1. Parse the original prompt.
- Extract the user's true objective, audience, constraints, deliverable shape, and any explicit non-goals.
- Classify whether the task is open-ended, mixed, or mostly deterministic.

2. Diagnose mode-collapse risk.
- Identify where the original prompt is likely to trigger default, median-model output.
- Look for weak instructions such as "be creative", "give me ideas", "best option", or vague requests with no mechanism, assumptions, tradeoffs, or evaluation criteria.

3. Rewrite by changing the distribution, not just the wording.
- Prefer changes to objective, constraints, perspectives, assumptions, output structure, and evaluation rubric.
- Add diversity requirements only when they are useful for the task. Do not force brainstorm-style output onto deterministic fact lookup or narrow procedural work.
- Preserve the user's domain language and concrete constraints.
- If the user omitted critical specifics, insert explicit placeholders like `{goal}` or `{constraints}` rather than inventing facts.

4. Ground the rewrite.
- Require specifics, failure modes, measurable signals, next steps, or concrete examples where appropriate.
- When the task is coding, product, strategy, leadership, parenting, or personal growth, use the domain-specific patterns in the guide below.
- When useful, ask for rare-but-plausible options, explicit assumption flips, or a diverge -> converge workflow.

5. Produce the output in a compact, usable form.
- Default to these sections:
  - `Diagnosis`: 2-5 bullets on what made the original prompt generic or under-specified.
  - `Rewritten prompt`: one production-ready prompt block.
  - `Missing inputs`: only when placeholders remain or key facts are absent.
- If the user explicitly asks for alternatives, provide up to 3 variants:
  - `Baseline`
  - `Diversity-first`
  - `Evaluation-first`

## Rewrite Rules

- Preserve intent. Improve the prompt without changing the user's real problem.
- Change objectives and constraints before changing wording.
- Prefer explicit clusters, assumptions, mechanisms, risks, and scoring criteria over generic "creativity" language.
- Avoid adding boilerplate intros, motivational filler, or generic persona scaffolding unless it materially improves the output.
- Avoid fake specificity. If the user did not supply facts, use placeholders or a short missing-input list.
- When the original task is already precise and deterministic, tighten clarity and success criteria instead of adding artificial divergence.
- When a prompt obviously invites dominant-mode answers, explicitly instruct the model to identify the default answer and escape it.

## Full Reference Guide

# Prompting Against the "Artificial Hivemind" (Cheat Sheet)

_Primary source_: **"Artificial Hivemind: The Open-Ended Homogeneity of Language Models (and Beyond)"** (Jiang et al., arXiv:2510.22954 / NeurIPS 2025 D&B).  
_What this file is for_: practical, copy/paste prompt patterns + workflows for a **senior SWE / founder / heavy LLM user** who uses AI for coding, product, and personal growth.

Useful references (from the paper):

```text
Paper: https://arxiv.org/abs/2510.22954
Code:  https://github.com/liweijiang/artificial-hivemind
Data:  https://huggingface.co/liweijiang/artificial-hivemind
```

---

## 0) The core idea in one minute

**LLMs often converge to the same "dominant mode"** (the most statistically typical answer), even for prompts where many very different answers could be good. The paper calls this the **Artificial Hivemind** and splits it into:

- **Intra-model repetition**: the *same model* keeps giving you "the same answer with different phrasing".
- **Inter-model homogeneity**: *different models* often give you **surprisingly similar** content (sometimes even overlapping phrases), so "try another model" is not a guaranteed escape hatch.

**Practical consequence**: If you ask LLMs for ideas, strategy, advice, or creative content, you may be sampling a narrow slice of humanity's knowledge + culture - and you'll tend to get what everyone else gets. That's fine for boilerplate, but dangerous for originality, product differentiation, and independent thinking.

---

## 1) What the paper actually found (high-signal takeaways)

### Infinity-Chat: what "open-ended prompts" look like in the wild
The authors build **Infinity-Chat** from real user queries (from WildChat) and find that "open-ended" is not just poems and jokes - it includes product decisions, how-to tasks, explanations, and worldview questions.

**Taxonomy (6 top-level / 17 subcategories)** is included at the bottom of this cheat sheet (Section 9). Use it as a mental model: it's a map of where "diversity of answers" is expected.

### Artificial Hivemind is measurable and shows up at scale
They sample many responses per prompt and compute semantic similarity via embeddings. In their setup:

- Even with aggressive sampling, **responses from the same model remain highly repetitive** (the paper reports that in **79%** of cases the average similarity is **> 0.8**).
- Different models often output **highly overlapping ideas** (inter-model homogeneity), including "extended verbatim spans" in some cases.
- And even within the "most-similar" cluster for a prompt, **many different models contribute to the same cluster** (average ~= **8 unique models** in a top-50 most-similar set; some prompts exceed 10). In other words: cross-model outputs are often *interchangeable*.

**Concrete example (why this matters)**: for a fully open-ended prompt like "Write a metaphor about time," the paper shows responses across many models collapse into just a couple of dominant clusters (e.g., variations of **"time is a river"** vs **"time is a weaver"**).

### "Just paraphrase the prompt" doesn't fix it
Across 42 models, average similarity barely drops when you paraphrase:

- within-prompt similarity ~= **0.821**
- cross-paraphrase similarity ~= **0.781**
- delta ~= **0.04**

**Interpretation**: paraphrasing is usually a *surface* move. You need *objective / constraint / perspective* changes to escape the mode.

### Humans disagree - and LLM judges aren't great at that regime
They collect dense human labels (25 per example) and show **high disagreement** is common on open-ended tasks. They then test LMs, reward models, and "LLM judges" and find **correlations with human ratings drop** on:

- subsets where responses are *similar-quality*, and/or
- subsets with *high human disagreement*

**Interpretation**: when there's no single gold answer, automated scoring often becomes brittle. You should treat "LLM-as-a-judge" as a helpful *assistant*, not an oracle.

---

## 2) What this means for you (SWE + founder + personal growth)

### If you use LLMs for coding
- The hivemind can be good: it converges on standard patterns and "known good" designs.
- It can also be bad: it can over-propose fashionable defaults (framework-of-the-month, generic architecture diagrams, CRUD-first thinking) and under-propose unconventional but better-fitting solutions.

**Move**: ask for **multiple architectures**, each with explicit constraints, risks, and "why you'd choose it".

### If you use LLMs for product strategy
If all founders ask similar prompts, the AI will tend to produce:

- the same market maps
- the same positioning language
- the same onboarding checklists
- the same "growth loops"

**Move**: force the model to generate **distinct hypotheses** tied to **your specific wedge**, data, and constraints - and to *name what would make each hypothesis false*.

### If you use LLMs for life / meditation / leadership
The hivemind often outputs:

- generic self-help platitudes
- culturally dominant metaphors
- one-size-fits-all "productivity" answers

**Move**: ask for **pluralistic advice** (multiple value systems), **concrete practices**, and **questions** that help you think - not just advice that tells you what to do.

---

## 3) "Anti-Hivemind" prompting principles (the ones that actually change the distribution)

### Principle 1: Ask for **modes**, not "more"
Instead of "give me 10 ideas", ask for **3-5 distinct *clusters*** and label what makes each cluster different.

**Prompt add-on**:
- "Generate **4 mutually exclusive directions**, each with a different underlying assumption and risk profile. Then provide 2 variations inside each direction."

### Principle 2: Put *diversity constraints* in the output spec
LLMs optimize for "helpful + typical". You must **specify diversity** as a requirement.

Good constraints:
- different mechanisms (e.g., "pricing lever" vs "distribution lever" vs "retention lever")
- different audiences (enterprise vs prosumer vs hobbyist)
- different tradeoffs (speed vs safety vs cost vs simplicity)
- different worldviews (utilitarian vs virtue ethics vs deontological; or "Western productivity" vs "contemplative")

Bad constraints:
- "be creative"
- "be original"
- "think outside the box"

### Principle 3: Change *the objective*, not the wording
Paraphrase barely moves the needle. Instead:
- change the **evaluation rubric**
- change the **format** (memo vs debate vs design doc vs checklist)
- change the **perspective** (supporter, critic, operator, adversary, end-user)
- change the **constraints** (time, money, legal, cultural, technical)

### Principle 4: Force the model to reveal (and vary) assumptions
Most homogenization is "shared assumptions".

**Prompt add-on**:
- "List the **assumptions** you're making. Now produce 3 alternatives that each flips one key assumption."

### Principle 5: Use a **Diverge -> Converge** workflow
Do not ask for "the best answer" in one shot. Use a 2-pass loop:
1) Diverge: generate diverse options with strong constraints.
2) Converge: select based on *your* values + context.

### Principle 6: Treat LLM evaluation as multi-objective (not "pick winner")
When options are close, LLM judges can be unstable.

**Prompt add-on**:
- "Create a **tradeoff table** with 6 criteria. Then tell me which option wins under **three different value weightings**."

### Principle 7: "Ground novelty" with specifics
To avoid fluffy originality:
- require concrete examples, pseudo-metrics, failure modes, next steps
- require "what would I do in the next 48 hours?"

### Principle 8: If you can, add **your data**
The best way to escape a global mode is to inject *local information*:
- your users' quotes
- your codebase constraints
- your preferences and history
- your child's temperament and routines (parenting prompts)

### Principle 9: Use multiple models, but don't trust it blindly
Inter-model homogeneity means you still need diversity constraints. Use multi-model as an *ensemble of editors* - not a "diversity guarantee".

### Principle 10: Ask for "what's missing" and "what's rare"
**Prompt add-on**:
- "What are **3 high-quality but rarely mentioned approaches** here? Why are they rare?"

---

## 4) Copy/paste prompt patterns

### 4.1 The "Diversity-First Brainstorm" (works for product, writing, strategy)
```text
You are helping me brainstorm, but I want to avoid generic LLM answers.

Context:
- Goal: {goal}
- Audience: {audience}
- Constraints: {constraints}
- What I already tried / believe: {attempts}

Task:
1) Generate 4 DISTINCT directions (clusters). Each direction must:
- be based on a different underlying assumption
- use a different mechanism
- have a different primary risk
2) For each direction, give:
- A one-sentence "thesis"
- 2 concrete examples
- 1 metric I'd track
- 1 failure mode + how to detect it early
3) After all directions:
- Identify what's "most hivemind/generic" among them and why
- Propose 2 twists that would make the top 2 directions more unique to my context
Output as a structured list.
```

### 4.2 "Architectures as alternatives" (system design / backend work)
```text
I'm designing {system}. I want 3 viable architectures that are meaningfully different.

Constraints:
- Scale: {scale}
- Latency: {latency}
- Team size: {team}
- Existing stack: {stack}
- Non-goals: {non_goals}

Generate 3 architectures:
A) "Simple + boring" (fastest to ship)
B) "Scalable + robust" (handles growth & failures)
C) "Unusual but plausible" (a different paradigm)

For each:
- diagram in words (components + responsibilities)
- data model + consistency strategy
- failure modes & mitigations
- operational burden (on-call, tooling)
- why this might be the wrong choice

Then recommend *two* based on different value weightings:
- weighting 1: speed
- weighting 2: correctness + operability
```

### 4.3 "Code review that doesn't collapse into generic"
```text
Review the following code for correctness, readability, and maintainability.
But don't give generic style advice.

Rules:
- Give exactly 10 findings.
- At least 4 findings must be NON-obvious (not naming, not formatting).
- Each finding must include: (a) why it matters, (b) evidence pointing to the exact line(s),
(c) a concrete fix, (d) a test I should add.

Code:
{paste}
```

### 4.4 "Debugging: hypothesis ladder"
```text
I have a bug: {symptom}

Environment:
- stack: {stack}
- recent changes: {changes}
- logs: {logs}

Task:
1) Create a ranked hypothesis list (top 7), each with:
- why it fits the symptom
- what observation would falsify it quickly
- the fastest experiment to run
2) For the top 3 hypotheses, give the exact commands / code changes I should try.
3) If none reproduce, propose a minimal repro strategy and what to instrument.
```

### 4.5 "Founder decision support (pluralistic)"
Use this when the right answer depends on values, not facts.

```text
Help me decide: {decision}

My context:
- Goals (ranked): {goals}
- Constraints: {constraints}
- Risk tolerance: {risk}
- Values I care about: {values}

Task:
1) Summarize the decision in 2 sentences.
2) Generate 3 decision frames, each with a different value system:
- "maximize optionality"
- "maximize stability for family"
- "maximize long-term upside"
3) Under each frame:
- recommend an action
- name the tradeoff I'm accepting
- give 3 questions I should ask myself
4) Close with a 7-day experiment plan that reduces uncertainty.
```

### 4.6 "Parenting prompt: practical scripts, not platitudes"
```text
I'm a parent. Situation: {situation}
Child age: {age}
Temperament: {temperament}
My constraints: {constraints}

I do NOT want generic advice. I want scripts and options.

Give me:
1) The likely underlying needs driving the behavior (3 hypotheses).
2) 3 scripts I can say verbatim (calm, firm, playful variants).
3) 2 boundary-setting approaches with pros/cons.
4) A "repair" script if I lose my cool.
5) A 1-week plan to reduce this situation recurring.
```

### 4.7 "Meditation / inner work: practices + checkpoints"
(Secular, no drugs, grounded.)

```text
I practice meditation and want to grow. Topic: {topic}

Context:
- experience level: {level}
- current practice: {practice}
- constraints (time, family, work): {constraints}

Task:
1) Give 3 practices, each from a different lens:
- attention training
- somatic regulation
- ethical / values practice
2) For each practice:
- steps (5-10 minutes)
- what to notice
- common failure mode
- how to measure progress without ego traps
3) Give 5 journaling questions that will surface my blind spots.
```

### 4.8 "Community leadership (ethical)"
If you're leading a community (meditation group, startup team, etc.), keep it consensual and non-coercive.

```text
I'm leading a community around {theme}. I want ethical leadership, not manipulation.

Context: {context}

Task:
1) Draft a "community covenant" (consent, autonomy, boundaries, conflict handling).
2) Design 3 rituals/practices that build belonging WITHOUT coercion.
3) List red flags that signal unhealthy dynamics (including mine).
4) Give a transparency checklist for decisions and money/time asks.
```

---

## 5) Practical "anti-mode-collapse" tactics you can add to almost any prompt

### A) "Show me the default answer - then escape it"
```text
First, briefly state what the typical/generic LLM answer would be.
Then generate 5 alternatives that intentionally avoid those tropes and take different assumptions.
```

### B) "Ban-list" (works for writing + product copy)
```text
Avoid these cliches/phrases: {list}
Avoid these frameworks: {list}
Now produce the answer without them.
```

### C) "Counterfactual lens"
```text
Assume the opposite of the default assumption: {assumption}
Now answer again.
```

### D) "Two-level output"
```text
Level 1: simple, conventional answer (for baseline)
Level 2: contrarian / rare / expert answer (still realistic)
Explain what extra assumptions Level 2 uses.
```

---

## 6) How to know you're getting a "hivemind answer" (fast detection)

If the output:
- looks like a blog post template (intro -> 5 bullet tips -> conclusion)
- uses the same metaphors you've seen everywhere
- avoids specifics, metrics, or failure modes
- says "it depends" without narrowing the space
- recommends the same 3 tools/frameworks everybody recommends
- gives advice that would be true for almost anyone

...then you probably sampled the dominant mode.

**Fix**: add constraints, demand clusters, demand assumptions, demand "rare but plausible".

---

## 7) A lightweight rubric for evaluating *diversity* (not just quality)

Score each candidate (0-2 each):

1) **Distinct mechanism**: is it a different causal story, or just a rephrase?
2) **Distinct assumptions**: does it assume different constraints or values?
3) **Actionability**: clear next steps, measurable outcomes.
4) **Specificity**: concrete examples, names, numbers, edge cases.
5) **Risk clarity**: named failure modes, early warning signals.
6) **Non-obviousness**: would a smart generalist think of this quickly?

Total /12. Keep the top 2-3 and iterate.

---

## 8) A recommended workflow for heavy AI users (so you don't outsource thinking)

### The 3-pass loop
1) **Pass 1: Diverge**
- 4 clusters, different assumptions/mechanisms
2) **Pass 2: Stress-test**
- failure modes, adversarial critique, "what would make this wrong?"
3) **Pass 3: Commit**
- pick based on your values, write a 7-day experiment plan

### The "human in the loop" move
Before you ask the model, write 5 bullet points yourself (even rough).
Then ask the model to:
- compare its output to yours
- find what you missed
- produce "rare" alternatives

This keeps your agency and reduces passive homogenization.

---

## 9) Infinity-Chat taxonomy (quick reference)

These are real-world open-ended query types where output diversity matters:

### Creative Content Generation (58.0%)
- Poems, essays, jokes, stories, etc.

### Brainstorming & Ideation (15.2%)
- Generating new ideas, features, characters, thesis topics, etc.

### Open-Endedness (conceptual / interpretive)
- Philosophical Questions (3.5%)
- Abstract Conceptual Questions (10.0%)
- Ambiguous Everyday Questions (2.6%)
- Analytical & Interpretive Questions (22.6%)
- Speculative & Hypothetical Scenarios (22.2%)

### Alternative Perspectives
- Value-Laden Questions (2.3%)
- Controversial Questions (2.5%)

### Alternative Styles
- Communication Styles (3.2%)
- Writing Genres (38.5%)

### Information-Seeking (still open-ended in practice)
- Problem Solving (19.3%)
- Decision Support (2.2%)
- Skill Development (23.5%)
- Recommendations (11.0%)
- Concept Explanations (23.6%)
- Personal Advice (4.1%)

---

## 10) Quick "meta-prompt" to generate better prompts (prompt architect)

```text
Act as my prompt architect.

1) Ask me up to 7 questions to clarify my goal, constraints, and what "good" looks like.
2) Then propose 3 prompt variants:
- Variant A: fastest/most direct (baseline)
- Variant B: diversity-first (forces multiple clusters/assumptions)
- Variant C: evaluation-first (includes a scoring rubric + failure modes)
3) For each variant, explain what kind of output distribution it will tend to produce and why.
```

---

## 11) Final note: how to use AI without becoming an echo

The point isn't "LLMs are bad at creativity". The point is:

- **LLMs are great at the median.**
- If you want **outlier value** (original product wedge, uncommon insight, meaningful growth), you must **engineer the prompt + process** to escape the median.

Treat AI like:
- a generator of *candidates*,
- a simulator of *perspectives*,
- a helper for *execution*,

...but keep **judgment** and **values** with you.
