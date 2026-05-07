# Finalize Feature

Reusable sub-workflow for completing a feature after all phases pass review.

## Inputs

- `feature_name`: feature identifier
- `final_merge_policy`: `human_required` (default) | `auto_if_green`

## Procedure

### 1. Verify all phases complete

Read `state.json` and confirm:
- All phases from the plan are in `completed_phases`
- Every completed phase has `review_passed: true` and `merged: true`
- `current_phase` is null or the last phase
- No unresolved blockers

If any phase is incomplete, return to orchestrator with the gap identified.

### 1a. Verify feature-list (mandatory per D-2, v3 schema only)

For v3 features (`state.json.schema_version == "v3"`), finalize blocks until every feature-list.json entry has status=passed. Run `jq '.features | map(select(.status != "passed")) | length' dev/<feature_name>/feature-list.json` — must return 0 before proceeding to main merge.

Procedure:

1. Confirm `dev/<feature_name>/feature-list.json` exists. If missing on a v3 feature, halt: the feature was not initialized under the mandatory D-2 contract and cannot finalize.
2. From the repo root, run:
   ```bash
   cd $(git rev-parse --show-toplevel)
   jq '.features | map(select(.status != "passed")) | length' dev/<feature_name>/feature-list.json
   ```
   The command must print `0`. Any non-zero count means one or more features are still `pending`, `in_progress`, or `blocked` — finalize halts and lists the offending entries (`jq '.features[] | select(.status != "passed") | {id, status, blocking_phase}'`).
3. Orchestrator escalates to the user with the list of non-passed entries and the `blocking_phase` for each. Main merge MUST NOT proceed while any entry is non-passed.
4. For v2 grandfathered features (no `feature-list.json`), skip this step — their finalize semantics predate D-2. Surface the one-line banner described in `.agentic/skills/resume-feature.md` so the user knows the feature is running in grandfathered mode.

### 2. Check requirements

Read `dev/<feature_name>/REQUIREMENTS.md` and verify each requirement:
- Map each requirement to implemented work
- Confirm evidence exists (tests, review logs, git history)
- List any unmet requirements

If requirements are unmet, report the gaps and do NOT proceed to merge.

### 3. Run final verification

Execute all verification gates one last time on the feature branch:
- Build must pass
- All tests must pass
- Any integration tests must pass

Record results in `dev/<feature_name>/verification/final-verification.json`.

### 4. Generate completion summary

Write to `dev/<feature_name>/COMPLETION_SUMMARY.md`:

```md
# Completion Summary — <feature_name>

## Phases Completed
| Phase | Review rounds | Fix rounds | Merged commit |
|---|---|---|---|

## Requirements Status
| Requirement | Met | Evidence |
|---|---|---|

## Final Verification
| Gate | Result |
|---|---|

## Telemetry
- Total agent runs: <N>
- Total review rounds: <N>
- Total fix rounds: <N>
- Total resume events: <N>
- Gate pass rates: <build: X%, tests: Y%, ...>
- Time span: <first commit> to <last commit>

## Decisions Made
<count> decisions logged in DECISIONS.md

## Open Items
- <any remaining concerns or follow-up work>
```

### 5. Apply merge policy

**If `human_required` (default):**
- Present the completion summary to the user
- Wait for explicit approval before merging
- Do NOT merge autonomously

**If `auto_if_green`:**
- If all verification passed and all requirements met:
  ```
  git checkout main
  git merge feature/<feature_name>
  git branch -d feature/<feature_name>
  ```
- If any check failed, fall back to `human_required`

### 6. Update final state

Update `state.json`:
- Set `status` to `complete`
- Set `next_action` to `none`
- Set `last_updated`

Write final telemetry event.

### 7. Retain dev folder as audit trail

**Default behavior: `dev/<feature_name>/` is retained after merge as the feature's audit trail.**

The folder contains the authoritative record of how the feature was executed — plan, decisions, review verdicts, telemetry, and measurement artifacts. Downstream tooling depends on retention:
- Phase 1 and Phase 7 cache/token measurement artifacts live under `dev/<feature_name>/` and are consulted by later features when calibrating prompt structure or codex invocation flags.
- Post-mortem reviews and heuristic tuning (per the agentic-dev skill) re-read prior `DECISIONS.md`, `feature-list.json`, and `reviews/` to extract patterns.
- `telemetry/runs.ndjson` feeds the rolling corpus used to refine model-selection and parallelism heuristics.

Git history preserves source changes, but it does NOT capture the planning-and-review artifacts produced outside tracked files — those exist only under `dev/<feature_name>/`.

#### User-opt-in cleanup

If — and only if — the user explicitly asks to prune `dev/<feature_name>/` for this specific feature (e.g. "delete the dev folder for <feature_name>"), remove the directory after the merge completes. Never prune proactively; never apply this to other features in the same pass. When pruning, confirm in the completion summary which measurement artifacts (if any) are being discarded so the user has a last chance to archive.

## Output

- Completion summary presented to user (includes telemetry stats)
- Merge executed (if policy allows) or user approval requested
- `dev/<feature_name>/` retained as audit trail (default) or pruned on explicit user request
