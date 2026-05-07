# AGENTS.md — Repo-Level Operational Guidance

This file contains stable instructions that all agents need. It is repo-level context (Layer 1) and should not contain per-feature or per-phase state.

---

## Coding Conventions

- Follow existing patterns and conventions already established in the codebase
- Do not add features, refactor code, or make improvements beyond what was asked
- Do not add error handling, fallbacks, or validation for scenarios that cannot happen
- Prefer editing existing files over creating new ones
- Be careful not to introduce security vulnerabilities
- Targeted reads: for files over 200 lines, prefer `Grep -n <specific-pattern>` or `Read --offset --limit` over full-file `Read`. Use `Glob` for file discovery. Full-file `Read` is reserved for files <= 200 lines or when the whole file is directly relevant to the task.

## Branching Conventions

- Feature branches: `feature/<feature-name>`
- Phase branches: `feature/<feature-name>-phase-<N>` (flat per D-9 — hierarchical `feature/<name>/phase-<N>` is forbidden because git refs cannot coexist with sub-path-prefix branches)
- Phase branches merge into feature branch on review PASS
- Feature branch merges into main on completion (subject to merge policy)
- Phase branches are deleted after merge

## Commit Conventions

- After implementation: `feat(<phase>): <short description>`
- After fix: `fix(<phase>): <finding addressed>`
- After merge: `merge: phase-<N> complete`
- Workflow init: `chore: initialize agentic workflow for <feature-name>`

## Test Commands

- Build: `dotnet build`
- Runtime tests: `dotnet test tests/runtime/Runtime.Tests.csproj`
- Compiler tests: `dotnet test tests/compiler/Compiler.Tests.csproj`
- All tests: `dotnet test`

## Review Rules

- A phase is NOT complete because an implementation agent says it is
- A phase is complete only when the review agent returns PASS AND all required verification gates pass
- Review agents must inspect gate outputs, not only diff content
- Fix agents address specific review findings, scoped to the feedback

## Safety Constraints

- Never force-push to main
- Never skip git hooks without explicit user approval
- Never commit secrets or credentials
- Always verify before destructive git operations
- Merge to main requires explicit approval unless `final_merge_policy=auto_if_green`

## Orchestration Artifacts

All per-feature state lives under `dev/<feature-name>/`:

```
dev/<feature-name>/
  state.json              — canonical machine-readable state
  budgets.json            — budget configuration
  SHARED_MEMORY.md        — human-readable operational state
  DECISIONS.md            — design decisions log
  CODEBASE_ANALYSIS.md    — codebase analysis (refreshed on demand)
  REQUIREMENTS.md         — completion requirements
  runtime/
    environment.json      — environment fingerprint
  verification/
    phase-<N>-verification.json
  telemetry/
    runs.ndjson           — per-run telemetry events
    summary.json          — aggregated feature-level stats
  context/
    phase-<N>-context.md  — minimal phase context
  parallelism/
    parallel-safety-check.json
  reviews/
    review-phase-<N>.md
  runs/<run-id>/
    touched-files.json
    verification-results.json
    commands.log
```
