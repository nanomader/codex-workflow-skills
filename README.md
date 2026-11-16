# Plan a change with Codex. Review exactly what changed.

![A red panda compares a plan with a code change through a magnifying glass.](assets/banner.jpg)

Codex Workflow Skills gives you six reusable skills for working on a Git repository. Use one on its own, or follow a change from its first plan to its pull request. Plans and review findings are saved in files you can inspect later.

## Try a local code review

With Bash, Git, Python 3, jq and a signed in Codex CLI, clone the skills once:

```sh
git clone https://github.com/nanomader/codex-workflow-skills.git
skills="$(cd codex-workflow-skills && pwd)"
```

From the repository where you have uncommitted changes, run:

```sh
"$skills/local-codex-review/scripts/local_review.sh" --uncommitted --blocking-only
```

The reviewer gets the diff and saves its findings under `.codex/reports/local_review/`. Review that file before deciding what to fix. It can contain private code.

## Pick a skill

| When you want to… | Use |
| --- | --- |
| Give a broad request a clearer scope | [Prompt rewriter](anti-hivemind-prompt-rewriter/SKILL.md) |
| Find decisions that could block implementation | [Decision gap scout](decision-gap-scout/SKILL.md) |
| Write and review a plan for one change | [Plan review](plan-author-review-loop/SKILL.md) |
| Check a local diff for regressions | [Local code review](local-codex-review/SKILL.md) |
| Read GitHub review feedback for the current commit | [Pull request review poller](pr-codex-review-poll/SKILL.md) |
| Verify a reported bug before fixing it | [Bug triage](bug-triage-analysis/SKILL.md) |

For a larger goal, adapt the templates to your repository and choose one change at a time. Run your project’s tests before asking for a review. If the same finding keeps returning, revisit the plan. [Worked example](examples/toy-lane/README.md) · [Templates](templates/) · [Workflow guide](docs/workflow.md)

[Saved files](docs/artifacts.md) · [Limitations](docs/claims-and-limits.md) · [Test suite](scripts/test_all.sh) · [MIT license](LICENSE)
