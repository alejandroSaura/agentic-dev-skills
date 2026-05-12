Run-exit-demo workflow. Drives a consumer plan's exit demo via the `dev/demo-e2e/` cross-host harness on a dedicated Opus 4.7 sub-agent, applies a fixed-rule recovery + triage pipeline, and emits `dev/<plan>/demo-state.json` for `/roadmap-runner` to consume.

This workflow defines **how to execute an exit demo and classify its outcome**, not what the demo tests. It is consumer-agnostic; the consumer plan slug + spec glob are the only project-specific inputs. The entrypoint itself writes no code and contains no recovery logic — it composes three sub-skills (`run-exit-demo-recover` → `run-exit-demo-dispatch` → `run-exit-demo-triage`) on a freshly-dispatched sub-agent.

---

## Skill asset lookup (global installation)

This skill ships in two locations:
- Project-local: `<repo-root>/.claude/commands/run-exit-demo.md` + `<repo-root>/.agentic/`
- User-global: `~/.claude/commands/run-exit-demo.md` + `~/.agentic/`

When this file references `.agentic/templates/<X>` or `.agentic/skills/<X>`, resolve in this order:
1. `<cwd>/.agentic/<X>` — project-local override (preferred when present).
2. `~/.agentic/<X>` — user-global fallback.

This rule also applies inside the sub-skills under `.agentic/skills/run-exit-demo-*.md` (they reference each other and the `demo-state.schema.json` with the same project-relative shorthand).

Output paths (`dev/<plan>/demo-state.json`, run-logs archive directories under `dev/<plan>/`) are ALWAYS resolved relative to `<cwd>` — never `~/`. Only `.agentic/` skill assets fall back to the user home.

---

## Nomenclature

- **Consumer plan** — the plan whose exit demo is being run. Identified by `plan=<slug>`. The skill is consumer-agnostic; it never reads the plan markdown, only the slug and the spec glob.
- **Harness** — `dev/demo-e2e/` in the consumer repo. The `make demo-e2e` target and its Playwright config. The skill never edits the harness.
- **`demo-state.json`** — the canonical exit-state artefact this skill produces at `dev/<plan>/demo-state.json` (or the override path supplied by the runner). Schema: `.agentic/templates/demo-state.schema.json`. This file is the **only** contract surface between this skill and `/roadmap-runner` (per plan D-2).
- **Run-logs archive** — the per-invocation directory the dispatch sub-skill creates for harness stdout, Playwright reporter copy, recovery transcripts, and host-key fingerprint captures. `demo-state.json` references entries here by path, never by inlined content (R-10).

---

## Arguments

`$ARGUMENTS` must contain named parameters:

| Parameter | Required? | Default | Notes |
|---|---|---|---|
| `plan=<slug>` | required | — | Consumer plan slug (e.g. `durability`). Used as the path key for `dev/<plan>/demo-state.json` and as the run-logs archive scope. |
| `spec_glob=<glob>` | required | — | Path or glob to the Playwright spec(s) the harness should run. The entrypoint itself applies no default — the runner applies `dev/demo-e2e/tests/<slug>.spec.ts` upstream (plan D-6) and passes the resolved value here. |
| `hosts_yaml=<path>` | required | — | Inventory file path passed through to the harness. Typical value `dev/demo-e2e/hosts.yaml`. |
| `model=<id>` | optional | `opus` | Model for the dispatched sub-agent that runs the recover → dispatch → triage chain. Forwarded to the `Agent` tool's `model` param at spawn time (plan D-5). The `Agent` tool accepts the friendly names `opus`, `sonnet`, `haiku` only — `opus` is the documented default and should not be lowered without an explicit reason; cross-host recovery + diagnosis benefit from deep reasoning on small structured outputs. |
| `retry_budget=<n>` | optional | `1` | Combined harness+unknown retry budget. The total number of dispatches per skill invocation is bounded by `1 + retry_budget` (so the default `1` permits one retry after the initial dispatch, for a hard cap of two `make demo-e2e` runs). |

Example: `/run-exit-demo plan=durability spec_glob=dev/demo-e2e/tests/durability.spec.ts hosts_yaml=dev/demo-e2e/hosts.yaml`

---

## Role

You are the **exit-demo orchestrator**. You do NOT run the harness, recover from failures, or classify outcomes yourself. You:

1. Validate the args, derive the state-file path (`dev/<plan>/demo-state.json` unless the runner supplied an override), and prepare the run-logs archive root (`dev/<plan>/runs/<timestamp>/`).
2. Spawn a single sub-agent via the `Agent` tool (`subagent_type: general-purpose`, `model: <model>`) with a prompt that composes the three sub-skills in order.
3. After the sub-agent returns, confirm `demo-state.json` exists at the expected path and validates against `demo-state.schema.json`. Return its `status` (`pass | blocked | fail`) to the caller.

You do not classify, retry, or interpret failures — every behaviour is owned by the sub-skills. You are bookkeeping and dispatch.

---

## Design Principles

1. **`demo-state.json` is the only contract surface.** Per plan D-2, this skill writes exactly one artefact the runner consumes. No side-channel state, no runner-state mutation, no harness edits.
2. **Triage is a fixed rule table, not heuristic.** The classifier lives in `run-exit-demo-triage.md` and is reproduced verbatim from plan D-4 — the entrypoint never second-guesses a sub-skill verdict.
3. **One sub-agent dispatch per invocation.** The recover → dispatch → triage chain runs inside a single Opus 4.7 sub-agent (plan D-5). The entrypoint itself stays on the caller's session model and only consumes the resulting state file.
4. **Bounded retry budget.** At most `1 + retry_budget` dispatches. The default `retry_budget=1` is the canonical value; raising it shifts cost without typically buying determinism (cross-host flakes that survive one retry rarely resolve on a second).
5. **Run-logs are durable, not inlined.** Per R-10, `demo-state.json` references run-logs entries by path. Never inline PTY/stdout/reporter content into the state file or into the entrypoint's return value.
6. **The skill is markdown.** Per plan D-1 there is no new TypeScript, shell, or build glue. All behaviour is described in this file and the three sub-skills; the dispatched sub-agent reads them and executes.

---

## Outputs

Per invocation:

- `dev/<plan>/demo-state.json` — written by `run-exit-demo-triage` against `.agentic/templates/demo-state.schema.json`. The only file the runner reads.
- `dev/<plan>/runs/<timestamp>/` — run-logs archive directory created by the dispatch sub-skill. Contains harness stdout, the Playwright reporter copy at `playwright-results.json`, and per-class recovery transcripts. Referenced from `demo-state.json` by path. Gitignored at the consumer repo level (`dev/<plan>/runs/` belongs in the repo's `.gitignore`, not this skill's concern).
- Return value to the caller: a short structured summary of `{status, state_path, run_logs_path}`. The runner reads the state file itself; the return is for log clarity.

This skill writes nothing else. No edits to product code, the consumer plan, the harness, or `runner-state.json`.

---

## Workflow

### Step 1 — Validate args and prepare paths

1. Assert `plan`, `spec_glob`, `hosts_yaml` are present. If any is missing, exit with an error pointing at this file's `## Arguments` table.
2. Derive `state_path = dev/<plan>/demo-state.json` (unless an upstream caller, i.e. the runner, supplied an override).
3. Derive `run_logs_root = dev/<plan>/runs/`. The dispatch sub-skill creates `<run_logs_root>/<timestamp>-<short-sha>/` per invocation; the entrypoint just ensures the root exists.
4. Read `model` (default `opus`) and `retry_budget` (default `1`) for the dispatch step.

### Step 2 — Dispatch the orchestration sub-agent

Spawn one sub-agent via the `Agent` tool with:

- `subagent_type: general-purpose`
- `model: <model>` (default `opus`; plan D-5)
- A prompt that instructs the sub-agent to invoke the three sub-skills in order via the `Skill` tool. The recommended chain is:

  1. **`run-exit-demo-recover`** (preflight pass + known-class recovery). Args:
     - `plan=<plan>`
     - `hosts_yaml=<hosts_yaml>`
     - `run_logs_path=<run_logs_root>/<timestamp>` (the sub-agent generates the timestamp)
     - `requested_actions=[]` (empty on first pass; the sub-skill runs preflight and applies every matching D-4 rule it finds)

     Capture the returned `recovered[]` array.

  2. **`run-exit-demo-dispatch`** (run `make demo-e2e`, capture the D-9 last-line JSON summary and the Playwright reporter). Args:
     - `plan=<plan>`
     - `spec_glob=<spec_glob>`
     - `hosts_yaml=<hosts_yaml>`
     - `run_logs_root=<run_logs_root>`

     Capture the seven-key `dispatch_result` object the sub-skill returns.

  3. **`run-exit-demo-triage`** (classify per-spec outcomes against the D-4 rule table, write `demo-state.json`). Args:
     - `plan=<plan>`
     - `dispatch_result=<the object from step 2>`
     - `prior_recovered=<the recovered[] from step 1>`
     - `hosts_yaml=<hosts_yaml>`
     - `state_path=<state_path>` (only when the runner supplied a non-default)

     Capture the returned `status` and the path to the written state file.

### Step 3 — Retry rule (single retry, harness class takes precedence)

After triage's first pass:

- **If triage classified any failing spec as `harness` AND `retry_budget >= 1`**, re-invoke `run-exit-demo-recover` with `requested_actions[]` set to the harness rows triage flagged for retry, then re-invoke `run-exit-demo-dispatch` once more (same `spec_glob`, same `hosts_yaml`), then re-invoke `run-exit-demo-triage` with the new dispatch result and the merged `recovered[]`. `harness`-class retries take precedence over `unknown`-class retries (plan D-4 / triage workflow).
- **Else if triage classified the failing-spec set as `unknown`-only AND `retry_budget >= 1`**, re-invoke `run-exit-demo-dispatch` once with no further recovery (the retry is a flake-discrimination probe), then re-invoke `run-exit-demo-triage` on the new dispatch result.
- **Else**, accept the first-pass triage verdict.

The retry budget is **shared** across harness and unknown classes — at most one retry total per invocation when `retry_budget=1`. The dispatched sub-agent enforces this; the entrypoint does not need to count.

### Step 4 — Verify and return

After the sub-agent returns:

1. Confirm `state_path` exists.
2. Read `demo-state.json` and confirm it validates against `.agentic/templates/demo-state.schema.json`. The triage sub-skill is required to validate before writing; this is a belt-and-braces check.
3. Return `{status, state_path, run_logs_path}` to the caller. The runner reads `state_path` itself; the return is human-readable confirmation.

The entrypoint does not interpret `status` beyond passing it back. Bubble-up of `blocked` / `fail` to the human is the runner's responsibility (plan D-6, roadmap-runner.md §D.1a).

---

## Anti-patterns

- **Modifying product code (control plane, worker, browser app) for any reason.** This skill verifies a consumer plan's exit demo against the codebase as committed. If the demo fails because of a real product bug, triage classifies the failing spec as `real-bug` and the runner surfaces it — fixing the bug belongs in a fresh `/agentic-dev` cycle, not inside this skill. The same prohibition applies to the harness in `dev/demo-e2e/`: per plan D-1, this skill is markdown only.
- **Inlining `run_logs` archive contents into `demo-state.json` or any return value.** Per R-10 the PTY/stdout/reporter logs stay on disk; `demo-state.json` references them by path only. Inlining defeats the PTY-leakage guard and can silently push large outputs into runner state via the bubble-up path.
- **Mutating `dev/<roadmap>/runner-state.json`.** That file is owned by `/roadmap-runner`; `demo-state.json` is the only contract surface this skill writes. The runner reads our state file and updates its own — never the other way around.

---

## Out of Scope

Deliberately not built into this skill:

- **Single-host demo variants.** Per plan D-8, single-host execution is deferred to a follow-up plan that owns the necessary harness edits. The arg list intentionally does not expose a flag for it.
- **Editing the consumer plan, the harness, or `runner-state.json`.** Covered by the anti-patterns above; restated here for grep-friendliness.
- **Bubble-up to the human on failure.** The runner owns the human channel; this skill writes `demo-state.json` and exits.
- **Cross-plan state aggregation.** The skill is invoked once per plan-completion check; aggregating across plans is the runner's job.

---

## Handing off

This skill consumes a consumer plan slug and produces a `demo-state.json` at the documented path. Once the file exists and validates, the skill's job is done. Whether the runner advances, bubbles up a blocker, or aborts is downstream of this file's `status` — and is not something the entrypoint speaks to.
