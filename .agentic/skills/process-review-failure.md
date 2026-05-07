# Process Review Failure

Reusable sub-workflow for handling a FAIL review result and spawning a fix agent.

## Inputs

- `feature_name`: feature identifier
- `phase_id`: phase that failed review
- `review_findings`: structured findings from the review agent
- `implementation_model`: model to use for the fix agent
- `run_id`: new run identifier for this fix attempt

## Procedure

### 1. Budget check

Before spawning a fix agent, check:
- `current_phase.fix_round < budgets.max_fix_rounds_per_phase`
- `telemetry.agent_runs < budgets.max_total_agent_runs`

If either budget is exceeded:
- Set state to blocked with type `blocked_unproductive_loop`
- Write escalation summary explaining what has been tried
- Return without spawning fix agent

### 2. Unproductive retry detection

Compare the current diff with the previous fix attempt's diff (if any):
- If the changes are substantially similar (same files, similar line counts, same test failures), increment unproductive retry counter
- If `max_unproductive_retries` reached, escalate with `blocked_unproductive_loop`

### 3. Prepare fix prompt

Include in the fix agent's prompt:
- Review findings (primary input — this is what drives the fix)
- Phase scope from the plan
- Current SHARED_MEMORY.md content
- Phase context (from build-phase-context)
- Instruction to scope work to the review feedback, not the whole project
- Instruction to produce a handoff summary

### 4. Spawn fix agent

Using the configured `implementation_model`:
- If Claude model: use Agent tool with `model` parameter
- If codex: use Codex CLI in full-auto mode

### 5. After fix returns

1. Commit: `fix(<phase>): <finding addressed>`
2. Record touched files in `dev/<feature_name>/runs/<run_id>/touched-files.json`
3. If the fix agent changed a design decision or made a new one, update DECISIONS.md
4. Update SHARED_MEMORY.md with fix summary
5. Update state.json:
   - Increment `current_phase.fix_round`
   - Increment `telemetry.agent_runs`
   - Set `next_action` to "run_verification"
6. Write telemetry event to `runs.ndjson`

## Output

- Fix committed on phase branch
- State updated
- Orchestrator should proceed to run-verification, then run-review
