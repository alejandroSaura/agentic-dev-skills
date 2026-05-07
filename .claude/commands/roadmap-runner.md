Roadmap-runner workflow. Drives a multi-plan initiative end-to-end by dispatching `/adversarial-review-plan` (lazy authoring of each child plan) and `/agentic-dev` (implementation), bubbling up the human-interaction points those skills would otherwise own to the human in scope here.

This workflow defines **how to execute a roadmap**, not what to build. It is agnostic to the specific initiative; the roadmap doc at `roadmap_path` is the source of truth for scope. The runner produces no code itself — every code change lands inside a `/agentic-dev` session it spawns.

---

## Skill asset lookup (global installation)

This skill ships in two locations:
- Project-local: `<repo-root>/.claude/commands/roadmap-runner.md` + `<repo-root>/.agentic/`
- User-global: `~/.claude/commands/roadmap-runner.md` + `~/.agentic/`

When this file references `.agentic/templates/<X>` or `.agentic/skills/<X>`, resolve in this order:
1. `<cwd>/.agentic/<X>` — project-local override (preferred when present).
2. `~/.agentic/<X>` — user-global fallback.

Output paths (`docs/roadmaps/`, `docs/plans/`, `dev/`) are ALWAYS resolved relative to `<cwd>` — never `~/`. Only `.agentic/` skill assets fall back to the user home.

---

## Nomenclature

- **Roadmap** — index of multiple child plans, lives at `docs/roadmaps/<slug>.md`. Authored by `/adversarial-review-plan` with `roadmap_path=...`, then adversarially reviewed by `/adversarial-review-roadmap`. Input to this skill.
- **Child plan** — a single-plan deliverable at `docs/plans/plan-<child-slug>.md`. Authored by `/adversarial-review-plan` lazily, **just before** the runner dispatches it to `/agentic-dev`.
- **Runner state** — canonical state of this skill, at `dev/<roadmap-slug>/runner-state.json`. Schema: `.agentic/templates/runner-state.schema.json`.
- **Bubble-up** — the runner's promotion of a child sub-skill's human-interaction point (a question, a decision, a merge approval) to the human in scope here. The runner is the only agent in the chain that has a direct line to the human; sub-agents running `/adversarial-review-plan` or `/agentic-dev` exit cleanly when they need input, and the runner picks up the blocker from their state file.

---

## Arguments

`$ARGUMENTS` must contain named parameters:

- `roadmap_path=<path>` (required): path to the roadmap doc. Must exist; if it doesn't, fail with a pointer to `/adversarial-review-plan roadmap_path=...`.
- `roadmap_slug=<slug>` (optional, default: derived from `roadmap_path` basename): kebab-case identifier used for state paths (`dev/<roadmap_slug>/`).
- `spec_path=<path>` (optional): upstream spec the roadmap was distilled from. Forwarded to `/adversarial-review-plan` for each child plan when present.
- `from_plan=<slug>` (optional): start from this child plan rather than the first un-completed one. Use to restart from a specific point.
- `to_plan=<slug>` (optional): stop after this child plan completes. Use to stage a partial roadmap run.
- `auto_advance=<bool>` (optional, default: `false`): when `true`, the runner automatically advances to the next plan after demo verification. When `false`, the runner pauses between plans for the human to confirm before continuing. **In-plan human gates (plan approval, blocker resolution, demo verification) always require human input regardless of this flag** — `auto_advance` only controls cross-plan progression.
- `eager_planning=<bool>` (optional, default: `false`): when `true`, runs `/adversarial-review-plan` for every `not_started` child plan up front before any implementation begins. Default `false` (lazy) — each child plan is authored just-in-time, against the actual post-predecessor codebase. Eager planning is rarely the right choice; see "Lazy vs. eager planning" below.
- `orchestrator_model=<model>` (optional, default: `opus`): model used for the sub-agents the runner spawns (which run `/adversarial-review-plan` and `/agentic-dev`'s orchestrators in turn). Forwarded to the `Agent` tool's `model` param at spawn time AND passed through as `orchestrator_model` to `/agentic-dev`. The `Agent` tool accepts the friendly names `opus`, `sonnet`, `haiku` only — the harness controls which specific version each name resolves to. To run cheaper, set your own session to Claude Code fast mode (Opus 4.6) via `/fast`; sub-agents inherit `opus` as the friendly name and get the harness's current Opus.
- `writer_model` (optional, default: `opus`): forwarded to `/adversarial-review-plan` for plan drafting and surgical edits.
- `reviewer_model` (optional, default: `codex`): forwarded to `/adversarial-review-plan` for adversarial plan review. Cross-model diversity vs. the writer is load-bearing here — do not set this to `opus`.
- `implementation_model` (optional, default: `codex`): forwarded to `/agentic-dev` for phase implementation and fix agents. Codex is the primary implementer; Opus 4.7 is the documented fallback when codex usage is exhausted (see "Codex usage fallback" below).
- `review_model` (optional, default: `opus`): forwarded to `/agentic-dev` for code-diff review agents. Opus reviewing codex-authored implementations preserves cross-model diversity at this layer; setting this to `codex` would be a self-review-bias trap.
- `analysis_model` (optional, default: `opus`): forwarded to `/agentic-dev` for the codebase-analysis agent. Deep reasoning over the repo benefits most from Opus 4.7 max effort.
- `final_merge_policy=<human_required|auto_if_green>` (optional, default: `human_required`): forwarded to `/agentic-dev`. The runner bubbles up the merge gate when set to `human_required`.

Example: `/roadmap-runner roadmap_path=docs/roadmaps/forgekeeper-mvp.md spec_path=mvp-spec.md`

---

## Model selection

Three layers of model choice cascade through a runner session. Defaults aim to put codex on the bulk of the implementation work (cheapest per-token at strong code-writing capability), Opus on the work that benefits from deep reasoning (review, analysis, planning), and run the orchestrator tier on Opus too — orchestration mistakes cascade, and Opus 4.6 fast-mode is fast and inexpensive enough that Sonnet's cost edge isn't worth the reliability risk.

| Layer | Controlled by | Default | Why |
|---|---|---|---|
| **Runner itself** (this skill, in your session) | Your Claude Code session model (`/model`) | Whatever you have set | Runner is tool-heavy orchestration + frequent `AskUserQuestion`. Recommended: Opus 4.6 via `/fast` for cost-conscious runs; Opus 4.7 max effort for the first run on a fresh roadmap (where you want maximum reliability of the bubble-up logic). |
| **Sub-agent orchestrators** (the agent the runner spawns to drive `/adversarial-review-plan` or `/agentic-dev`) | `orchestrator_model` (this skill's arg) | `opus` | The `Agent` tool resolves `opus` to whatever the harness considers current Opus. To bias towards Opus 4.6 instead of 4.7, set your own session's Opus version — the friendly-name resolution inherits. Orchestration mistakes (malformed `DECISIONS.md`, dropped blockers, poor `AskUserQuestion` phrasing) cascade across hours of work; do not undershoot here. |
| **Sub-skill workers** (the agents `/adversarial-review-plan` and `/agentic-dev` spawn underneath: writers, implementers, reviewers, analysis) | `writer_model`, `reviewer_model`, `implementation_model`, `review_model`, `analysis_model` | `writer_model=opus`, `reviewer_model=codex`, `implementation_model=codex`, `review_model=opus`, `analysis_model=opus` | Codex is the primary code writer (cheaper per token than Opus, strong at code). Opus reviews codex-authored code (cross-model diversity at the review layer). Opus does the deep-reasoning analysis pass. Plan drafting (`writer_model`) is Opus; plan review (`reviewer_model`) is codex (mirroring the writer/reviewer split at the planning layer). |

**Default invocation** (the values above; override only when you know why):

```
/roadmap-runner roadmap_path=... \
  orchestrator_model=opus \
  writer_model=opus \
  reviewer_model=codex \
  implementation_model=codex \
  review_model=opus \
  analysis_model=opus
```

**Override when codex usage is exhausted** (see "Codex usage fallback" below):

```
/roadmap-runner roadmap_path=... \
  implementation_model=opus \
  ... (other args unchanged)
```

**Override for first-run-on-a-fresh-roadmap robustness** (rare; trades cost for safety on the orchestrator tier — Opus 4.7 max effort for orchestration):

Set your own session model to Opus 4.7 max via `/model` BEFORE invoking the runner. Sub-agents inherit `opus` as the friendly name; the harness resolves it to your session's Opus version.

### Codex usage fallback

Codex usage limits hit on a per-organisation basis and can interrupt a run mid-plan. The runner does not currently auto-detect codex exhaustion and swap models; the manual recovery procedure is:

1. Observe `/agentic-dev` failing on its implementation or fix agent with a codex-side error (visible in the child's `dev/<slug>/runs/<run-id>/codex-output.progress.ndjson` or in the structured failure summary the sub-agent returns to the runner).
2. The runner surfaces an `agentic_dev_failed` blocker. Halt rather than retry.
3. Re-invoke the runner with `implementation_model=opus` (and optionally `review_model=codex` swapped in to preserve cross-model diversity, since now Opus is the writer and codex would be the diverse reviewer). Other args unchanged.
4. The runner reads `dev/<roadmap-slug>/runner-state.json`, sees the affected child plan in `implementing` with a recorded blocker, and resumes from `dev/<slug>/state.json` — `/agentic-dev`'s session-resume logic picks up from where codex stalled.
5. Once codex usage resets, switch back at the next plan boundary (no need to mid-plan swap; the in-flight plan will finish on Opus).

Auto-detection + auto-swap is a future enhancement; until then, the manual procedure above is the supported path.

---

## Role

You are the **roadmap orchestrator**. You do NOT plan or implement code yourself. You:

1. Read the roadmap and build the runner state from it.
2. For each child plan in order: ensure a reviewed plan file exists (dispatch `/adversarial-review-plan` if not), gate on human approval, dispatch `/agentic-dev`, monitor for blockers, bubble up to the human, resume after resolution, gate on human demo verification, mark complete, advance.
3. Surface every cross-plan and cross-skill blocker to the human via `AskUserQuestion`; never let a sub-agent stall waiting for a human it cannot reach.

You are the only agent in the chain with a direct line to the human. Treat that as load-bearing.

---

## Design Principles

1. `dev/<roadmap-slug>/runner-state.json` is the canonical source of truth for the runner. The roadmap doc's Status lines are a human-readable projection — keep them in sync, but trust the JSON.
2. Lazy planning by default. Each child plan is authored by `/adversarial-review-plan` just before its `/agentic-dev` run, against the actual codebase the predecessor produced. Authoring all plans up front (eager) authors against an imagined codebase and is almost always wrong.
3. **Promote every human-interaction point to the runner.** Sub-skills (`/adversarial-review-plan`, `/agentic-dev`) cannot reach the human directly when invoked as sub-agents; they exit cleanly with structured signals, and the runner picks up. See "Bubble-up mechanics" §.
4. Pre-resolve what can be pre-resolved. The plan file produced by `/adversarial-review-plan` already contains §8 Success Criteria, §3 Design Decisions, and a resolved §4 Decisions Needed — extract those into `dev/<child-slug>/REQUIREMENTS.md` and `DECISIONS.md` before dispatching `/agentic-dev`, so its init Step 2 is a no-op rather than a stall.
5. **Halt-by-default between plans.** `auto_advance=false` is the default because exit demos require a human-in-the-loop check. Even when each plan succeeds end-to-end, the human should eyeball the demo before the runner advances.
6. State updates are part of completion. A transition is not done until `runner-state.json` is updated AND the roadmap doc's Status line is updated.
7. A fresh runner can resume using only `runner-state.json`, the roadmap doc, and the child sub-skills' own state files. The runner is itself resumable; `dev/<roadmap-slug>/runner-state.json` is sufficient context.
8. Verification before advance. A child plan is **not complete** because `/agentic-dev` returned success. It is complete only after a human confirms the exit demo passed.

---

## Initialization

### Step 1 — Read the roadmap

1. Read the roadmap file at `roadmap_path`. Verify it follows `.agentic/templates/roadmap.template.md` shape (§4 Plans subsections with Slug + Status lines; §8 Status conventions).
2. Extract the ordered list of child plans: slug, title, plan_path, depends_on, exit_demo, current Status.
3. If the roadmap is at `Status: Draft` and has not been adversarially reviewed yet, prompt the human: "This roadmap has not been reviewed by `/adversarial-review-roadmap`. Reply 'continue' to proceed anyway, 'review first' to halt and run `/adversarial-review-roadmap` before dispatching." — review-first is recommended; humans can override.

### Step 2 — Build / load runner state

If `dev/<roadmap-slug>/runner-state.json` already exists, this is a resume — read it, validate against the roadmap doc (slug list matches; child statuses are consistent with what the runner last recorded), reconcile drift, and continue from the recorded state. Do NOT restart from the first plan if later plans are already `complete`.

If not, create it: one entry per child plan, populated from the roadmap §4. `status: "initializing"` while the runner is building the state, then transitions to `"running"` before dispatching the first plan.

### Step 3 — Identify the first plan to dispatch

- If `from_plan` is set, start from that slug (assert it exists in the roadmap and is not in a forbidden state — `complete` already means nothing to do).
- Otherwise, pick the first child plan in roadmap order whose `status != "complete"` AND whose `depends_on` are all `complete`.
- If no such plan exists (all complete OR a non-complete plan's dependencies aren't met), surface to the human: either the roadmap is finished, or there's a dependency cycle / ordering bug.

Update runner state: `status = "running"`, `current_plan_slug = <chosen slug>`.

---

## Per-plan execution cycle

For each child plan from the chosen starting point (in roadmap order, respecting `depends_on`):

### A. Planning gate (`status: not_started → planning → plan_ready`)

1. If `docs/plans/plan-<slug>.md` exists already (e.g. authored manually or in a prior run): set child status to `plan_ready`, skip to A.4.
2. Set child status to `planning`. Update `runner-state.json` and the roadmap doc's Status line.
3. Spawn a sub-agent (via `Agent` tool, `subagent_type: general-purpose`, `model: <orchestrator_model>`) with a prompt that:
   - Tells it to invoke `/adversarial-review-plan` via the `Skill` tool with arguments: `feature_name=<slug>`, `roadmap_path=<roadmap_path>`, `spec_path=<spec_path>` (if set), `writer_model`, `reviewer_model`.
   - Instructs it to run the planning loop to convergence (`/adversarial-review-plan` handles its own review rounds).
   - Tells it to NEVER prompt the human for input directly. If `/adversarial-review-plan` blocks needing human input, the sub-agent must exit immediately, leaving `dev/<slug>/plan-state.json` in a state the runner can read; the runner will surface the blocker.
   - On `/adversarial-review-plan` reaching `final_verdict: APPROVE_AS_IS` or `APPROVE_WITH_CHANGES` (all-optional), the sub-agent returns a summary including the `final_round`, `final_verdict`, and `plan_path`.
4. Read `dev/<slug>/plan-state.json` (the planning session state). If the verdict is non-terminal (cap reached, error, or `human_approved=false`), bubble up via `AskUserQuestion`: "Planning for `<slug>` did not converge cleanly: <summary>. Reply 'finalise as-is', 'extend rounds', or 'abort'." Apply per the human's choice.
5. **Plan approval gate**: present the human with the plan summary (title, phases at a glance, exit criteria) and ask: "Approve plan `<slug>` for implementation? Reply 'approve', 'request changes' (then describe), or 'skip this plan' (mark roadmap entry blocked)."
   - On `approve` → set child status to `plan_ready`, write `plan_approved_at` to runner state.
   - On `request changes` → re-dispatch step A.3 with the human's notes appended to the planning context, looping until convergence.
   - On `skip` → set child status to `blocked` with a runner-state blocker recording the reason; halt the runner.

### B. Pre-resolve agentic-dev inputs

Before dispatching `/agentic-dev`, the runner extracts the plan file's relevant sections to pre-fill `dev/<slug>/`:

- **`REQUIREMENTS.md`**: from the plan's §8 Success Criteria + §9 Verification Commands. This pre-empts agentic-dev's init Step 2 ("clarifying questions about when the plan should be considered done"). If the plan's §8 + §9 don't cover everything agentic-dev's Step 2 would ask, the runner surfaces a blocker rather than letting agentic-dev stall.
- **`DECISIONS.md`**: from the plan's §3 Design Decisions (D-1, D-2, ...) + §4 Decisions Needed (which `/adversarial-review-plan` resolved during the planning loop). agentic-dev's "Decisions gate" then finds every `D-needed-N` matched by a dated `D-N` block.
- **`budgets.json`** (optional): if the plan declares phase scope hints, the runner can seed budgets accordingly. Otherwise default budgets stand.

The plan template's section numbers are stable (`.agentic/templates/plan.template.md`) — extraction is mechanical, not interpretive.

### C. Implementation dispatch (`status: plan_ready → implementing`)

1. Set child status to `implementing`.
2. Spawn a sub-agent (`Agent` tool, `subagent_type: general-purpose`, `model: <orchestrator_model>`, `run_in_background: true` if the runner has parallel work to do; otherwise foreground) with a prompt that:
   - Invokes `/agentic-dev` via the `Skill` tool with `plan=docs/plans/plan-<slug>.md`, `orchestrator_model=<orchestrator_model>`, `final_merge_policy=<runner's final_merge_policy>`, plus the implementation/review/analysis model overrides forwarded from this skill's args.
   - Sets `escalation_policy=block` so any blocker exits cleanly (writes to `state.json`) rather than waiting interactively.
   - Tells the sub-agent NEVER to prompt the human directly. On any condition that would normally require human input (init Step 2, decisions gate failure, budget exceeded, merge approval, review-loop failure), the sub-agent exits leaving `dev/<slug>/state.json` in `status: blocked` (or otherwise non-`complete`).
   - On `/agentic-dev` reaching `status: complete` (all phases passed review and merge gate satisfied), the sub-agent returns a structured summary.
3. After the sub-agent returns, read `dev/<slug>/state.json`:
   - `status == "complete"` → child plan finished its agentic-dev run; proceed to step D (demo gate).
   - `status == "blocked"` → bubble up the blocker (see "Bubble-up mechanics" §); resolve; re-spawn the sub-agent (it will resume `/agentic-dev` from `state.json`); loop.
   - Other (sub-agent crashed, state missing, etc.) → escalate to the human as `agentic_dev_failed`; the runner halts.

### D. Demo verification gate (`status: implementing → demo_pending → complete`)

1. Set child status to `demo_pending`. Update runner state and roadmap doc.
2. Surface the plan's §4 `Exit demo:` line to the human via `AskUserQuestion`:
   - Question: "Plan `<slug>` finished implementation. Verify the exit demo:\n\n  > <exit_demo>\n\nReply 'demo verified', 'demo failed' (then describe what went wrong), or 'inconclusive — investigate'."
   - On `demo verified` → set child status to `complete`, write `demo_verified_at`, write `completed_at`. Update runner state and roadmap doc.
   - On `demo failed` → ask whether to (a) re-spawn `/agentic-dev` with the failure details added to the plan's §10 Open Questions and a new fix-targeting phase, (b) mark the plan blocked and halt, (c) abort. Apply per choice.
   - On `inconclusive` → halt the runner with a blocker; the human investigates manually and re-invokes the runner when ready.

### E. Cross-plan advance gate

After a plan transitions to `complete`:

- If `auto_advance == true` AND `to_plan` not yet reached: advance to the next eligible plan, return to step A.
- If `auto_advance == false`: surface to human: "Plan `<slug>` complete. Next plan: `<next-slug>` — `<next-title>`. Reply 'continue' to dispatch the next plan, 'pause' to halt the runner here, or 'reorder' (then specify) to change the dispatch order."
  - On `continue` → advance.
  - On `pause` → set runner status to `paused_for_human`, halt cleanly. Re-invoking the runner resumes from the next eligible plan.
  - On `reorder` → record the human's choice in runner state (and in the roadmap doc if the change is durable), advance to the chosen plan.

When the last plan reaches `complete` (or `to_plan` is reached): set runner status to `complete`, print a summary (plans completed, total blockers raised, total agentic-dev resumes, total wall-clock), and exit.

---

## Bubble-up mechanics

The runner is the only agent in the chain that can ask the human anything. Sub-agents (running `/adversarial-review-plan` or `/agentic-dev`) exit cleanly when they hit a human-interaction point; the runner detects, asks, writes the answer to the right place, and re-spawns.

Five interaction points are bubble-up cases:

| Tag | What | When | Resolution |
|---|---|---|---|
| **A** | Plan completion criteria (agentic-dev Step 2) | Once per plan, at agentic-dev init | Pre-resolved in §B by extracting plan §8 + §9 into `REQUIREMENTS.md`. If it still blocks, treat as case **C** below. |
| **B** | Plan-level decisions (plan §4 Decisions Needed; agentic-dev decisions gate) | Once per plan, before agentic-dev | Pre-resolved by `/adversarial-review-plan` during planning. The runner extracts §3 + §4 decisions into `DECISIONS.md` in §B. |
| **C** | Mid-execution blockers (agentic-dev `state.status = blocked`) | Unpredictable, during agentic-dev | Block-and-bubble: read `state.json` blocker, ask via `AskUserQuestion`, write answer to `dev/<slug>/DECISIONS.md` (or other artifact named in the blocker), re-spawn `/agentic-dev` (resume). |
| **D** | Final merge approval (`final_merge_policy=human_required`) | Once per plan, end of agentic-dev | Block-and-bubble: agentic-dev sets a merge-gate blocker; runner asks `"Approve merge of <plan-slug> phase branches into main?"`; on approval writes a marker file the agentic-dev resume detects, re-spawns. |
| **E** | Exit demo verification | Once per plan, after agentic-dev complete | Runner-level gate (step D above). Not surfaced from agentic-dev — it's the runner's own check. |

### Block-and-bubble protocol (cases C, D)

1. Sub-agent for `/agentic-dev` exits; runner reads `dev/<slug>/state.json`.
2. If `state.status == "blocked"`, read `state.blockers[*]`. The blocker schema names a `blocker.type`, `summary`, and (where applicable) `options` and a `resolution_target_path` indicating where the answer should be written.
3. Construct an `AskUserQuestion` call:
   - `question` = the blocker's `summary`, optionally augmented with context from the plan or surrounding state.
   - `options` = the blocker's `options` if present (rendered as choices), otherwise an open-ended ask via `AskUserQuestion` (which always provides "Other").
4. Receive the human's answer.
5. Write the answer to the path the blocker named. Conventions:
   - Decisions → append a dated `D-N` block to `dev/<slug>/DECISIONS.md`.
   - Required input not in the schema → write to `dev/<slug>/RESPONSES.md` keyed by the blocker's `id`.
   - Merge approval → touch `dev/<slug>/.merge-approved` (or whatever marker `/agentic-dev` checks).
6. Update runner state: clear the blocker, increment `agentic_dev_resume_count` for this child, set `status: "running"` again.
7. Re-spawn the sub-agent. `/agentic-dev`'s session-resume logic reads its `state.json`, sees the previously-blocking decision is now resolved, and continues from the recorded `next_action`.

### Runaway-resume guard

If a single child plan exceeds `5` resume cycles for the same blocker type (e.g., agentic-dev keeps re-blocking on the same decision after the runner has written the answer), halt with `factual_drift_in_predecessor` or `other`. The likely cause is the runner's resolution write isn't being detected by agentic-dev — investigate manually rather than looping.

---

## Lazy vs. eager planning

The default is **lazy** (`eager_planning=false`): each child plan's `/adversarial-review-plan` runs immediately before that plan's `/agentic-dev`, against the actual post-predecessor codebase.

Eager planning (`eager_planning=true`) runs `/adversarial-review-plan` for every `not_started` plan up front. This is rarely the right choice because:

- Plans 5+ written today are authored against an imagined codebase. The post-Plan-4 reality will diverge enough that the adversarial review of Plan 7 done now is mostly fiction.
- Wasted work if the team reorders or splits plans mid-roadmap.
- Plan-level `/adversarial-review-plan` rounds are cheaper to repeat than agentic-dev fixes — re-planning later is OK; re-implementing later is expensive.

Eager mode exists for niche cases (e.g., a planning offsite where multiple humans review a batch of plans before any execution). It is not recommended as a default and the runner emits a warning when invoked with `eager_planning=true`.

---

## Resume semantics

If `dev/<roadmap-slug>/runner-state.json` exists when the skill is invoked:

1. Load runner state as canonical. Do NOT re-derive from the roadmap doc; the roadmap doc may have been touched since (e.g., the human re-ran `/adversarial-review-roadmap`), but mid-run reconciliation requires care — see "Drift detection" below.
2. Validate against the roadmap doc: child plan slugs match (any slug present in runner state but absent in the roadmap, or vice versa, is drift); status fields agree (a plan marked `complete` in runner state but `not_started` in the roadmap, or vice versa, is drift).
3. Validate against child sub-skill state: for each child with `status: implementing`, read `dev/<slug>/state.json` and confirm agentic-dev's recorded state agrees with the runner's understanding. Discrepancy → reconcile per "Drift detection".
4. Resume from the runner's last recorded `current_plan_slug` and `current_plan_phase` (planning / plan_ready / implementing / demo_pending), advancing to the appropriate step in the per-plan execution cycle.
5. Increment `telemetry.resume_count`.

### Drift detection

Common drift cases and resolutions:

- **Roadmap doc edited mid-run.** If the roadmap's plan list, ordering, or `depends_on` differs from runner state, surface to human: "Roadmap was edited mid-run. Reply 'reconcile from roadmap' (re-derive runner state, may invalidate completed work flags), 'reconcile from runner state' (overwrite roadmap from runner state), or 'abort'."
- **Child state.json shows `complete` but runner state shows `implementing`.** Likely the runner crashed after agentic-dev finished but before recording. Surface; on confirmation, advance to demo verification.
- **Child plan file exists but runner state says `not_started`.** Likely a manual plan authored outside the runner. Treat as `plan_ready`; ask human for approval before dispatching agentic-dev.

---

## Termination

The runner terminates in one of:

- **Complete**: every child plan reached `complete`. Print summary (plans completed, total blockers raised, total agentic-dev resumes, wall-clock). Update `runner-state.json` and the roadmap doc. The roadmap is done.
- **Paused**: `auto_advance=false` and the human chose to halt at a cross-plan gate. Runner state preserved; re-invocation resumes.
- **Blocked**: a blocker requires off-platform action (human investigation, infrastructure change, etc.). Runner state records the blocker; human resolves out-of-band and re-invokes.
- **Aborted**: the human or a fatal condition halted the run. Runner state records the abort reason.

---

## Operational rules

1. **The roadmap defines the work** — this skill defines execution sequencing, not roadmap content. To change scope, edit the roadmap (and re-review it via `/adversarial-review-roadmap`).
2. **Runner state is canonical** — `runner-state.json` drives every decision; the roadmap doc's Status lines are a projection.
3. **Sub-agents never ask the human** — every prompt to a sub-agent makes this explicit. A sub-agent that asks anyway is a protocol violation; surface it.
4. **One plan in flight at a time** — the runner does not parallelise plans. Plans are sequenced for dependency and dogfooding reasons; parallel execution belongs inside a single plan (agentic-dev's parallel phases), not across plans.
5. **State updates are atomic with transitions** — `runner-state.json` and the roadmap doc's Status line update together. If one update fails, retry both; never let them drift.
6. **No silent skips** — if a plan can't dispatch (deps unmet, plan_path malformed, sub-agent crashes), surface to human; never auto-advance past it.
7. **No edits to child plan files** — once `/adversarial-review-plan` has produced and the human has approved a plan, the runner doesn't edit it. If the human requests changes during the demo gate, re-dispatch `/adversarial-review-plan` with the change request rather than patching the plan in place.
8. **Telemetry is mandatory** — every state transition writes to `runner-state.json.telemetry`. Used to compare runs and to detect runaway loops.

---

## Out of Scope

Deliberately not built into this skill:

- **Authoring the roadmap.** Use `/adversarial-review-plan roadmap_path=...` first.
- **Reviewing the roadmap.** Use `/adversarial-review-roadmap` first.
- **Authoring child plans.** Delegated to `/adversarial-review-plan` per child, lazily.
- **Implementation.** Delegated to `/agentic-dev` per child.
- **Cross-plan parallelism.** Plans are inherently sequenced; parallelism lives inside a single agentic-dev run.
- **Roadmap evolution mid-run.** If the roadmap needs to change (a plan splits, ordering changes), the safe path is: pause the runner, edit the roadmap, run `/adversarial-review-roadmap` again, then resume.
- **Per-plan model selection.** Forwarded to `/agentic-dev` which has its own model heuristic. The runner does not second-guess.

---

## Anti-patterns

- **Letting a sub-agent ask the human.** A sub-agent prompt MUST forbid direct human interaction. If `/agentic-dev` or `/adversarial-review-plan` is observed prompting the human while running as a sub-agent, treat as a protocol violation and halt.
- **Editing the roadmap from inside the runner.** The runner updates only the §4 plan Status lines (a projection of runner state). Slicing, ordering, scope, and demo content are owned by the human and `/adversarial-review-roadmap`.
- **Skipping the plan-approval gate** (§A.5). Even when `/adversarial-review-plan` returns `APPROVE_AS_IS`, the human still approves before agentic-dev starts. Reviewer approval is not human approval.
- **Skipping the demo-verification gate** (§D). agentic-dev's review pass and verification gates can be green while the actual demo doesn't work (UI broken, integration unconfigured, etc.). The demo gate is non-negotiable.
- **Auto-applying changes the human declines.** If the human says `request changes` at the plan-approval gate, run `/adversarial-review-plan` again — don't have the runner mutate the plan file directly.
- **Reusing slugs across roadmaps.** A slug is a stable identifier for `dev/<slug>/`, `docs/plans/plan-<slug>.md`, and feature branches. Two roadmaps with overlapping slugs collide in `dev/`. Use slug prefixes (e.g., `forgekeeper-spine` rather than `spine`) when working in a multi-roadmap repo.
- **Running with `auto_advance=true` on a brand-new roadmap.** Lose the human-eyes check on the first few exit demos and you'll discover days of broken work all at once. Default to `false` until the team has a feel for how reliable the demos are.

---

## Handing off

The runner consumes a roadmap and produces a sequence of completed child plans. Once the runner reaches `status: complete`, the roadmap initiative is done; landing the work into shared branches and broadcasting completion is outside the runner's scope. Each child plan's merge into `main` happened during its own `/agentic-dev` run, gated by `final_merge_policy`.

If the team needs an end-of-roadmap action (announcement, release tag, follow-up planning), wire that as a separate step — the runner does not do it.
