# agentic-dev-skills

A bundle of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for agentic development workflows: adversarial-reviewed planning, autonomous plan-driven implementation, and orchestrated multi-plan execution.

## Skills

- **`/agentic-dev`** — Autonomous, plan-driven implementation. Consumes a plan doc and drives the full development cycle through coordinated sub-agents (analysis, implementation, verification, review, fix) with structured state, budget controls, and merge-policy gates.
- **`/adversarial-review-plan`** — Authors a plan from a rough proposal, then iterates with a cross-model adversarial reviewer (codex by default). Surgical edits between rounds; bounded round cap. Outputs `docs/plans/plan-<slug>.md`, ready for `/agentic-dev`.
- **`/adversarial-review-roadmap`** — Reviews an existing roadmap (an index of multiple child plans) for slicing, ordering, exit demos, spec coverage, and cross-plan coupling. Same iterative adversarial pattern as `/adversarial-review-plan`.
- **`/roadmap-runner`** — Orchestrates a multi-plan initiative end-to-end. Dispatches `/adversarial-review-plan` (lazy authoring per child plan) and `/agentic-dev` (implementation), bubbling up every human-interaction point those skills would otherwise own to the human in scope.
- **`/review-feature-phase`** — Phase-level adversarial code-diff review (used internally by `/agentic-dev`; can also be invoked directly).

## Install

See [INSTALL.md](INSTALL.md) for full instructions including agent-driven install. TL;DR:

```bash
# macOS / Linux
./install.sh

# Windows PowerShell
.\install.ps1
```

Both scripts copy `.claude/commands/*` into `~/.claude/commands/` and `.agentic/*` into `~/.agentic/`.

## Repo layout

```
.claude/commands/          ← top-level slash commands (the "skills")
.agentic/skills/           ← reusable sub-workflows referenced by the top-level skills
.agentic/templates/        ← prompt templates and JSON schemas
.agentic/evals/            ← evaluation protocols
.agentic/ADOPTION_GUIDE.md ← onboarding notes
.agentic/MIGRATION_MAP.md  ← version-migration notes
install.ps1 / install.sh   ← copy bundle into user-home locations
README.md / INSTALL.md     ← this file + install detail
```

After install, the layout mirrors into:

```
~/.claude/commands/
~/.agentic/
```

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and working.
- For the adversarial review skills (`/adversarial-review-plan`, `/adversarial-review-roadmap`): the [`codex` CLI](https://github.com/openai/codex) on `PATH`. The cross-model reviewer is load-bearing — without codex, the review skills will fail at round 1.
- For `/agentic-dev` with `implementation_model=codex` (the default when invoked via `/roadmap-runner`): same — codex on `PATH`. Fall back to `implementation_model=opus` when codex usage is exhausted.

## Typical workflow

1. Author a roadmap (manually, or via `/adversarial-review-plan roadmap_path=...`).
2. Adversarially review the roadmap: `/adversarial-review-roadmap feature_name=<slug> spec_path=<optional>`.
3. Run the roadmap: `/roadmap-runner roadmap_path=<path> spec_path=<optional>`. The runner dispatches `/adversarial-review-plan` for each child plan lazily, then `/agentic-dev` for implementation, gating on human approval at the bubble-up points.

For a single one-off plan (no roadmap), skip steps 1–2 and feed the plan directly to `/agentic-dev`.

## Updating

Pull the latest from the repo, then re-run the install script. The destination files are overwritten with the new versions; `~/.claude/commands/` and `~/.agentic/` reflect the new state.

## License

MIT. See [LICENSE](LICENSE).
