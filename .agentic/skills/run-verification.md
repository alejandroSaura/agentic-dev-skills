# Run Verification Gates

Reusable sub-workflow for executing the verification pipeline against a phase's work.

## Inputs

- `feature_name`: feature identifier
- `phase_id`: phase being verified
- `verification_config`: path to `dev/<feature_name>/verification/phase-<N>-verification.json`
- `run_id`: current run identifier

## Verification Gate Catalog

Available gates (each phase selects which are required):

| Gate | Description |
|------|-------------|
| `format` | Code formatting check |
| `lint` | Linter passes |
| `typecheck` | Type checking passes |
| `build` | Project builds successfully |
| `unit_tests` | Unit tests pass |
| `targeted_tests` | Tests specific to the changed area pass |
| `integration_tests` | Integration/end-to-end tests pass |
| `repro_script` | Bug reproduction script confirms fix |
| `review` | Review agent returns PASS |

## Procedure

### 1. Load or create verification config

If `dev/<feature_name>/verification/phase-<N>-verification.json` does not exist, create it based on the phase scope:

```json
{
  "phase": "<phase_id>",
  "required_gates": ["build", "targeted_tests", "review"],
  "commands": {
    "build": "dotnet build",
    "targeted_tests": "dotnet test <relevant-test-project>"
  }
}
```

Default gate selection by mode:
- **Lightweight:** `["build", "review"]`
- **Standard:** `["build", "targeted_tests", "review"]`
- **Full:** `["build", "unit_tests", "targeted_tests", "review"]`

### 2. Execute automated gates in order

Run each non-review gate in sequence. For each gate:

1. Record the command being run
2. Execute the command
3. Capture stdout/stderr and exit code
4. Record result as pass/fail

Write command log to `dev/<feature_name>/runs/<run_id>/commands.log`.

### 3. Record results

Write `dev/<feature_name>/runs/<run_id>/verification-results.json`:

```json
{
  "run_id": "<run_id>",
  "phase": "<phase_id>",
  "timestamp": "<ISO>",
  "results": {
    "build": { "status": "pass", "command": "dotnet build", "duration_ms": 1234 },
    "targeted_tests": { "status": "pass", "command": "dotnet test ...", "duration_ms": 5678 }
  },
  "all_required_passed": true
}
```

### 4. Update state.json

Update `verification.last_results` with the gate outcomes.

### 5. Gate failure handling

If any required automated gate fails:
- Do NOT proceed to review
- Report which gate failed and why
- Check budget: if `max_consecutive_gate_failures` reached, escalate
- Otherwise, return failure to orchestrator for fix cycle

## Output

- Verification results captured in run artifacts
- state.json updated
- Boolean: all required non-review gates passed
