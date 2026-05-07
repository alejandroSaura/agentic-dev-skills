Agentic development workflow. Autonomous, plan-driven development through coordinated agents with structured state, verification gates, execution modes, and budget controls.

This workflow defines **how to execute**, not **what to build**. It is agnostic to the specific feature, migration, or subsystem being worked on.

---

## Skill asset lookup (global installation)

This skill ships in two locations:
- Project-local: `<repo-root>/.claude/commands/agentic-dev.md` + `<repo-root>/.agentic/`
- User-global: `~/.claude/commands/agentic-dev.md` + `~/.agentic/`

When this file references `.agentic/templates/<X>` or `.agentic/skills/<X>`, resolve in this order:
1. `<cwd>/.agentic/<X>` — project-local override (preferred when present).
2. `~/.agentic/<X>` — user-global fallback.

This rule also applies inside the sub-workflows under `.agentic/skills/` (they reference each other and templates with the same project-relative shorthand).

Output paths (`dev/<feature-name>/`, `docs/proposals/`, `docs/plans/`, `docs/roadmaps/`, `docs/workstreams/archive/`) are ALWAYS resolved relative to `<cwd>` — never `~/`. Only `.agentic/` skill assets fall back to the user home.

First-time use in a fresh project: if `<cwd>` lacks the conventional folders (`dev/`, `docs/proposals/`, `docs/plans/`, `docs/workstreams/archive/`), create them as needed and proceed. Do not require a `<cwd>/.agentic/` to be present — the user-global fallback covers it.

---

## Nomenclature

- **Proposal** — rough idea at `docs/proposals/<slug>.md`. Not consumed by this skill directly.
- **Plan** — adversarially-reviewed output of `/adversarial-review-plan` at `docs/plans/plan-<slug>.md`. **This skill consumes plans.**
- **Roadmap** — at `docs/roadmaps/<slug>.md`. Lists multiple child plans. To execute a roadmap, run this skill once per child plan.

Working state during execution lives in `dev/<feature-name>/`. On feature completion (after main merge), the entire `dev/<feature-name>/` folder is moved to `docs/workstreams/archive/<feature-name>/` as a permanent audit trail. See §"Completion" → "Archive on completion".

---

## Arguments

$ARGUMENTS must contain named parameters:

- `plan=<path>` (required): path to the plan `.md` file (typically `docs/plans/plan-<slug>.md`)
- `mode=<lightweight|standard|full>` (optional): execution mode — auto-selected if omitted
- `orchestrator_model=<model>` (optional, default: opus): model for this orchestrator
- `implementation_model=<model|codex>` (optional, default: opus): model for implementation/fix agents
- `review_model=<model|codex>` (optional, default: opus): model for review agents
- `analysis_model=<model|codex>` (optional, default: opus): model for codebase analysis agent
- `final_merge_policy=<human_required|auto_if_green>` (optional, default: human_required): merge policy for main

Each model parameter accepts a Claude model name (opus, sonnet, haiku) or `codex` to use the Codex CLI.

Example: `/agentic-dev plan=docs/plans/plan-12-store-owned-data.md mode=standard review_model=codex`

---

## Role

You are the **orchestrator agent**. You do NOT implement code yourself. You coordinate the full development cycle by spawning sub-agents and managing structured state.

---

## Design Principles

1. `state.json` is the canonical source of truth for orchestration
2. Markdown memory files are human-readable projections, not the canonical source
3. Context is loaded just-in-time, not dumped broadly
4. Every autonomous action is auditable via telemetry
5. Verification gates must pass before review
6. Budget limits prevent unbounded loops
7. A fresh orchestrator can resume using only repo files and git state

---

## Execution Modes

### Mode Selection

If `mode` is not provided, auto-select based on the plan:

**Lightweight** — use when:
- Single bugfix or contained change
- One file or one issue
- No multi-phase structure in the plan

**Standard** — use when:
- Medium-sized feature or multi-file work
- Bounded refactor
- 2-4 phases in the plan

**Full** — use when:
- Migration or subsystem rewrite
- 5+ phases in the plan
- Parallel phases are beneficial
- Recovery requirements are high

### Mode Escalation

Promote from lightweight to standard if:
- More than one significant subsystem is touched
- A second fix cycle is needed
- Task requires multi-step verification
- Agent cannot bound the change confidently

Promote from standard to full if:
- Explicit multi-phase plan exists with 5+ phases
- Parallel phases are beneficial
- Recovery requirements are high
- Task spans architecture boundaries

When escalating, create any additional artifacts required by the new mode.

---

## Agent Backends

- **Claude models** (opus, sonnet, haiku): use the `Agent` tool with the `model` parameter
- **`codex`**: invoke via Codex CLI in non-interactive mode (see Codex CLI section)

---

## Agent Roles

### Analysis Agent

Spawned at initialization, then re-run only on demand (see refresh-analysis policy).

- Analyze the codebase (or relevant subsystem based on plan scope)
- Produce `dev/<feature-name>/CODEBASE_ANALYSIS.md`
- See `.agentic/skills/refresh-analysis.md` for when and how to refresh

### Implementation Agent

- Implement only the assigned phase scope
- Read phase context (not full codebase analysis) before touching code
- Produce code, tests, and a handoff summary
- Do not re-investigate the project if context is already provided

### Review Agent

- Review implementation against the plan's phase definition and acceptance criteria
- Verify correctness, quality, compilation, and tests as applicable
- Inspect verification gate outputs, not only diff content
- Return structured result: **PASS** or **FAIL**
- If failing, provide findings grouped by severity (critical / important / optional)

### Fix Agent

- Address the specific review findings
- Scope work to the review feedback, not the whole project
- Produce updated code/tests and a handoff summary

A failed review always triggers a **new** fix agent, not an informal continuation.

---

## Structured State

### Canonical state: `dev/<feature-name>/state.json`

This file is the source of truth for all orchestration decisions. Schema: `.agentic/templates/state.schema.json`.

### Update rules

The orchestrator MUST update `state.json`:
- After initialization
- After each phase transition (start, review, fix, merge, advance)
- After any status change
- After any blocker is added or resolved
- After any verification gate runs
- After budget consumption changes
- On resume

### Auto-generation of SHARED_MEMORY.md

After every `state.json` update, auto-generate `SHARED_MEMORY.md` from `state.json`. SHARED_MEMORY.md is a read-only projection — never edit it manually.

**Field mapping (state.json → SHARED_MEMORY.md):**

| state.json field | SHARED_MEMORY.md section |
|---|---|
| `plan_path`, `mode`, `status`, `current_phase`, `next_action`, `last_updated` | Active State |
| `completed_phases[]` | Completed Phases table |
| `current_phase.attempt`, `.review_round`, `.fix_round`, `verification.last_results` | Current Phase Progress |
| `budgets` vs `current_phase.review_round`/`.fix_round` | Budget Status |
| `project_knowledge[]` | Project Knowledge |
| `last_handoff` | Last Agent Handoff |

---

## Initialization

### Step 1 — Load and parse plan

1. Read the plan file specified in the `plan` parameter
2. Extract the feature name from the plan title (short, kebab-case)
3. Identify all phases, their dependencies, and acceptance criteria
4. Auto-select execution mode if not provided

### Step 2 — Gather completion requirements

Ask the user clarifying questions about when the plan should be considered **done**:
- What are the high-level success criteria beyond the plan's phases?
- Are there integration or testing requirements?
- Any constraints (e.g., must compile, must pass existing tests)?

### Step 2.5 — Decisions gate (pre-dispatch)

Before transitioning `state.json.status` from `initializing` to `implementing`, the orchestrator reads §4 "Decisions needed before execution" from the plan doc and, for each `D-needed-N` entry, verifies a matching dated D-N block exists in `dev/<feature>/DECISIONS.md`. Dispatch is blocked (`decisions_resolved: false` in state.json) until every listed item is resolved; once all are recorded, the orchestrator sets `decisions_resolved: true` and proceeds to phase-1 dispatch. Plan template: `.agentic/templates/plan.template.md`.

### Step 3 — Initialize workspace

Follow `.agentic/skills/initialize-feature.md`:
- Create feature branch, dev folder, state.json, templates
- Artifacts created depend on the selected mode

### Step 4 — Codebase analysis

Spawn an analysis agent (using `analysis_model`) following `.agentic/skills/refresh-analysis.md` with `trigger_reason=initialization`.

### Step 5 — Identify first phase

Read the plan, identify the first phase (or set of independent phases if parallelizable in full mode), and begin the execution cycle.

Update `state.json`:
- Set `status` to `implementing`
- Set `current_phase` with phase details
- Set `next_action` to `spawn_implementation`

---

## Git Strategy

### Branch hierarchy

```
main
 └── feature/<feature-name>
      ├── feature/<feature-name>-phase-1
      ├── feature/<feature-name>-phase-2
      └── ...

(Flat naming per D-9 — see §"Parallelism Policy" §"Flat branch naming". Hierarchical `feature/<name>/phase-<N>` is forbidden because git refs cannot coexist with sub-path-prefix branches.)
```

### Phase branches

Before starting work on a phase:
```
git checkout feature/<feature-name>
git checkout -b feature/<feature-name>-phase-<N>
```

All implementation, fix, and review commits for that phase happen on this branch.

### Merge on review pass

```
git checkout feature/<feature-name>
git merge feature/<feature-name>-phase-<N>
git branch -d feature/<feature-name>-phase-<N>
```

Phase branches are deleted after merge. Git history preserves the commits.

### Parallel execution (full mode only)

Parallel execution is **orchestrator judgment per-situation** per D-8. See §"Parallelism Policy" for the authoritative 6-item C-1..C-6 safety checklist and per-pair `parallel-safety-check-<pair>.json` artifact contract (schema at `.agentic/templates/parallel-safety-check.schema.json`).

Quick summary (full policy in §"Parallelism Policy"):

1. Build the phase DAG at initialization time per `.agentic/skills/initialize-feature.md §"DAG construction"`.
2. For each candidate pair, evaluate C-1..C-6 and write `dev/<feature-name>/parallelism/parallel-safety-check-<pair>.json`:
   ```json
   {
     "candidate_pair": ["phase-3", "phase-4"],
     "checklist_results": [
       {"id": "C-1", "result": "pass", "rationale": "..."},
       {"id": "C-2", "result": "pass", "rationale": "..."},
       {"id": "C-3", "result": "pass", "rationale": "..."},
       {"id": "C-4", "result": "pass", "rationale": "..."},
       {"id": "C-5", "result": "pass", "rationale": "..."},
       {"id": "C-6", "result": "pass", "rationale": "..."}
     ],
     "decision": "allow_parallel",
     "rationale": "No shared files, independent modules, decisions frozen"
   }
   ```
3. If `decision` is `allow_parallel`:
   - Use the `Agent` tool with `isolation: "worktree"` for each parallel phase
   - Each agent works on its own phase branch in its own worktree
   - Merge each into the feature branch sequentially after both pass review
4. If overlap risk is not low, serialize the phases

### Commit policy

- After implementation agent: `feat(<phase>): <short description>`
- After fix agent: `fix(<phase>): <finding addressed>`
- After review pass + merge: `merge: phase-<N> complete`

---

## Run Identifiers

Each agent run gets a deterministic `run_id` for artifact paths and telemetry:

**Format:** `<phase_id>-<agent_type>-<sequence>`

Examples: `phase-1-impl-1`, `phase-1-review-1`, `phase-1-fix-1`, `phase-1-review-2`

The sequence number increments per agent type within a phase (first implementation = 1, second = 2, etc.). The orchestrator tracks this via `current_phase.attempt`, `.review_round`, and `.fix_round` in state.json.

---

## Execution Cycle

For each phase in the plan:

### 1. Create phase branch
```
git checkout feature/<feature-name>
git checkout -b feature/<feature-name>-phase-<N>
```

### 2. Build phase context

Follow `.agentic/skills/build-phase-context.md` to generate `dev/<feature-name>/context/phase-<N>-context.md`.

Context depth depends on mode:
- **Lightweight:** phase scope + shared memory + relevant files
- **Standard:** above + decisions + interfaces + test locations
- **Full:** above + codebase analysis + dependency summaries

### 3. Spawn implementation agent

Using configured `implementation_model`. Prompt must include:
- The phase context document (NOT the full codebase analysis unless full mode)
- The current shared memory content
- Instruction to produce a handoff summary
- Instruction to NOT re-investigate the project — use the provided context

### 4. After implementation returns

1. Commit on phase branch: `feat(<phase>): <short description>`
2. Record touched files in `dev/<feature-name>/runs/<run-id>/touched-files.json`
3. Update `SHARED_MEMORY.md` with handoff notes
4. If the agent made design decisions, record them in `DECISIONS.md`
5. Update `state.json`: increment `telemetry.agent_runs`, update `next_action` to `run_verification`
6. Write telemetry event to `runs.ndjson`

### 5. Run verification gates

Follow `.agentic/skills/run-verification.md`:
- Execute all required automated gates (build, tests, etc.)
- If any gate fails, proceed to fix cycle (step 7)
- If all gates pass, proceed to review (step 6)

### 6. Spawn review agent

Follow `.agentic/skills/run-review.md`:
- Review agent receives the diff AND verification gate results
- Review PASS is impossible when required automated gates have failed

### 7. Process review result

Append result to `dev/<feature-name>/reviews/review-phase-<N>.md`.

**If PASS:**
1. Commit review log update
2. Merge and delete phase branch
3. Update state.json: move phase to `completed_phases`, clear `current_phase`
4. Update shared memory: mark phase complete, advance to next
5. Check if analysis refresh is needed (see refresh-analysis policy)
6. If more phases remain: advance to next phase
7. If all phases complete: proceed to finalization

**If FAIL:**
Follow `.agentic/skills/process-review-failure.md`:
1. Check budgets before spawning fix agent
2. Detect unproductive retries
3. Spawn fix agent scoped to review findings
4. After fix: go back to step 5 (run verification, then re-review)

### Non-negotiable rules

- A phase is **not complete** because an implementation agent says it is. A phase is complete only when the review agent returns **PASS** AND all required verification gates pass.
- A review is **not started** until all required automated gates pass.

---

## Verification Pipeline

### Gate catalog

| Gate | Description | Default for |
|------|-------------|-------------|
| `format` | Code formatting | full |
| `lint` | Linter passes | full |
| `typecheck` | Type checking | standard, full |
| `build` | Project builds | all modes |
| `unit_tests` | Unit tests pass | full |
| `targeted_tests` | Tests for changed area | standard, full |
| `integration_tests` | Integration tests | full (if applicable) |
| `repro_script` | Repro confirms fix | bugfix tasks |
| `review` | Review agent PASS | all modes |

### Per-phase configuration

Each phase declares its required gates in `dev/<feature-name>/verification/phase-<N>-verification.json`. See `.agentic/skills/run-verification.md` for details.

### Gate resolution

The orchestrator must resolve concrete commands for each gate. Default commands are defined in `.agentic/templates/AGENTS.md` under Test Commands.

---

## Budget and Escalation Policy

### Budget configuration

Budgets live in `state.json.budgets` at runtime. In standard/full modes, an optional `dev/<feature-name>/budgets.json` can provide overrides at initialization time — its values are merged into `state.json.budgets` during workspace setup, then `budgets.json` is not read again. Schema: `.agentic/templates/budgets.schema.json`.

Default budgets:
- Max review rounds per phase: **4**
- Max fix rounds per phase: **4**
- Max total agent runs per feature: **50**
- Max parallel agents: **2**
- Max unproductive retries: **2**
- Max consecutive gate failures: **3**

### Budget enforcement

Before every agent spawn, check relevant budgets. If exceeded:

1. Set `state.json` status to `blocked`
2. Add a blocker with the appropriate type:
   - `blocked_needs_human_decision` — budget exceeded, user must decide
   - `blocked_needs_design_resolution` — technical approach is wrong
   - `blocked_needs_env_fix` — environment issue prevents progress
   - `blocked_unproductive_loop` — retries produce no meaningful change
3. Write an explicit summary of why the agent is blocked
4. Apply the escalation action from `state.json.budgets.escalation_policy` (`ask_user` or `block`)

### Unproductive retry detection

After each fix cycle, compare the current diff with the previous attempt:
- If the same files are changed with similar patterns and the same gates fail, this is an unproductive retry
- After `max_unproductive_retries`, escalate

---

## Telemetry

### Per-run events

After every agent run, append an event to `dev/<feature-name>/telemetry/runs.ndjson` following the schema in `.agentic/templates/telemetry-event.schema.json`.

### Feature summary

On completion, generate `dev/<feature-name>/telemetry/summary.json` with aggregated stats (see `.agentic/skills/finalize-feature.md`).

### What to capture

- Agent type, model, start/end time
- Files changed, commands run
- Verification results, review result
- Retry count, outcome

### Streaming progress (`.progress.ndjson`)

- `.progress.ndjson` files are transient — streamed by codex during review/impl runs to provide incremental progress visibility.
- The canonical audit artifact for each review round is the final verdict `.md` under `dev/<feature-name>/reviews/`; the `.progress.ndjson` sibling is a disposable stream.
- Phase 6 `.gitignore` pattern `dev/*/reviews/*.progress.ndjson` keeps them out of commits; see that phase for rationale.

---

## Context Strategy

Every sub-agent prompt is structured as `<stable prefix> + <dynamic suffix>` per `.agentic/templates/impl-prompt.template.md`. The stable prefix is byte-identical across sub-agent invocations in a session so Claude's automatic prompt cache (see §"Prompt Cache Economics") has a consistent entry to hit. Layers 1–2 below land in the stable prefix; Layers 3–4 in the dynamic suffix.

### Layer 1 — Stable repo guidance *(stable prefix)*

`.agentic/templates/AGENTS.md` contains stable instructions all agents need. Inlined verbatim at the top of the stable prefix.

### Layer 2 — Feature-local stable artifacts *(stable prefix)*

Stable for the lifetime of the feature (orchestrator-only writes per D-10):
- `dev/<feature-name>/REQUIREMENTS.md` — feature requirements, inlined
- Plan excerpt — the "Design Decisions" section of the plan file, inlined (stable per-feature)

Excluded from the stable prefix: `DECISIONS.md` (grows per-phase, would invalidate the cache), `state.json` (mutates each cycle), `SHARED_MEMORY.md` (projection of state.json). These move to the dynamic suffix below.

### Layer 3 — Just-in-time code context *(dynamic suffix)*

Phase-specific material assembled per dispatch:
- `dev/<feature-name>/DECISIONS.md` snapshot (snapshot-by-hash in a `runs/<run-id>/decisions-snapshot.md` file; referenced from the suffix by path + SHA-256)
- `dev/<feature-name>/context/<phase-id>-context.md` — phase context doc
- `dev/<feature-name>/SHARED_MEMORY.md` — current orchestration projection
- Touched files and relevant interfaces
- Dependency summaries for the current phase
- Relevant test locations
- Handoff format

### Layer 4 — Optional deep analysis *(dynamic suffix)*

`CODEBASE_ANALYSIS.md` is loaded only when:
- Initializing a new feature
- A completed phase changed architecture-significant files
- A reviewer flags stale context
- The orchestrator cannot map work to existing knowledge

---

## Runtime Isolation

### Environment contract (standard + full modes)

For every phase run, record in `dev/<feature-name>/runtime/environment.json`:
- OS, shell, runtime versions
- Worktree path and branch
- Commit SHA at start
- Build/test command set

### Worktree isolation (full mode parallel)

- Each parallel phase gets its own worktree via `Agent` tool with `isolation: "worktree"`
- Worktrees are cleaned up after merge

### Cleanup policy

- Abandoned worktrees: remove after phase completion or failure resolution
- Temp files: delete agent prompt/output files after processing
- Per-feature telemetry and run artifacts: **archive after merge.** Once the feature lands on `main`, move `dev/<feature-name>/` to `docs/workstreams/archive/<feature-name>/` (see §Completion step 7). The DECISIONS log, review history, telemetry, and context docs are part of the project's long-term record of how the work happened. Do not delete them; they remain readable in the archive.

---

## Common Memory

### File: `dev/<feature-name>/SHARED_MEMORY.md`

Human-readable operational projection of `state.json`. Every agent reads it before starting work. The orchestrator updates it after every cycle.

Template: `.agentic/templates/SHARED_MEMORY.template.md`

### Quality rules

- Keep it concise and operational
- Prefer facts over narrative
- Do not record optimistic completion claims without evidence
- Remove stale information — this is a living document, not a log
- Auto-generated from `state.json` — never edit manually

### Cold-start requirement

The shared memory plus `state.json` must be strong enough that a **fresh orchestrator with no conversation history** can read them, understand the exact current state, and continue from the correct next step.

---

## Session Resume

If `dev/<feature-name>/state.json` exists when starting:

Follow `.agentic/skills/resume-feature.md`:

1. Load `state.json` as canonical state
2. Validate against git (branches, commits, working tree)
3. Detect and reconcile drift
4. Read supporting artifacts appropriate to the mode
5. Continue from the recorded `next_action`
6. Increment `telemetry.resume_count`

### Never on resume

- Do not re-derive the plan if the plan file exists
- Do not restart from phase 1 if later phases are already complete
- Do not assume prior completion without checking evidence

---

## Prompt Cache Economics (Claude side)

Every Claude sub-agent prompt is structured as `<stable prefix> + <dynamic suffix>` per `.agentic/templates/impl-prompt.template.md`. The stable prefix is byte-identical across all sub-agent invocations in a session so the automatic prompt cache has a consistent entry to hit.

Pricing (as of March 2026):
- Cache write: 1.25× base input token price (one-time per prefix)
- Cache read: 0.1× base input token price (per subsequent request within TTL)
- Default cache TTL: 5-min (reduced from 1h in March 2026)

Claim scope: a byte-identical prefix *increases the likelihood* of a cache hit. It does not guarantee one — Claude matches on `tools → system → messages`, not a raw prompt hash, and the Agent tool does not expose `cache_control` markers (per D-4). Treat measurement as best-effort: record the observed cache-hit ratio in `state.json.telemetry` when the backend surfaces it, and `unavailable` when it does not.

Prefix hygiene rules:
- Anything that mutates per phase, per attempt, or per fix-round belongs in the dynamic suffix.
- `DECISIONS.md` grows as execution proceeds; reference it from the dynamic suffix by snapshot-hash + path, never inline its contents into the stable prefix.
- Editing `AGENTS.md`, `REQUIREMENTS.md`, or the plan's Design Decisions section mid-session invalidates the prefix for that session only — expected, acceptable, but note it in telemetry.

---

## Codex CLI Invocation

When a model parameter is set to `codex`:

### For implementation/fix agents (workspace-write sandbox):
```bash
codex exec --ephemeral \
  -s workspace-write \
  -c approval_policy="never" \
  --json \
  -o dev/<feature-name>/runs/<run-id>/codex-output.md \
  "$(cat dev/<feature-name>/runs/<run-id>/agent-prompt.md)" 2>&1 \
  | tee dev/<feature-name>/runs/<run-id>/codex-output.progress.ndjson
```

### For review agents (read-only sandbox):

The orchestrator invokes `/review-feature-phase` first to render the prompt file at `dev/<feature-name>/reviews/<phase-id>-review-prompt[-rN].md`, THEN runs codex with `--output-schema` pinned:

```bash
codex exec --ephemeral \
  -s read-only \
  -c approval_policy="never" \
  --json \
  --output-schema .agentic/templates/review-verdict.schema.json \
  -o dev/<feature-name>/reviews/<phase-id>-review[-rN].md \
  < dev/<feature-name>/reviews/<phase-id>-review-prompt[-rN].md \
  > dev/<feature-name>/reviews/<phase-id>-review[-rN].progress.ndjson 2>&1
```

Flag set is byte-identical across every review round in a session (`--output-schema` path pinned, no flag added/removed between rounds). Drift invalidates codex's prefix cache.

### Structured verdicts via --output-schema (review agents)

Every review-agent codex invocation MUST include `--output-schema .agentic/templates/review-verdict.schema.json`. The schema pins verdict shape (`verdict`, `summary`, `findings[]`, `self_audit_verification`) so the orchestrator parses by field rather than regex-matching markdown. Flag path stays byte-identical across rounds — drift invalidates codex's prefix cache.

### Warmed-cache measurement protocol (codex before/after)

When measuring codex token cost for a review pathway change, the first invocation pays the prefix-cache write and overstates steady-state. Use this protocol:

1. Pick one representative phase review. Record commit range, diff byte size, allowlist file count.
2. Run the SAME review invocation three times back-to-back, byte-identical flags and prompt: R1 (cold), R2 (warm), R3 (warm).
3. Capture `turn.completed` usage events from each `*.progress.ndjson` stream: `input_tokens`, `cached_input_tokens`, `output_tokens`.
4. Discard R1. Compare (R2, R3) old-pathway vs (R2, R3) new-pathway on the SAME diff. R2 and R3 should agree within a few percent; if not, the cache isn't warming — check flag/prompt drift.
5. Record the before/after pair in `dev/<feature-name>/measurements/codex-tokens-before-after.md` with: commit range, diff bytes, allowlist size, R2+R3 tokens per pathway, delta. Cross-link from `dev/<feature-name>/DECISIONS.md`.

Never compare R1 across pathways — first-run cache-write cost dwarfs real improvement and produces misleading numbers.

### Flag rationale (codex CLI ≥ 0.118.0)

- `--ephemeral` — no on-disk session persistence between runs.
- `-s read-only` (review) / `-s workspace-write` (impl/fix) — sandbox policy. **Reviews must use `read-only`** so the review agent cannot mutate code. The legacy `--full-auto` alias forces `workspace-write` and is the wrong sandbox for reviews.
- `-c approval_policy="never"` — TOML override for the approval policy. The old `-a never` short-flag is no longer accepted on recent codex CLIs and will fail with `unexpected argument '-a'`.
- `--json` — streams per-event JSONL to stdout (thinking, tool calls, messages). Required for the streaming pattern below.
- `-o <file>` — writes the final clean message to the file. Combined with `--json | tee`, gives both the streaming progress AND the polished final artifact.
- `tee <...>.progress.ndjson` — persists JSONL events in real time so external pollers (cron, status agents) can `tail -c 8000` and parse the latest events without blocking the codex run.

### Workflow

1. Write the full agent prompt to a temp `*-prompt.md` file under `dev/<feature-name>/`.
2. Run `codex exec` with the flags above. Use `run_in_background: true` when you have non-overlapping orchestration work to do (commit dev files, prep next prompt). Otherwise run in foreground.
3. Wait for completion notification (background) or for command to return (foreground).
4. Read the `-o` output file as the authoritative review/implementation result.
5. `*.progress.ndjson` streams are transient by policy (see §Telemetry → Streaming progress). The final verdict `.md` is the canonical audit artifact; the `.progress.ndjson` siblings are gitignored (Phase 6) and may be pruned from disk at any time.

### Why streaming matters

Without `--json | tee`, codex only flushes the final message at completion. A 5–9 minute review feels stalled to any status poller. With streaming, the cron / orchestrator can answer "what is codex doing right now?" by tailing the progress file (see "Live Progress Monitoring" below).

---

## Live Progress Monitoring (optional but recommended)

For long-running review/impl cycles, set up a cron status poller via the `CronCreate` tool so the orchestrator (or a sibling Claude) reports progress at a fixed cadence instead of polling reactively.

### When to set this up

- The first time a long codex review is launched in a session.
- After resuming a feature where multiple phases remain.
- The user explicitly requests "check in every N minutes".

### Suggested cron prompt template

```
Cron check-in (every 2 min): agentic-dev status poll for <feature-name>.

Do all of the following concisely in under 150 words:

1. Read `dev/<feature-name>/state.json` — report `status`, `current_phase.id`,
   `next_action`, `telemetry.agent_runs`, `completed_phases.length`.

2. List background tasks currently running. If a codex review is in flight,
   identify its `*.progress.ndjson` file under `dev/<feature-name>/reviews/`
   and peek at it.

   Use **line-based tail** (`tail -n 5`), NOT byte-based — codex events can be
   tens of KB and a byte tail will split mid-JSON. Pattern:

   tail -n 5 <progress.ndjson> | python3 -c "
   import json, sys
   for line in sys.stdin:
       line = line.strip()
       if not line: continue
       try:
           e = json.loads(line)
           t = e.get('type','?')
           if t == 'item.completed':
               item = e.get('item', {})
               kind = item.get('type', '?')
               if kind == 'command_execution':
                   print(f'cmd: {item.get(\"command\",\"\")[:120]}')
               elif kind == 'agent_message':
                   print(f'msg: {item.get(\"text\",\"\")[:200]}')
               elif kind == 'reasoning':
                   print(f'think: {(item.get(\"text\") or item.get(\"content\",\"\"))[:200]}')
               else:
                   print(f'item: {kind}')
           elif t == 'turn.completed':
               u = e.get('usage', {})
               print(f'turn done in:{u.get(\"input_tokens\",\"?\")} out:{u.get(\"output_tokens\",\"?\")}')
           else:
               print(f'event: {t}')
       except Exception:
           print('parse fail (truncated event)')
   "

   Summarize in 1-2 sentences what codex is doing right now (e.g.,
   \"running dotnet test\", \"reading DECISIONS.md\", \"writing verdict\").

3. If a background agent looks stalled (progress file size unchanged for
   >4 min, no new events, dotnet test hung), surface it prominently.

4. If `state.json.status == \"complete\"` OR all phases are in
   `completed_phases`, delete this cron via CronDelete (id visible via
   CronList) and report cron killed.

Do NOT spawn new agents, edit code, or advance phases from inside this
check-in — read-only status polling only.
```

**Why line-based tail:** Codex's JSONL events with large nested objects (tool inputs, big text completions) can exceed 8 KB per line. `tail -c 8000` on a stream with such events produces partial JSON that fails to parse. `tail -n 5` always returns whole lines.

### Cron schedule

- Use `3-59/5 * * * *` (every 5 min, off-minute) — avoids the `:00` / `:30` clustering and gives meaningful coverage during multi-minute reviews. The 5-min cadence is calibrated against the Anthropic prompt-cache 5-min TTL: each firing is far enough from the cache boundary that a 2-min review finishes within one window, and a 9-min review spans two windows at most.
- Session-only by default (job dies when Claude exits — fine, since the cron is for the live session).
- The cron auto-deletes itself when all phases are `completed_phases` (the prompt above includes the kill condition).

### Self-cleanup

The cron prompt MUST include the auto-delete clause. If you forget, the cron will keep firing for the 7-day session window even after the feature merges.

---

## Model Selection Heuristics

The orchestrator selects the implementation-agent model per phase at dispatch time. The carrier for the plan's suggestion is `dev/<feature>/phase-manifest.json` (`phases[].suggested_model`) — feature-grained `feature-list.json` cannot unambiguously map one model per phase when a feature spans multiple phases or a phase satisfies multiple features (per codex v4 important finding). V2 grandfathered features bypass this section entirely (per D-7): the orchestrator uses opus or honors a user pin via context-doc metadata, and writes no `model_choice` fields.

### Decision flow (5 rules)

1. **Plan suggests.** Each phase entry in `phase-manifest.json` declares `suggested_model ∈ {opus, sonnet, haiku, codex}`. `codex` selects the Codex CLI backend rather than the Agent tool and does not participate in the Claude tier ladder. Default if omitted from a plan is `sonnet`.
2. **Orchestrator validates at dispatch.** Before spawning, the orchestrator runs a checklist against the phase context doc:
   - **Promote to opus if any of:**
     - Phase has unresolved design decisions at dispatch (`decisions_resolved=false`) → rationale `promoted_unresolved_decision`.
     - Scope verification (Phase 2) flagged ambiguity or cross-classification → rationale `promoted_scope_ambiguity`.
     - Phase is cross-cutting (touches ≥ 5 files OR ≥ 2 subsystems) → rationale `promoted_cross_cutting`.
     - Phase is correctness-critical (modifies a hasher, determinism pin, or INTENTIONAL HASH CHANGE class) → rationale `promoted_correctness_critical`.
     - Phase is foundational (first phase sets contracts later phases depend on) → rationale `promoted_foundational`.
   - **Stay at sonnet if:** pure mechanical migration; docs-only; tests-only against stable impl; < 5 files and < 2 subsystems. Rationale `plan_suggested`.
   - **Downshift to haiku if:** trivial edits (< 50 LOC across < 3 files); pure formatting/linting/rename. Rationale `plan_suggested`.
   - **Codex exception:** if the EFFECTIVE `model_choice = codex` at dispatch time, rule-2 promote/downshift heuristics do NOT change the model. Codex is flat: cross-cutting, correctness-critical, foundational, and similar promote/downshift checks still run for auditability, but a codex phase stays codex. Record rationale as its source value (`plan_suggested` or `user_override`) and never as `promoted_*`.
3. **Fix rounds auto-promote.** If a phase enters a fix round (review FAIL → fix dispatch), the fix-agent model auto-promotes by one tier (`haiku → sonnet`, `sonnet → opus`, `opus stays opus`). Rationale `promoted_fix_round`. Fixes are strictly harder than the original work. If the EFFECTIVE `model_choice = codex` at fix-round dispatch time (regardless of source — plan-declared via `suggested_model` or user-overridden via context-doc metadata), rule-3 promotion does NOT change the model. Codex is flat, so the orchestrator preserves `model_choice = codex` across fix rounds and keeps rationale as its source value (`plan_suggested` or `user_override`) rather than flipping to `promoted_fix_round`.
4. **User override.** Users can explicitly pin a model in the phase's context-doc metadata (`## Model choice` section); the orchestrator respects the pin verbatim and records rationale `user_override` in `state.json`.
5. **Record in state.** For v3 schema features the orchestrator writes `state.json.current_phases[i].model_choice` and `state.json.current_phases[i].model_choice_rationale` before dispatch. Telemetry `runs.ndjson` mirrors `model` per run so the heuristic can be retroactively evaluated. V2 grandfathered features omit.

### Retrospective worked example (proposal-28-followups)

| Phase | Work | Suggested model | Rationale |
|---|---|---|---|
| 1 | docs | haiku | docs-only, single file, no design ambiguity |
| 2 | dead code + rename | sonnet | mechanical, < 5 files |
| 3 | TryGetHeader accessor | opus | foundational + design decision (Option A) |
| 4 | determinism tripwire | opus | correctness-critical + scenario authoring |
| 5a | safe read migration | sonnet | mechanical, grep-classified |
| 5b | SetHeader + setter refactor | opus | cross-cutting (~30 files), design decisions |
| 6 | flat-mirror deletion | opus | INTENTIONAL HASH CHANGE |

Applying the 5-rule flow retrospectively: phases 1, 2, 5a would have downshifted (one to haiku, two to sonnet); rough ballpark 25–40% sub-agent token cost reduction on a workstream of that shape. The heuristic tightens over time via telemetry.

---

## Completion

When all phases pass review:

Follow `.agentic/skills/finalize-feature.md`:

1. Verify all phases complete with review PASS and gates passed
2. Check all requirements from REQUIREMENTS.md are met
3. Run final verification on the feature branch
4. Generate completion summary
5. Apply merge policy:
   - **`human_required`** (default): present summary, wait for approval
   - **`auto_if_green`**: merge if all checks pass, otherwise ask
6. Update final state and telemetry
7. **Archive on completion** — after the feature branch lands on `main`, move `dev/<feature-name>/` to `docs/workstreams/archive/<feature-name>/` via `git mv`. The PROPOSAL.md (if it ever lived in `dev/`) belongs at `docs/proposals/<feature-name>.md` instead — promote it before archiving so the canonical proposal lives under `docs/`. The plan file at `docs/plans/plan-<feature-name>.md` is left in place as the canonical plan record. `dev/` should contain only in-flight feature folders.

---

## Parallelism Policy

Per D-8, parallelism is neither a default nor an opt-in flag. The orchestrator evaluates each candidate phase-pair at dispatch time against the 6-item safety checklist below. All items must pass for the pair to run in parallel; any single failure forces serialization. The outcome of every evaluation — allow_parallel or serialize — is persisted to `dev/<feature>/parallelism/parallel-safety-check-<pair>.json` per `.agentic/templates/parallel-safety-check.schema.json`. The DAG the orchestrator walks is built at initialization time per `.agentic/skills/initialize-feature.md §"DAG construction"` from the plan's §"Phase dependencies" plus `dev/<feature>/phase-manifest.json`.

Checklist (canonical wording from plan §Phase 9):

- **C-1 Touched-files disjoint.** Plan declares or orchestrator infers from scope-verification. If files overlap, serialize.
- **C-2 Decisions frozen.** Both phases have zero open `Decisions needed` items. Otherwise serialize.
- **C-3 No shared-doc mutations.** Per D-10, shared artifacts (`DECISIONS.md`, `SHARED_MEMORY.md`, telemetry, review logs, feature-list) are orchestrator-only writers. Sub-agents in parallel phases MUST NOT write them.
- **C-4 Merge bookkeeping safe.** Both phases branch from the same feature HEAD; orchestrator merges sequentially into the feature branch.
- **C-5 No cross-phase test-fixture mutation.** Parallel phases can't share a test scaffolding file unless both edits are declared and conflict-checked at plan time.
- **C-6 Worktree isolation.** Parallel sub-agents work in separate git worktrees (`git worktree add`) so file writes don't interfere. Serial execution uses the main working tree.

Outcome written to `dev/<feature>/parallelism/parallel-safety-check-<pair>.json` with `{candidate_pair, checklist_results[], decision, rationale}` conforming to `.agentic/templates/parallel-safety-check.schema.json`. One file per evaluated pair (serialized pairs logged too — audit trail shows why).

### Flat branch naming (D-9)

Phase branches MUST use the flat naming pattern `feature/<feature-name>-phase-<N>` (single level, no additional slashes after the feature name). The hierarchical pattern `feature/<name>/phase-<N>` is rejected — git refs do not allow a branch and a sub-path-prefix to coexist. The flat rule applies equally to serial and parallel phase execution.

### Shared-artifact write discipline (D-10)

During both serial and parallel phase execution, every path under `dev/<feature>/` is orchestrator-only-writable UNLESS it is explicitly listed as phase-scoped below. Sub-agents MUST NOT write to any shared-artifact path; the orchestrator buffers state updates and commits them between sub-agent dispatches.

Phase-scoped (sub-agent writes allowed, scoped to the phase's path):
- `dev/<feature>/runs/<run-id>/*`
- `dev/<feature>/context/<phase-id>-context.md` (orchestrator creates; sub-agent may append)
- `dev/<feature>/verification/<phase-id>-verification.json` (orchestrator creates; read-only at run time)
- `dev/<feature>/reviews/<phase-id>-review*.md` and `.progress.ndjson`
- Phase branch code changes, restricted to the phase's declared `touched-files`.

Shared (orchestrator-only — everything else under `dev/<feature>/`):
- `state.json`, `SHARED_MEMORY.md`, `DECISIONS.md`, `REQUIREMENTS.md`, `feature-list.json`, `phase-manifest.json`, `budgets.json`, `telemetry/*`, `runtime/environment.json`, `parallelism/*`, consolidated review logs, and any future path not in the phase-scoped list.

Parallel execution enforcement: the orchestrator audits commit authorship on shared paths during each parallel window. Any sub-agent-authored commit touching a shared path is a violation — the feature's remaining phases serialize and the incident is recorded in `DECISIONS.md`.

---

## Operational Rules

1. **The plan file defines the work** — this workflow defines execution behavior, not project scope
2. **Structured state is canonical** — `state.json` drives all orchestration decisions; Markdown is a projection
3. **Verification before review** — automated gates must pass before the review agent is spawned
4. **Review gates progression** — no phase progresses based only on implementation output
5. **Fixes use a new agent** — a failed review always triggers a fresh fix agent
6. **Shared memory is mandatory** — no agent begins work without reading it first
7. **Context is layered** — agents receive focused context, not full codebase dumps
8. **Git history is the backup** — if state is lost, git log + branch state can reconstruct progress
9. **No overlapping scope** — parallel agents must pass safety checks and work on independent phases
10. **State update is part of completion** — a cycle is not done until `state.json` is updated and `SHARED_MEMORY.md` is regenerated
11. **On ambiguity, ask the user** — do not guess
12. **Decisions are recorded** — any design choice not explicitly dictated by the plan must be logged in `DECISIONS.md`
13. **Autonomous phase progression** — do not ask for permission to move from one phase to the next. After a phase passes review and merges, immediately continue. Only pause for user input when blocked or ambiguous.
14. **Background execution is conditional** — run an agent in background (`run_in_background: true`) only when: the task is bounded, no clarification is expected, permissions are already known, and waiting time can be productively overlapped with other work. Otherwise run in foreground. When running in background, continue with non-overlapping tasks (updating state, preparing next prompts, committing dev files). For long codex review/impl runs, set up the cron status poller (see "Live Progress Monitoring") so the orchestrator surfaces incremental progress instead of opaque blocking.
14a. **Codex review streaming is mandatory** — every codex review/impl invocation MUST include `--json | tee <run>.progress.ndjson` so external pollers can summarize live progress. The legacy `-o`-only invocation is obsolete (see "Codex CLI Invocation").
15. **Review loop until PASS** — after each fix agent, always re-run verification then review. Repeat until PASS or budget exceeded.
16. **Budgets are enforced** — the harness cannot loop forever without surfacing a blocker
17. **Telemetry is mandatory** — every agent run produces a telemetry event
18. **Merge policy controls final integration** — development is autonomous, but merge to main respects the configured policy

---

## Reusable Sub-Workflows

The following sub-workflows live in `.agentic/skills/` and are referenced by this orchestrator:

| Skill | Purpose |
|-------|---------|
| `initialize-feature.md` | Set up feature workspace, state, and artifacts |
| `build-phase-context.md` | Generate minimal focused context for a phase |
| `run-verification.md` | Execute verification gate pipeline |
| `run-review.md` | Spawn and process review agent |
| `process-review-failure.md` | Handle FAIL, check budgets, spawn fix agent |
| `refresh-analysis.md` | On-demand codebase analysis refresh |
| `resume-feature.md` | Resume after interruption with state validation |
| `finalize-feature.md` | Complete feature with verification and merge policy |

---

## Schemas and Templates

Located in `.agentic/templates/`:

| File | Purpose |
|------|---------|
| `state.schema.json` | Schema for `state.json` |
| `budgets.schema.json` | Schema for `budgets.json` |
| `telemetry-event.schema.json` | Schema for telemetry NDJSON events |
| `AGENTS.md` | Repo-level operational guidance template |
| `SHARED_MEMORY.template.md` | Template for SHARED_MEMORY.md |
| `DECISIONS.template.md` | Template for DECISIONS.md |
| `impl-prompt.template.md` | Canonical stable-prefix + dynamic-suffix layout for every sub-agent prompt |
