# Refresh Analysis

Reusable sub-workflow for on-demand codebase analysis refresh.

## Inputs

- `feature_name`: feature identifier
- `plan_content`: full plan content
- `analysis_model`: model to use for the analysis agent
- `trigger_reason`: why analysis is being refreshed

## When to Refresh

Refresh `CODEBASE_ANALYSIS.md` only when one of these is true:

1. **Initialization** — first analysis for a new feature (mandatory)
2. **Architecture-significant change** — a completed phase changed interfaces, schemas, or module boundaries
3. **Reviewer flag** — a reviewer flagged missing or stale architectural context
4. **Orchestrator uncertainty** — the orchestrator cannot map new work to existing knowledge
5. **Explicit request** — the user requests a refresh

Do NOT refresh:
- After every phase (wasteful — use policy-driven refresh instead)
- When only implementation details changed without architectural impact
- When the phase only added tests

## Procedure

### 1. Determine scope

Based on `trigger_reason`, decide scope:
- **Full refresh:** initialization, major architecture change
- **Incremental update:** specific module changed, add/update that section only

### 2. Spawn analysis agent

Prompt must include:
- The full plan content (so it knows what parts of the codebase are relevant)
- The trigger reason (so it knows what to focus on)
- Previous CODEBASE_ANALYSIS.md content (if incremental, so it can update rather than rewrite)
- Instruction to analyze: project structure, key files, architectural patterns, conventions, existing APIs, test infrastructure, gotchas

### 3. Write output

Write or update `dev/<feature_name>/CODEBASE_ANALYSIS.md`.

### 4. Update state

- Increment `telemetry.agent_runs`
- Write telemetry event to `runs.ndjson`

## Output

- Updated `CODEBASE_ANALYSIS.md`
- Telemetry recorded
