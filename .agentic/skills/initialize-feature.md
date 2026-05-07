# Initialize Feature Workspace

Reusable sub-workflow for setting up a new feature's development workspace.

## Inputs

- `feature_name`: kebab-case feature identifier
- `plan_path`: path to the plan .md file
- `mode`: lightweight | standard | full
- `budgets`: budget overrides (optional, defaults from budgets.schema.json)

## Procedure

### 1. Create feature branch

```
git checkout main
git checkout -b feature/<feature_name>
```

### 2. Create dev folder structure

Create `dev/<feature_name>/` with the following:

**Always (all modes):**
- `state.json` — initialize from state.schema.json with status=initializing
- `SHARED_MEMORY.md` — from SHARED_MEMORY.template.md
- `REQUIREMENTS.md` — from user input (Step 2 of initialization)
- `DECISIONS.md` — from DECISIONS.template.md
- `feature-list.json` — drafted by the orchestrator from the plan's §"Acceptance" and §"Verification Commands" sections, conforming to `.agentic/templates/feature-list.schema.json`. See Step 4a below.
- `reviews/` — empty directory
- `verification/` — empty directory
- `context/` — empty directory
- `runs/` — empty directory

**Standard and full modes additionally:**
- `budgets.json` — initialization-time config, values are copied into `state.json.budgets`
- `runtime/environment.json` — capture environment fingerprint
- `telemetry/runs.ndjson` — empty file

**Full mode additionally:**
- `parallelism/` — empty directory

### 3. Capture environment fingerprint (standard + full)

Write `dev/<feature_name>/runtime/environment.json`:

```json
{
  "os": "<detected>",
  "shell": "<detected>",
  "runtime_versions": {
    "dotnet": "<dotnet --version output>",
    "node": "<node --version if applicable>"
  },
  "captured_at": "<ISO timestamp>",
  "worktree_path": null,
  "branch": "feature/<feature_name>",
  "commit_sha_at_start": "<HEAD SHA>"
}
```

### 4. Initialize state.json

```json
{
  "feature_name": "<feature_name>",
  "plan_path": "<plan_path>",
  "workflow_version": "v2",
  "schema_version": "v3",
  "status": "initializing",
  "mode": "<mode>",
  "current_phase": null,
  "completed_phases": [],
  "verification": { "required_gates": [], "last_results": {} },
  "budgets": {
    "max_review_rounds_per_phase": 4,
    "max_fix_rounds_per_phase": 4,
    "max_total_agent_runs": 50,
    "max_parallel_agents": 2,
    "max_unproductive_retries": 2,
    "max_consecutive_gate_failures": 3,
    "escalation_policy": {
      "on_review_budget_exceeded": "ask_user",
      "on_fix_budget_exceeded": "ask_user",
      "on_unproductive_loop": "block",
      "on_gate_failure_loop": "ask_user"
    }
  },
  "telemetry": { "agent_runs": 0, "resume_count": 0 },
  "project_knowledge": [],
  "last_handoff": null,
  "next_action": "gather_requirements",
  "blockers": [],
  "last_updated": "<ISO timestamp>"
}
```

### 4a. Draft feature-list and block on user sign-off (mandatory per D-2)

Drafting `feature-list.json` is mandatory. Initialization blocks until the user signs off on the drafted feature-list. Per D-2.

Procedure:

1. Read the plan's §"5. Phases" (or `Phases` section by whichever numbering), §"8. Success Criteria", and §"9. Verification Commands". Every declared acceptance check becomes a feature-list entry.
2. Populate `dev/<feature_name>/feature-list.json` conforming to `.agentic/templates/feature-list.schema.json`:
   - Each entry needs `id` (F-NNN, zero-padded), `description` (one-line observable pass condition), `verification_command` (shell, repo-root-relative per D-11), `status` initialized to `pending`, `passed_at: null`, and `blocking_phase` (e.g. `phase-3`).
   - Run `jq empty dev/<feature_name>/feature-list.json` — it MUST exit 0. If jq fails, fix the draft before proceeding.
3. Evaluate the scale-down rule (see `.agentic/templates/plan.template.md` §"Feature list — 1-entry scale-down rule"). A 1-entry feature-list is only valid when ALL four conditions hold (exactly one observable behavior, exactly one verification command, zero cross-phase dependencies, touched-files ≤ 3). If any fails, the draft needs multiple entries.
4. Present the drafted list to the user and explicitly ask: "Approve feature-list.json as drafted, or request edits?" The orchestrator MUST NOT dispatch any phase until the user answers "approve" (or equivalent). Edits iterate in place; the approval gate is re-asked each round.
5. Record the approval moment in `SHARED_MEMORY.md` under a `## Feature list sign-off` heading with the ISO timestamp.
6. On approval, proceed to Step 5 (initial commit) so the feature-list lands in the first commit alongside state.json.

This gate catches granularity mismatches at drafting time rather than at finalize, when a missing feature would stall the main merge.

### 4b. DAG construction (v3 features, prepares Phase 9 parallel-safety evaluation)

After the feature-list is signed off (Step 4a), the orchestrator constructs the phase dependency graph so the §Parallelism Policy in `.claude/commands/agentic-dev.md` has a concrete DAG to evaluate candidate pairs against at dispatch time. Per D-8, parallelism is neither a default nor a flag — it is a runtime judgment the orchestrator makes per pair using the 6-item C-1..C-6 checklist specified by `.agentic/templates/parallel-safety-check.schema.json`. That judgment requires a pre-built DAG; initialization is where the DAG is assembled.

Procedure:

1. **Read the plan's §"Phase dependencies" section** (per `plan.template.md` §6). The section declares edges as lines of the form `Phase A ──▶ Phase B` meaning "phase B depends on phase A". Leaf phases are declared as `Phase X ──▶ (no downstream)`. Every phase referenced in the plan's §"Phases" MUST appear in §"Phase dependencies" — the initializer errors if a phase is missing, since an unreferenced phase is ambiguous (does it run first? last? never?).
2. **Read `dev/<feature_name>/phase-manifest.json`** (see `.agentic/templates/phase-manifest.schema.json`). The manifest's `phases[].dependencies` array is the machine-readable form of the same DAG; the plan section is the human-readable narration. The two MUST agree. If they diverge the initializer flags the divergence and blocks until the user reconciles (usually by editing the plan to match the manifest, since the manifest is load-bearing at dispatch).
3. **Build the DAG in memory** as an adjacency list keyed by phase id. Nodes: every `phases[].id` from the manifest. Edges: for each `phases[i]`, draw an edge from every id in `phases[i].dependencies` to `phases[i].id`. Detect cycles — any cycle is a plan bug and the initializer refuses to proceed (documented in `phase-manifest.schema.json.phaseEntry.dependencies`: "Cycles are a plan bug; orchestrator refuses to dispatch on detection.").
4. **Compute the initial candidate set.** Phases with zero dependencies can be considered for parallel dispatch at feature start. Phases whose dependencies are all in `completed_phases[]` become candidates at each cycle. The initializer does not yet evaluate the candidates against the C-1..C-6 checklist — that evaluation is per-dispatch (runtime) because C-2 (decisions frozen) and C-3 (no shared-doc mutations) can change between initialization and dispatch.
5. **Persist the DAG implicitly** via the manifest. The orchestrator does not write a separate DAG file; the manifest IS the DAG. At dispatch time the orchestrator re-reads the manifest and re-derives the adjacency list, so any mid-feature manifest edits (with user sign-off) flow through automatically.
6. **Do NOT populate `dev/<feature_name>/parallelism/`** during initialization. That directory stays empty until the first parallel-safety evaluation at dispatch time. Artifacts land as `parallel-safety-check-<pair>.json` per `.agentic/templates/parallel-safety-check.schema.json` — one file per candidate pair the orchestrator evaluates, whether the outcome is `allow_parallel` or `serialize`.

Output of this step: a validated manifest (no cycles, no missing phases, dependencies match plan §6), and an in-memory DAG the orchestrator can query at every subsequent dispatch. The §Parallelism Policy section of `.claude/commands/agentic-dev.md` describes how the orchestrator uses the DAG at dispatch time to pick candidate pairs and evaluate them against the C-1..C-6 safety checklist (`.agentic/templates/parallel-safety-check.schema.json`). Per D-10, the orchestrator is the sole writer of files under `dev/<feature_name>/parallelism/`; sub-agents never touch them.

For v2 grandfathered features this step is skipped (single-phase execution has no DAG to build).

### 5. Initial commit

```
git add dev/<feature_name>/
git commit -m "chore: initialize agentic workflow for <feature_name>"
```

## Output

- Initialized `dev/<feature_name>/` directory
- `state.json` with status=initializing
- Feature branch created and initial commit made
