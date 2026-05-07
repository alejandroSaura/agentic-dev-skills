# Scope Verification Template

This template produces the `## Scope verification` section embedded in every
phase context doc at `dev/<feature>/context/<phase-id>-context.md`.

The orchestrator runs the relevant grep set before dispatching the phase's
implementation agent. Results are pasted INLINE into the phase context doc;
the sub-agent never repeats the search. Dispatch blocks if this section is
missing or contains an unresolved anomaly flag (see `build-phase-context.md`
§"Pre-dispatch steps").

Artifact ownership per D-10: the orchestrator writes and maintains this
section in the phase context doc; phase sub-agents only read it.

## When to run

Before every phase dispatch (implementation, fix, or review). Re-run between
fix rounds if the touched-file set changed. The probe is cheap; running it
twice is always safer than skipping it.

## Canonical grep set (adjust per phase)

For each target symbol, API, or module this phase touches, record the exact
command and its match count. Use repo-root-relative paths (verification cwd
convention, D-11).

| Intent | Command shape |
|---|---|
| All references (broad sweep) | `grep -rn '<symbol>' src/ tests/ benchmarks/` |
| Reads only (filter out guarded accessors) | `grep -rn '<api>(' src/ tests/ \| grep -v TryGet` |
| Writes via ref | `grep -rn 'ref var .* = ref .*<api>' src/ tests/` |
| Call-site of a specific overload | `grep -rnE '<symbol>\s*\([^)]*<arg-type>' src/ tests/` |
| Full-tree fallback | `grep -rn '<symbol>' .` (last resort; noisy) |

Prefer the narrowest shape that still surfaces every site the plan claims to
touch. Broad sweeps are required when the plan's inventory is an estimate.

## Result shape (paste into phase context doc)

```markdown
## Scope verification

Run at: <ISO-8601 timestamp>
Cwd: <repo root>
Phase: <phase-id>

| # | Command | Match count | Classification | Notes |
|---|---|---|---|---|
| 1 | `grep -rn 'FooService' src/` | 14 | 12 reads, 2 writes | matches plan inventory |
| 2 | `grep -rn 'FooService' tests/` | 3 | all reads | matches plan inventory |
| 3 | `grep -rn 'FooService' benchmarks/` | 0 | n/a | expected |

Anomalies: none
```

If any anomaly is flagged, leave the section in the context doc with the
anomaly listed and a resolution note. Dispatch remains blocked until the
anomaly is resolved (reconciled with the plan, plan amended, or scope
adjusted).

## Anomaly flags that BLOCK dispatch

- Match count materially diverges from the plan's inventory (> 20 % deviation
  in either direction).
- Sites classified as different categories than the plan predicted (e.g., plan
  says "reads only" but scope verification finds writes).
- Any unexpected hit in test files that would invalidate the plan's scope
  assumption (e.g., a test exercises a branch the plan marked out-of-scope).
- A command returns 0 matches when the plan claims the symbol exists.
- A broad sweep surfaces matches in files the phase is NOT supposed to
  touch — signals hidden scope creep.

## Resolution workflow

1. Orchestrator detects anomaly and records it in this section.
2. Orchestrator either (a) amends the plan/CODEBASE_ANALYSIS to reflect the
   real scope, then re-runs this probe, or (b) narrows phase scope to exclude
   the surprise sites.
3. Once the section shows "Anomalies: none" (or all anomalies marked
   `resolved`), dispatch unblocks.
