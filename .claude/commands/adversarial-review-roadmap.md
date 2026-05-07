Adversarial review of an existing roadmap. A human (or `/adversarial-review-plan`) authored a roadmap — an index of multiple child plans for a larger initiative; this skill subjects it to cross-model adversarial review rounds with surgical edits between, until approved or the human takes over.

This workflow defines **how to review a roadmap**, not how to author one. Its INPUT is an existing roadmap doc and its OUTPUT is the same doc, surgically edited across review rounds, ready for `/roadmap-runner` to dispatch its child plans. It writes no code and does not author new roadmaps; for first-time authoring, use `/adversarial-review-plan` with `roadmap_path=...`.

---

## Skill asset lookup (global installation)

This skill ships in two locations:
- Project-local: `<repo-root>/.claude/commands/adversarial-review-roadmap.md` + `<repo-root>/.agentic/`
- User-global: `~/.claude/commands/adversarial-review-roadmap.md` + `~/.agentic/`

When this file references `.agentic/templates/<X>` or `.agentic/skills/<X>`, resolve in this order:
1. `<cwd>/.agentic/<X>` — project-local override (preferred when present).
2. `~/.agentic/<X>` — user-global fallback.

Output paths (`docs/roadmaps/`, `dev/<feature_name>/`) are ALWAYS resolved relative to `<cwd>` — never `~/`. Only `.agentic/` skill assets fall back to the user home.

First-time use in a fresh project: if `<cwd>` lacks `docs/roadmaps/` or `dev/`, create them as needed and proceed.

---

## Nomenclature

- **Roadmap** — index of multiple child plans, lives at `docs/roadmaps/<slug>.md`. Input AND output of this skill (the same file is surgically edited across rounds; the skill never produces a different file as the canonical artefact).
- **Spec** — optional upstream document the roadmap was distilled from. Could be at `docs/proposals/<slug>.md`, an external path like `mvp-spec.md`, or absent. When present, the reviewer audits the roadmap against it for coverage drift.
- **Child plan** — the per-plan deliverable each roadmap entry points at, conventionally at `docs/plans/plan-<child-slug>.md`. May or may not exist yet during roadmap review; existing ones are added to the file allowlist so the reviewer can verify the roadmap's claims about them.

---

## Arguments

`$ARGUMENTS` must contain named parameters:

- `feature_name=<slug>` (required): short kebab-case identifier for the review session. Used for state paths (`dev/<feature_name>/`).
- `roadmap_path=<path>` (optional, default: `docs/roadmaps/<feature_name>.md`): path to the roadmap to review. The file MUST exist — this skill does not author roadmaps.
- `spec_path=<path>` (optional): path to the upstream spec the roadmap was distilled from. If set, the reviewer audits §5 Coverage map against it; if absent, `spec_coverage_audit` is null in every verdict.
- `writer_model=<model>` (optional, default: `opus`): model the orchestrator uses for surgical edits between rounds.
- `reviewer_model=<model>` (optional, default: `codex`): model for adversarial review. Must differ from `writer_model` by provider, not just temperature — same-provider review gives up most of this skill's value.
- `max_rounds=<int>` (optional, default: `5`, hard cap: `8`): maximum review rounds before handing back to the human. Self-bias literature shows more rounds beyond ~5 can amplify drift.

Example: `/adversarial-review-roadmap feature_name=forgekeeper-mvp spec_path=mvp-spec.md`

If `reviewer_model == writer_model` or both share a provider, the skill aborts with an error.

---

## Role

You are the **roadmap-review orchestrator**. You do NOT write implementation code, do not touch `src/` or `tests/`, and do not modify child plan files. You:

1. Read the roadmap and confirm scope with the human in a short conversation.
2. Build the file allowlist (roadmap, optional spec, every existing child plan file the roadmap cites).
3. Loop: dispatch the reviewer, apply surgical edits to the roadmap (and only the roadmap), bump version, repeat until approved or round cap.
4. Hand the final roadmap to the human for approval.

You do not self-approve. Reviewer verdicts terminate the loop, but human approval is required before the roadmap becomes input to `/roadmap-runner`.

---

## Design Principles

1. `dev/<feature_name>/roadmap-review-state.json` is the canonical source of truth for the review session.
2. The roadmap `.md` at `docs/roadmaps/<slug>.md` is the human-readable canonical artefact; review verdicts are its siblings (`*.review-r<N>.md`).
3. The skill reviews an **existing** roadmap; it does not author. If the roadmap doesn't exist, fail fast with a pointer to `/adversarial-review-plan`.
4. Reviewer prompts are never hand-written per round. Assembly is delegated to `.agentic/skills/run-roadmap-review.md` using `.agentic/templates/roadmap-review-prompt.template.md`.
5. Stable-header / dynamic-suffix split and byte-identical codex flags are how codex's prefix cache warms across rounds. Flag drift or header edits during a session kill the cache.
6. Surgical edits between rounds, not full rewrites. Routed by the verdict's `dimension` field to the correct roadmap section.
7. Human-in-the-loop for slicing and priority judgments. The skill automates mechanics (prompt assembly, model invocation, state tracking), not thinking.
8. Bounded round cap. Self-bias amplifies past ~5 rounds; hard-stop at 8.

---

## Outputs

Per review session:

```
docs/roadmaps/<feature-name>.md                                # canonical roadmap output (versioned internally via changelog)
docs/roadmaps/<feature-name>.review-r1-prompt.md               # per-round assembled prompt
docs/roadmaps/<feature-name>.review-r1.md                      # per-round structured verdict (JSON matching schema)
docs/roadmaps/<feature-name>.review-r1.progress.ndjson         # transient codex JSONL stream (gitignored)
docs/roadmaps/<feature-name>.review-r2-prompt.md               # ... repeats per round
docs/roadmaps/<feature-name>.review-r2.md
...
dev/<feature_name>/roadmap-review-state.json                   # session state
```

`.progress.ndjson` files are gitignored under `docs/roadmaps/*.progress.ndjson`. The canonical audit trail is the `review-r<N>.md` JSON files.

---

## Workflow

### 1. Initial conversation with the human

Read the roadmap at `roadmap_path`. Confirm with the human:
- Is the upstream spec (if `spec_path` is set) still the right reference, or has it changed since the roadmap was authored?
- Are any child plan files at `docs/plans/plan-<child-slug>.md` already in flight or in `dev/<child-slug>/`? (Existing plan files go on the allowlist; in-flight implementations may need to be paused before the roadmap is restructured.)
- Any non-negotiable constraints the reviewer should be told about beyond what the roadmap states?

If the roadmap doesn't exist at `roadmap_path`, fail with a message pointing the human at `/adversarial-review-plan` with `roadmap_path=...` to author one.

If the roadmap has no §"Changelog v1 → v2" section yet (i.e. it's still v1 — the pre-review draft), the orchestrator adds an empty changelog skeleton and bumps the file to v2 before round 1 starts. v1 is the pre-review draft no-one ever runs review against.

### 2. Build the file allowlist

The reviewer's `Read`/`Grep` access is bounded by the allowlist. The allowlist always contains:
- The roadmap itself.
- The upstream spec at `spec_path`, if set.
- Every existing child plan file referenced from the roadmap's §4 Plans subsections (only files that exist on disk; `not_started` plans don't have files yet and are not added).
- Any other repo file the roadmap explicitly cites in motivation, coverage map, or coupling sections.

Files cited only in glossary/appendix do NOT go on the list. The reviewer's job is to verify load-bearing claims, not to wander the repo.

Persist the allowlist into the review-session state.

### 3. Review loop

For each round `r` from 1 to `max_rounds`:

a. Invoke `.agentic/skills/run-roadmap-review.md` with:
   - `feature_name`, `roadmap_path`, `spec_path`, `round = r`, `prior_verdict`, `prior_review_path`, `prior_version`, `current_version`, `file_allowlist[]`, `writer_model`.

b. The sub-workflow assembles the prompt, runs codex in background, parses the structured verdict, updates the review-session state, and returns the verdict to this orchestrator.

c. Inspect the verdict:
   - `APPROVE_AS_IS` → break loop, go to step 4.
   - `APPROVE_WITH_CHANGES` → apply surgical edits for each `important` finding; if all remaining findings are `optional`, offer to break loop and hand to human; else continue.
   - `REVISE_AND_RESUBMIT` → apply surgical edits for each `critical` and `important` finding; keep `optional` for a later pass if cheap.

d. Apply `factual_corrections[]` (if present) and `cross_plan_coupling_audit[]` entries with `issue` non-empty as highest priority — they indicate the roadmap is internally inconsistent or out of sync with the spec.

e. Apply `spec_coverage_audit[]` entries:
   - `MISSING` → add a §5 Coverage map row mapping the spec item to the right plan, OR add an explicit "out of scope" row if the team confirms it's deferred.
   - `WRONG_PLAN` → re-attribute or split the affected plan.
   - `AMBIGUOUS` → tighten the §5 row's "Notes" column with the explicit ownership.
   - `SILENTLY_DROPPED` → either add a plan to cover it, or add an explicit "out of scope" row with rationale. Do NOT silently leave it dropped.

f. Route remaining findings by `dimension` to the appropriate roadmap section (see `.agentic/skills/run-roadmap-review.md` §"Apply surgical edits").

g. Bump the roadmap version (v(N) → v(N+1)). Add a changelog entry at the top of the roadmap:

```
**Changelog v<prior> → v<current>**
- Short bullet per finding addressed, in the author's voice. Not a re-quote of the reviewer.
- If a prior-round decision was retracted, say so explicitly.
```

h. Do NOT rewrite the whole roadmap. Surgical edits keep prior decisions stable and let the next round's `round_resolution_audit` audit actual deltas rather than wrestling with a moving target.

i. Loop.

### 4. Termination

Successful termination (`APPROVE_AS_IS` or all-optional `APPROVE_WITH_CHANGES`):
- Record the final verdict and round count in the review-session state.
- Print a summary to the human: convergence trajectory (finding counts per round), total token usage per round, cache hit rate if available.
- Prompt: "The reviewer has approved. Please review the final roadmap yourself. Reply 'approved' to finalise, 'another round' to dispatch round N+1, or 'hand off' to end here without dispatching."

Cap-reached termination (round `max_rounds` completes with a non-APPROVE verdict):
- Record the last verdict.
- Print the unresolved findings summary.
- Prompt: "Reached the {{max_rounds}}-round cap. The remaining findings are listed above. Reply 'extend' to add more rounds (not recommended past 8; self-bias amplification risk), 'apply-and-stop' to patch the findings manually without another review, or 'defer' to hand the current draft off as-is."

The skill does not auto-finalise. Human approval is required before the roadmap goes to `/roadmap-runner`.

---

## State File Shape

`dev/<feature_name>/roadmap-review-state.json`:

```json
{
  "feature_name": "<slug>",
  "roadmap_path": "docs/roadmaps/<slug>.md",
  "spec_path": "<path or null>",
  "writer_model": "<model>",
  "reviewer_model": "codex",
  "max_rounds": 5,
  "current_version": "v<N>",
  "status": "reviewing|approved|cap_reached|handed_off",
  "file_allowlist": ["docs/roadmaps/<slug>.md", "..."],
  "rounds": [
    {
      "round": 1,
      "prompt_path": "...",
      "review_path": "...",
      "progress_path": "...",
      "verdict": "REVISE_AND_RESUBMIT",
      "finding_counts": { "critical": N, "important": N, "optional": N },
      "completed_at": "2026-05-07T12:34:56Z",
      "token_usage": { "input": N, "cached_input": N, "output": N }
    }
  ],
  "final_verdict": "APPROVE_AS_IS|...",
  "final_round": <int>,
  "human_approved": false
}
```

Resume semantics: if the skill is re-invoked with an existing `roadmap-review-state.json`, it reads `current_version` and `rounds[]`, then continues from the next round (or from human-approval prompt if `final_verdict` is terminal).

---

## Out of Scope

Deliberately not built into this skill:

- **Authoring a new roadmap.** Use `/adversarial-review-plan roadmap_path=...` for that. This skill assumes the roadmap already exists.
- **Modifying child plan files.** The reviewer reads them (when they exist) to verify the roadmap's claims, but neither the reviewer nor the orchestrator edits them. Per-plan review is `/adversarial-review-plan`'s job, dispatched by `/roadmap-runner` lazily.
- **Verifying agentic-dev runtime artefacts.** The reviewer does not look at `dev/<child-slug>/state.json` or telemetry. The runner manages execution state; the roadmap is a static index.
- **Codebase analysis.** `/adversarial-review-plan` runs a codebase-analysis sub-agent because per-plan reviews depend on current-state audits. Roadmap reviews don't — the file allowlist already includes everything load-bearing. Skipping this step is intentional.

---

## Anti-patterns

- **Treating roadmap review as plan review.** A finding like "Phase 2 of Plan 5 should use approach X" belongs in the per-plan review, not here. The roadmap reviewer should redirect such findings ("the per-plan reviewer for Plan 5 will catch this") rather than asking the author to inline implementation detail into the roadmap.
- **Editing child plan files during roadmap review.** They are inputs to the reviewer's verification, not artefacts the orchestrator owns. If the roadmap restructures so a child plan needs to change, mark the affected plan `not_started` (forcing re-planning when the runner reaches it) rather than editing its file.
- **Same-provider reviewer.** Claude writes + Claude reviews defeats the cross-model bias correction the pattern exists for. The skill errors out if `writer_model` and `reviewer_model` share a provider.
- **Auto-applying optional findings.** Optional findings are nits; applying them mechanically bloats the roadmap. Surface them to the human and ask.
- **Unbounded loops.** Cap is 5 default, 8 hard. Going past 8 is almost always a sign the roadmap needs a human rethink, not another round.
- **Accepting reviewer findings verbatim when the reviewer is wrong.** Codex occasionally misreads slicing intent. When the orchestrator disagrees with a finding, record the disagreement in the changelog and ask the reviewer to re-verify the specific claim in the next round. Do not silently drop findings.

---

## Handing off to /roadmap-runner

Once the human approves the final roadmap:

```
/roadmap-runner roadmap_path=docs/roadmaps/<feature-name>.md spec_path=<spec-path-if-any>
```

The runner reads the §4 Plans list, the §5 Coverage map, and the §8 Status conventions, and dispatches each child plan in order via `/adversarial-review-plan` (lazy authoring) and `/agentic-dev` (implementation), bubbling up human gates as defined in `roadmap-runner.md` §"Bubble-up mechanics".
