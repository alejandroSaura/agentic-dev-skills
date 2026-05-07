# Resume Feature

Reusable sub-workflow for resuming a feature after context loss, process interruption, or session restart.

## Inputs

- `feature_name`: feature identifier (derived from dev/ folder or provided by user)

## Procedure

### 1. Load structured state

Read `dev/<feature_name>/state.json`. This is the canonical source of truth.

If `state.json` does not exist, the feature cannot be resumed. Report an error to the user.

### 1a. Detect schema version and apply grandfathering (per D-7)

Read `state.json.schema_version`. If absent, treat as `v2` (pre-proposal-29 features predate the field).

Grandfathering: if `state.json.schema_version == 'v2'`, skip feature-list requirement, use single `current_phase` shape, omit `model_choice` fields. Banner: 'This feature was initialized under schema v2; running in grandfathered mode.'

Concretely, under v2 schema mode the orchestrator:

- Does NOT require `dev/<feature_name>/feature-list.json` (Phase 8 mandatory-feature-list rule bypassed).
- Reads `state.json.current_phase` (object or null) instead of `current_phases[]` (array). All phase-dispatch logic collapses to the single-phase path — no parallel dispatch.
- Omits `current_phase.model_choice` and `current_phase.model_choice_rationale` when writing state (Phase 10 per-phase model selection bypassed; orchestrator uses opus by default or a user-pinned override via context-doc metadata).
- Runs `finalize-feature.md` under the original pre-D-2 semantics — no `jq '.features | map(select(.status != "passed")) | length'` gate.
- Emits the grandfathering banner above to the user on resume so the running mode is unambiguous.

If `schema_version == 'v3'` (or absent-but-clearly-v3 by presence of `current_phases[]`), apply the full mandatory-feature-list + parallel + model-choice rules documented in the other skill files.

A v2 feature never auto-upgrades. Migration to v3 is an explicit user-requested `upgrade-schema` step (out of scope of this skill).

### 2. Validate state against git

Check for drift between recorded state and git reality:

| State field | Git check |
|---|---|
| `current_phase.branch` | Does the branch exist? Is it checked out? |
| `completed_phases[].merged` | Do merge commits exist on the feature branch? |
| `completed_phases[].merged_commit` | Does the commit exist? |
| `status` | Does the working tree have uncommitted changes? |

If drift is detected:
- Log the drift in SHARED_MEMORY.md
- Attempt to reconcile (prefer git reality over stale state)
- Update state.json to reflect actual git state
- If reconciliation fails, set blocker `blocked_needs_human_decision`

### 3. Read supporting artifacts

Based on mode, read:
- **Always:** SHARED_MEMORY.md, DECISIONS.md (budgets are always in state.json)
- **Standard+:** latest verification results, runtime/environment.json
- **Full:** CODEBASE_ANALYSIS.md, parallelism checks, telemetry

### 4. Determine next action

From `state.json.next_action`, determine what to do:
- `gather_requirements` → continue initialization
- `run_analysis` → spawn analysis agent
- `spawn_implementation` → spawn implementation agent for current phase
- `run_verification` → run verification gates
- `spawn_review` → spawn review agent
- `spawn_fix` → spawn fix agent with last review findings
- `merge_phase` → merge current phase branch
- `advance_phase` → move to next phase
- `finalize` → run finalize-feature
- `blocked` → report blocker to user

### 5. Increment resume counter

Update `telemetry.resume_count` in state.json.

### 6. Generate resume report

Output a concise summary:

```
Resume Report — <feature_name>
  Mode: <mode>
  Status: <status>
  Current phase: <phase_id> — <title>
  Attempt: <N>, Review rounds: <N>, Fix rounds: <N>
  Budget: <used>/<max> review rounds, <used>/<max> fix rounds
  Blockers: <list or none>
  Next action: <next_action>
  Drift detected: <yes/no, details if yes>
```

## Rules

- Never re-derive the plan if the plan file exists
- Never restart from phase 1 if later phases are complete
- Never assume prior completion without checking evidence (review log, git history)
- Always prefer state.json over SHARED_MEMORY.md for orchestration decisions

## Output

- Validated and reconciled state
- Clear next action for the orchestrator
- Resume report for user visibility
