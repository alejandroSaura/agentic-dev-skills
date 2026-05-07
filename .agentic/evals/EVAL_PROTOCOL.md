# Evaluation Protocol — Agentic Harness

## Purpose

Measure harness performance so it can be tuned using evidence instead of intuition.

## Benchmark Task Set

Run the harness on a representative set of tasks to identify strengths and weaknesses.

### Recommended task categories

| Category | Description | Expected mode |
|----------|-------------|---------------|
| Simple bugfix | Single file fix with clear repro | lightweight |
| Medium feature | Multi-file addition, bounded scope | standard |
| Multi-phase refactor | Cross-module restructuring | full |
| Migration-like task | Schema change or API evolution | full |
| Ambiguous task | Underspecified requirement, needs clarification | standard |
| Environment-sensitive task | Depends on build/test tooling | standard |

### Task specification format

Each task in `.agentic/evals/cases/` should be a `.md` file with:

```md
# Task: <title>

## Category
<category from above>

## Description
<what needs to be done>

## Plan file
<path to the plan, or inline plan>

## Expected outcome
<what success looks like>

## Known complications
<anything that makes this non-trivial>
```

## Metrics

For each task, measure:

| Metric | Description | Better when |
|--------|-------------|-------------|
| Completion rate | Did the harness finish the task? | Higher |
| Review pass rate | First-pass review PASS percentage | Higher |
| Fix cycles | Number of fix -> re-review iterations | Lower |
| Total agent runs | Number of agents spawned | Lower |
| Time to complete | Wall-clock time from start to merge | Lower |
| Manual interventions | Times the user had to step in | Lower |
| Post-merge defects | Bugs found after completion | Lower |
| Prompt size (avg) | Average tokens per agent prompt | Lower |
| Resume reliability | Successful resumes / total resumes | Higher |

## Result Capture

### Per-task result file

Write to `.agentic/evals/results/<task-name>.json`:

```json
{
  "task": "<task-name>",
  "mode": "lightweight|standard|full",
  "completed": true,
  "review_pass_rate": 0.75,
  "fix_cycles": 2,
  "total_agent_runs": 8,
  "time_minutes": 45,
  "manual_interventions": 1,
  "post_merge_defects": 0,
  "notes": "..."
}
```

### Comparison over time

After multiple tasks, generate `.agentic/evals/compare/trends.md`:

```md
# Harness Performance Trends

## Results by Task
| Task | Mode | Completed | Fix cycles | Agent runs | Time (min) | Interventions |
|------|------|-----------|------------|------------|------------|---------------|

## Averages by Mode
| Mode | Avg fix cycles | Avg agent runs | Avg time | Avg interventions |
|------|----------------|----------------|----------|-------------------|

## Areas for Improvement
- ...
```

## Using Results

Use trends to:
- Identify which modes work best for which task types
- Tune default budgets based on observed fix cycles
- Identify verification gates that catch vs miss defects
- Adjust context strategy if prompt sizes are too large
