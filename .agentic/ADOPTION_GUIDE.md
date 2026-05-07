# Adoption Guide

## Quick Start

```
/agentic-dev plan=path/to/your-plan.md
```

The harness will auto-select execution mode based on your plan's complexity. You can also specify explicitly:

```
/agentic-dev plan=path/to/plan.md mode=lightweight
/agentic-dev plan=path/to/plan.md mode=standard
/agentic-dev plan=path/to/plan.md mode=full
```

## Choosing a Mode

| Mode | Use when | Artifacts created | Overhead |
|------|----------|-------------------|----------|
| **Lightweight** | Single bugfix, one-file change, quick fix | state.json, SHARED_MEMORY.md, DECISIONS.md, verification/, context/, runs/ | Minimal |
| **Standard** | Multi-file feature, bounded refactor, 2-4 phases | Above + budgets.json, environment.json, telemetry | Moderate |
| **Full** | Migration, subsystem rewrite, 5+ phases, parallel work | All artifacts including parallelism checks | Full |

## Key Features

1. **`state.json` as canonical state** — machine-readable, drives all orchestration decisions. SHARED_MEMORY.md is auto-generated from it.
2. **Layered context** — agents get focused phase context instead of full codebase analysis every time
3. **Verification gates** — build, tests must pass before review starts
4. **Budget controls** — prevents infinite fix loops, escalates to you instead
5. **Telemetry** — captured for every agent run
6. **Merge policy** — final merge to main always requires your approval

## Configuration Options

### Merge policy

```
/agentic-dev plan=plan.md final_merge_policy=auto_if_green
```

- `human_required` (default): presents a completion summary and waits for your approval before merging to main
- `auto_if_green`: merges automatically if all verification passes and requirements are met

### Budget overrides

Edit `dev/<feature-name>/budgets.json` to adjust limits per feature:

```json
{
  "max_review_rounds_per_phase": 6,
  "max_fix_rounds_per_phase": 6,
  ...
}
```

### Model selection

Mix models for different roles:

```
/agentic-dev plan=plan.md implementation_model=sonnet review_model=opus
```

## Cleanup

After a feature completes and merges, the `dev/<feature-name>/` folder is automatically deleted. All artifacts are ephemeral — git history preserves what matters.
