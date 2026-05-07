# Architecture Map

Maps the harness sections to their locations across the main skill and supporting files.

## Skill Section → File Mapping

| Skill Section | Implementation Location | Notes |
|---|---|---|
| Arguments | `agentic-dev.md` → Arguments | `plan`, `mode`, models, `final_merge_policy` |
| Role | `agentic-dev.md` → Role | Orchestrator-only, no direct implementation |
| Agent Backends | `agentic-dev.md` → Agent Backends | Claude models + Codex CLI |
| Agent Roles → Analysis | `agentic-dev.md` + `refresh-analysis.md` | On-demand refresh, policy-driven |
| Agent Roles → Implementation | `agentic-dev.md` → Agent Roles | Receives phase context, not full analysis |
| Agent Roles → Review | `agentic-dev.md` + `run-review.md` | Must inspect gate outputs + diff |
| Agent Roles → Fix | `agentic-dev.md` + `process-review-failure.md` | Budget-checked before spawning |
| Initialization | `agentic-dev.md` + `initialize-feature.md` | Mode-aware artifact creation |
| Git Strategy | `agentic-dev.md` → Git Strategy | Parallel safety check for full mode |
| Execution Cycle | `agentic-dev.md` → Execution Cycle | Verification gates before review |
| Phase Context | `build-phase-context.md` | Layered by mode (lightweight → full) |
| Verification | `run-verification.md` | Multi-gate pipeline with per-phase config |
| Review | `run-review.md` | Gates must pass first |
| Fix Cycle | `process-review-failure.md` | Budget checks + retry detection |
| Analysis Refresh | `refresh-analysis.md` | Policy-driven, not mandatory |
| Resume | `resume-feature.md` | State-validated with drift detection |
| Completion | `finalize-feature.md` | Merge policy + cleanup + telemetry |
| Structured State | `agentic-dev.md` → Structured State | `state.json` as canonical source |
| Execution Modes | `agentic-dev.md` → Execution Modes | lightweight / standard / full |
| Budget & Escalation | `agentic-dev.md` → Budget and Escalation | Prevents unbounded loops |
| Telemetry | `agentic-dev.md` → Telemetry | Per-run events + feature summary |
| Context Strategy | `agentic-dev.md` → Context Strategy | 4-layer just-in-time context |
| Runtime Isolation | `agentic-dev.md` → Runtime Isolation | Environment fingerprinting |
| Merge Policy | `agentic-dev.md` → Completion | human_required / auto_if_green |

## Artifact Mapping

| Artifact | Location | Purpose |
|---|---|---|
| `state.json` | `dev/<feature>/` | Canonical machine-readable state |
| `SHARED_MEMORY.md` | `dev/<feature>/` | Auto-generated from state.json |
| `DECISIONS.md` | `dev/<feature>/` | Design decisions log |
| `CODEBASE_ANALYSIS.md` | `dev/<feature>/` | Codebase analysis (refreshed on demand) |
| `REQUIREMENTS.md` | `dev/<feature>/` | Completion requirements |
| `budgets.json` | `dev/<feature>/` | Budget config (standard+ modes) |
| `environment.json` | `dev/<feature>/runtime/` | Env fingerprint (standard+ modes) |
| `phase-<N>-verification.json` | `dev/<feature>/verification/` | Gate config per phase |
| `runs.ndjson` | `dev/<feature>/telemetry/` | Per-run telemetry events |
| `summary.json` | `dev/<feature>/telemetry/` | Feature-level stats |
| `phase-<N>-context.md` | `dev/<feature>/context/` | Focused phase context |
| `parallel-safety-check.json` | `dev/<feature>/parallelism/` | Parallel safety check (full mode) |
| `review-phase-<N>.md` | `dev/<feature>/reviews/` | Review logs per phase |
| `touched-files.json` | `dev/<feature>/runs/<run-id>/` | Files modified per run |
| `verification-results.json` | `dev/<feature>/runs/<run-id>/` | Gate results per run |
| `commands.log` | `dev/<feature>/runs/<run-id>/` | Command log per run |

## Schema Files

| Schema | Location | Validates |
|---|---|---|
| `state.schema.json` | `.agentic/templates/` | `state.json` |
| `budgets.schema.json` | `.agentic/templates/` | `budgets.json` |
| `telemetry-event.schema.json` | `.agentic/templates/` | `runs.ndjson` entries |
