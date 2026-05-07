Adversarial review of plan documents. A human describes a feature (a *proposal* — a rough idea); the orchestrator authors a *plan* and subjects it to cross-model adversarial review rounds with surgical edits between, until approved or the human takes over.

This workflow defines **how to plan**, not **how to implement**. Its INPUT is a proposal (rough idea) and its OUTPUT is a plan `.md` file ready to feed into `/agentic-dev`. For larger initiatives the output may be a *roadmap* that links to several child plans. It writes no code.

---

## Skill asset lookup (global installation)

This skill ships in two locations:
- Project-local: `<repo-root>/.claude/commands/adversarial-review-plan.md` + `<repo-root>/.agentic/`
- User-global: `~/.claude/commands/adversarial-review-plan.md` + `~/.agentic/`

When this file references `.agentic/templates/<X>` or `.agentic/skills/<X>`, resolve in this order:
1. `<cwd>/.agentic/<X>` — project-local override (preferred when present).
2. `~/.agentic/<X>` — user-global fallback.

This rule also applies inside the sub-workflows under `.agentic/skills/` (they reference each other and templates with the same project-relative shorthand).

Output paths (`dev/<feature_name>/`, `docs/proposals/`, `docs/plans/`, `docs/roadmaps/`) are ALWAYS resolved relative to `<cwd>` — never `~/`. Only `.agentic/` skill assets fall back to the user home.

First-time use in a fresh project: if `<cwd>` lacks `docs/proposals/` or `docs/plans/`, create them as needed and proceed. Do not require a `<cwd>/.agentic/` to be present — the user-global fallback covers it.

---

## Nomenclature

- **Proposal** — a rough idea. Lives at `docs/proposals/<slug>.md`. Input to this skill. Authored by a human or distilled from a conversation; not adversarially reviewed.
- **Plan** — the adversarially-reviewed output of this skill. Lives at `docs/plans/plan-<slug>.md`. Input to `/agentic-dev`. Has phases, exit criteria, decisions, risks.
- **Roadmap** — when a proposal is too large for one plan, the output is a roadmap at `docs/roadmaps/<slug>.md` that lists multiple child plans (each at `docs/plans/plan-<child-slug>.md`).

---

## Arguments

$ARGUMENTS must contain named parameters:

- `feature_name=<slug>` (required): short kebab-case identifier for the planning session. Used for state paths.
- `proposal_path=<path>` (optional): path to the input proposal. If omitted, the orchestrator looks for `docs/proposals/<feature_name>.md`; if that doesn't exist, the §1 conversation captures one.
- `plan_path=<path>` (optional, default: `docs/plans/plan-<feature_name>.md`): where to write the plan. If the path already exists, the skill resumes the session; otherwise it starts fresh.
- `roadmap_path=<path>` (optional): if set, the output is a roadmap at this path that links to multiple child plans rather than a single plan. Use for initiatives spanning >1 plan.
- `writer_model=<model>` (optional, default: `opus`): model for drafting and surgical edits.
- `reviewer_model=<model>` (optional, default: `codex`): model for adversarial review. Must differ from `writer_model` by provider, not just temperature — same-provider review gives up most of this skill's value.
- `max_rounds=<int>` (optional, default: `5`, hard cap: `8`): maximum review rounds before the skill hands back to the human. The cap exists because self-bias literature shows more rounds beyond ~5 can amplify, not reduce, drift.

Example: `/adversarial-review-plan feature_name=network-rollback-preparation`

If `reviewer_model == writer_model` or both share a provider, the skill aborts with an error. Cross-provider diversity is load-bearing.

---

## Role

You are the **planning orchestrator**. You do NOT write implementation code and do not touch `src/` or `tests/`. You:

1. Have a short conversation with the human to establish what is being planned. If a proposal `.md` already exists at `docs/proposals/<feature_name>.md`, read it and confirm the scope with the human; otherwise capture a one-paragraph proposal in the conversation and write it there.
2. Spawn a codebase-analysis sub-agent (mandatory — skipping this is the single biggest defect source).
3. Draft the initial plan (or roadmap + child plan stubs).
4. Loop: dispatch the reviewer, apply surgical edits, bump version, repeat until approved or round cap.
5. Hand the final plan to the human for approval.

You do not self-approve. Reviewer verdicts terminate the loop, but human approval is required before the plan becomes input to `/agentic-dev`.

---

## Design Principles

1. `dev/<feature_name>/plan-state.json` is the canonical source of truth for the planning session.
2. Plan `.md` files at `docs/plans/plan-<slug>.md` are the human-readable canonical artefacts; review outputs are their siblings. The originating proposal at `docs/proposals/<slug>.md` is preserved as the rough-idea record.
3. Codebase analysis before drafting is not optional. Skipping it causes factual drift that costs rounds to recover.
4. Reviewer prompts are never hand-written per round. Assembly is delegated to `.agentic/skills/run-plan-review.md` using `.agentic/templates/plan-review-prompt.template.md`.
5. The stable-header/dynamic-suffix split and byte-identical codex flags are how codex's prefix cache warms across rounds. Flag drift or header edits during a session kill the cache.
6. Surgical edits between rounds, not full rewrites. A full rewrite invalidates reviewer context about what resolved and what didn't.
7. Human-in-the-loop for scope and priority judgments. The skill automates mechanics (prompt assembly, model invocation, state tracking), not thinking.
8. Bounded round cap. Self-bias in iterative refinement amplifies past ~5 rounds; hard-stop at 8.

---

## Outputs

Per planning session:

```
docs/proposals/<feature-name>.md                            # input proposal — rough idea (preserved unchanged after planning)
docs/plans/plan-<feature-name>.md                           # canonical plan output (versioned internally via changelog)
docs/plans/plan-<feature-name>.review-r1-prompt.md          # per-round assembled prompt
docs/plans/plan-<feature-name>.review-r1.md                 # per-round structured verdict (JSON matching schema)
docs/plans/plan-<feature-name>.review-r1.progress.ndjson    # transient codex JSONL stream (gitignored)
docs/plans/plan-<feature-name>.review-r2-prompt.md          # ... repeats per round
docs/plans/plan-<feature-name>.review-r2.md
...
dev/<feature_name>/plan-state.json                          # session state
dev/<feature_name>/codebase-analysis.md                     # one-time analysis sub-agent output
```

For roadmap-shaped output (when `roadmap_path` is set), substitute `docs/roadmaps/<feature-name>.md` for the top-level deliverable and write child plans at `docs/plans/plan-<child-slug>.md`. Each child plan still gets its own review trail.

`.progress.ndjson` files are gitignored under `docs/plans/*.progress.ndjson` (and `docs/roadmaps/*.progress.ndjson` for roadmap reviews). The canonical audit trail is the `review-rN.md` JSON files.

---

## Workflow

### 1. Initial conversation with the human

If `docs/proposals/<feature_name>.md` already exists, read it first and confirm with the human that scope/constraints are still accurate. Otherwise, ask the human, in order:
- What is the feature? One paragraph.
- What is the target topology or architecture? (e.g. "non-authoritative relay-server", "single-player-only", "migration from X to Y")
- What is explicitly out of scope for *this* plan? (Phase 4, future work, etc.)
- Any existing proposals, plans, or roadmaps that partially cover this? (Reference paths.)
- Any non-negotiable constraints? (Budget, deadline, existing APIs that must not change.)

Record the human's answers into `dev/<feature_name>/context.md`. If no proposal existed at start, also write a one-paragraph rough-idea summary to `docs/proposals/<feature_name>.md` for traceability. Do not start drafting the plan until both files exist.

### 2. Mandatory codebase analysis

Spawn a subagent (use `Explore` subagent type; use `writer_model` as the inherited model unless overridden) with a prompt that:
- Names the feature and the target topology.
- Asks for a structured audit of existing code relevant to the feature.
- Demands file + line number citations for every claim.
- Asks the subagent to flag anything in the repo that contradicts the feature's premises (e.g. "if you claim the simulation is deterministic, list every place it isn't").
- Caps output at ~1500 words.

Persist the output to `dev/<feature_name>/codebase-analysis.md`. This file is input to the drafting step but is NOT embedded in review prompts (the plan's own §3 audit section is where the relevant subset is surfaced to the reviewer).

**Anti-pattern:** draft first and verify later. The biggest defect source in manual planning is stale audit data. Codex catches it in round 1 at the cost of an avoidable round.

### 3. Draft the initial plan

Produce the plan at `plan_path` (or the roadmap + child plan stubs at `roadmap_path` if a roadmap was requested). Minimum structure for each plan:

- Title + status header (`Status: Draft (v2)` — first drafts are v2 because v1 is the pre-codebase-analysis mental model the orchestrator never writes down).
- Changelog section skeleton (empty for v2 — populated from v3 onward).
- Link back to the originating proposal at `docs/proposals/<feature_name>.md`.
- Motivation / Scope (in/out/constraints).
- Current-state audit table (subset of `codebase-analysis.md`, only the parts the plan's claims depend on).
- Design decisions D-1..D-N with rationale.
- Target architecture diagram (ASCII is fine).
- Phases with deliverables, tests, exit criteria, dependencies, reversibility.
- Risks table with severities + mitigations.
- Open questions the author deliberately left for the reviewer to push back on.
- Exit criteria for the whole plan.
- Appendices: file inventory, glossary.

Avoid premature implementation detail. The plan describes *what* and *why*; `/agentic-dev` produces *how*.

### 4. Review loop

For each round `r` from 1 to `max_rounds`:

a. Derive the **file allowlist** for this round: every repo-root-relative path the plan's current draft explicitly cites in audit tables, decision rationales, phase deliverables, and risks. Always include the plan itself. Files cited only in appendix boilerplate or glossary do NOT go on the list.

b. Invoke `.agentic/skills/run-plan-review.md` with:
   - `feature_name`, `plan_path`, `round = r`, `prior_verdict`, `prior_review_path`, `prior_version`, `current_version`, `file_allowlist[]`, `writer_model`.

c. The sub-workflow assembles the prompt, runs codex in background, parses the structured verdict, updates `plan-state.json`, and returns the verdict to this orchestrator.

d. Inspect the verdict:
   - `APPROVE_AS_IS` → break loop, go to step 5.
   - `APPROVE_WITH_CHANGES` → apply surgical edits for each `important` finding; if all remaining findings are `optional`, offer to break loop and hand to human; else continue.
   - `REVISE_AND_RESUBMIT` → apply surgical edits for each `critical` and `important` finding; keep `optional` for a later pass if cheap.

e. Apply factual_corrections[] from the verdict as highest priority (they indicate the plan is out of sync with the code).

f. Bump the plan version (v(N) → v(N+1)). Add a changelog entry at the top of the plan:

```
**Changelog v<prior> → v<current>**
- Short bullet per finding addressed, in the author's voice. Not a re-quote of the reviewer.
- Include what was retracted if a prior-round decision turned out to be wrong (this happens; see D-7 rework in the rollback-networking example).
```

g. Do NOT rewrite the whole plan. Surgical edits keep prior decisions stable and let the next round's `round_resolution_audit` audit actual deltas rather than wrestling with a moving target.

h. Loop.

### 5. Termination

Successful termination (`APPROVE_AS_IS` or all-optional `APPROVE_WITH_CHANGES`):
- Record the final verdict and round count in `plan-state.json`.
- Print a summary to the human: convergence trajectory (finding counts per round), total token usage per round, cache hit rate if available.
- Prompt: "The reviewer has approved. Please review the final plan yourself. Reply 'approved' to finalise, 'another round' to dispatch round N+1, or 'hand off' to end here without implementation."

Cap-reached termination (round `max_rounds` completes with a non-APPROVE verdict):
- Record the last verdict.
- Print the unresolved findings summary.
- Prompt: "Reached the {{max_rounds}}-round cap. The remaining findings are listed above. Reply 'extend' to add more rounds (not recommended past 8; self-bias amplification risk), 'apply-and-stop' to patch the findings manually without another review, or 'defer' to hand the current draft off as-is."

The skill does not auto-finalise. Human approval is required before the plan goes to `/agentic-dev`.

---

## Codex Invocation

Reviewer is `codex`. Flag set is byte-identical across every round in a planning session:

```bash
codex exec --ephemeral \
  -s read-only \
  -c approval_policy="never" \
  --json \
  --output-schema .agentic/templates/plan-review-verdict.schema.json \
  --skip-git-repo-check \
  --cd <repo-root> \
  -o docs/plans/<basename>.review-r<N>.md \
  - < docs/plans/<basename>.review-r<N>-prompt.md \
  | tee docs/plans/<basename>.review-r<N>.progress.ndjson \
  > /dev/null 2>&1
```

Rationale:
- `--ephemeral` — no persisted session; each round is stateless from codex's view.
- `-s read-only` — reviewer cannot mutate anything.
- `-c approval_policy="never"` — non-interactive.
- `--json` — JSONL events to stdout; the `--output-schema` layer emits the final structured message.
- `--output-schema .agentic/templates/plan-review-verdict.schema.json` — enforces structured verdict. Pinned path, not passed as parameter, so the flag bytes are identical.
- `--cd <repo-root>` — reviewer's working directory. Must be the repo root so file-allowlist paths resolve.
- `-o <file>` — final structured message lands here.
- `| tee <progress.ndjson>` — JSONL event stream captured for telemetry and gitignored.

Drift on any of these flags between rounds invalidates codex's prefix cache and forces a full re-tokenisation on the next round.

---

## Token Optimisations Applied

The skill inherits these from `/agentic-dev` and adapts them:

1. **Stable-header / dynamic-suffix split** — Reviewer prompt has a byte-identical header across every round in a session. The plan text is embedded at the header's end; changes between rounds re-tokenise only the plan payload, not the rubric + role + allowlist + instructions.

2. **Byte-identical codex flags** — Documented above; single source of truth in this skill file. Any future flag change lands in this file and is announced as cache-invalidating.

3. **Hard file allowlist** — Every round's prompt enumerates the allowed Read targets. Reviewer is explicitly forbidden from reading outside. Cuts tool-use tokens substantially vs ad-hoc "read as needed" language.

4. **Pre-digested prior-round findings** — Round N >= 2 prompts never embed the prior round's full review. The sub-workflow digests prior `findings[]` into a compact `- [severity] <title> — <where>` list and inlines it.

5. **Structured output via `--output-schema`** — Verdict is parsed by JSON field, not by regex-matching markdown. Eliminates retry overhead when reviewers drift on verdict wording.

6. **`.progress.ndjson` gitignored** — Transient streams for live observability; canonical audit artefact is the `-o` JSON file.

7. **Author's own changelog as the "what changed" signal** — Instead of asking the reviewer to diff v(N) vs v(N-1), the skill extracts the author's v(N-1) → v(N) changelog section from the plan and inlines it into the round-N suffix. Cheap and already authoritative.

Not applied (see §"Out of scope" below for why).

---

## State File Shape

`dev/<feature_name>/plan-state.json`:

```json
{
  "feature_name": "<slug>",
  "proposal_path": "docs/proposals/<slug>.md",
  "plan_path": "docs/plans/plan-<slug>.md",
  "roadmap_path": null,
  "writer_model": "<model>",
  "reviewer_model": "codex",
  "max_rounds": 5,
  "current_version": "v<N>",
  "status": "drafting|reviewing|approved|cap_reached|handed_off",
  "codebase_analysis_path": "dev/<slug>/codebase-analysis.md",
  "rounds": [
    {
      "round": 1,
      "prompt_path": "...",
      "review_path": "...",
      "progress_path": "...",
      "verdict": "REVISE_AND_RESUBMIT",
      "finding_counts": { "critical": 5, "important": 6, "optional": 3 },
      "completed_at": "2026-04-17T12:34:56Z",
      "token_usage": { "input": 12345, "cached_input": 0, "output": 3456 }
    }
  ],
  "final_verdict": "APPROVE_AS_IS|...",
  "final_round": <int>,
  "human_approved": false
}
```

Resume semantics: if the skill is re-invoked with an existing `plan-state.json`, it reads `current_version` and `rounds[]`, then continues from the next round (or from human-approval prompt if `final_verdict` is terminal).

---

## Out of Scope

Deliberately not built into this skill, even though `/agentic-dev` has them:

- **Warmed-cache measurement protocol** — telemetry-only, not correctness-critical. Can be added if a later planning session needs to tune token cost.
- **Per-phase model selection / downshift** — all writer edits use the same `writer_model`; all reviews use `codex`. Downshifting surgical edits to a cheaper Claude is a future optimisation.
- **Diff-embedding threshold** — plans aren't diffs; the full plan is always embedded in the prompt (cached stable header absorbs it).
- **Parallel rounds** — planning is inherently sequential; each round depends on the prior round's verdict.
- **Scope-verification greps / toolchain probes** — implementation-specific; the planning skill stays above `/src` and `/tests`.
- **Branch management, PR creation, merge gates** — this skill produces a document, not commits.

If a future planning session's needs grow past these boundaries, the right move is usually to hand off to `/agentic-dev` for the implementation, not to expand this skill.

---

## Anti-patterns

- **Skipping the codebase analysis step.** The single biggest defect source in the manual version was stale audit data. Even if the orchestrator "already knows" the codebase, running the analysis subagent is cheap and catches drift.
- **Rewriting the whole plan each round.** Reviewer verdicts reference specific sections; rewrites reset those references. Surgical edits keep the `round_resolution_audit` tractable.
- **Same-provider reviewer.** Claude writes + Claude reviews defeats the cross-model bias correction the pattern exists for. The skill errors out if `writer_model` and `reviewer_model` share a provider.
- **Auto-applying optional findings.** Optional findings are nits; applying them mechanically bloats the plan. The orchestrator should surface them to the human and ask.
- **Unbounded loops.** The round cap is 5 default, 8 hard. Going past 8 is almost always a sign the plan needs a human rethink, not another round.
- **Accepting reviewer findings verbatim when the reviewer is wrong.** Codex occasionally misreads code. When the orchestrator disagrees with a finding, it records the disagreement in the changelog and asks the reviewer to re-verify the specific claim in the next round. Do not silently drop findings.

---

## Handing off to /agentic-dev

Once the human approves the final plan, implementation uses:

```
/agentic-dev plan=docs/plans/plan-<feature-name>.md mode=<auto> review_model=codex
```

For roadmap-shaped output, hand off each child plan separately:

```
/agentic-dev plan=docs/plans/plan-<child-slug>.md ...
```

The plan's Phase structure (each phase with deliverables, tests, exit criteria) maps directly onto `/agentic-dev`'s phase-driven execution. `/adversarial-review-plan`'s output is deliberately shaped to be `/agentic-dev`'s input.
