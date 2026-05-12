# Run Exit Demo — Triage

Reusable sub-skill for `/run-exit-demo`. Consumes the dispatch return
value (from `run-exit-demo-dispatch.md`) plus `prior_recovered` (from
`run-exit-demo-recover.md`), classifies every failing spec against the
D-4 rule table, optionally requests one combined retry, and writes the
final `dev/<plan>/demo-state.json` validated against the Phase 1 schema
at `.agentic/templates/demo-state.schema.json`. The retry budget owner is
this sub-skill — never the entrypoint, never dispatch.

## Arguments

- `plan` — consumer plan slug. Determines the output path
  (`dev/<plan>/demo-state.json`) and the `plan` field in the written
  state.
- `dispatch_result` — the seven-key object returned by
  `run-exit-demo-dispatch.md`:
  `{summary, exit_code, run_logs_path, playwright_reporter_path,
   reporter_missing_post_spawn, harness_head_sha, harness_worktree_dirty}`.
  Treat the shape as a contract — read fields by name.
- `prior_recovered` — the `recovered[]` array returned by
  `run-exit-demo-recover.md` on the initial preflight pass. May be `[]`
  if recover applied no actions.
- `hosts_yaml` — pass-through for the retry, in case the harness retry
  needs to be re-dispatched after a recovery action.
- `state_path` — optional override for the final write target. Default
  is `dev/<plan>/demo-state.json`.

## Role

You are the decision-maker. Every spec result, every failure phase,
every recovery outcome lands in your hands and you decide:

1. What category each failing spec gets (`harness | real-bug | unknown`).
2. Whether the one-shot combined retry budget fires, and if so, whether
   it goes through `run-exit-demo-recover` first (harness path) or
   re-dispatches directly via `run-exit-demo-dispatch` (unknown path).
3. What top-level `status` the final `demo-state.json` carries
   (`pass | blocked | fail`).
4. Whether a `blocker` object is needed (real-bug entries → yes;
   pure-harness or unknown-flaky failures → no, `blocker: null`).

You do not run `make` commands directly. You hand action requests to
`run-exit-demo-recover` (with `requested_actions[]`) and re-dispatches
to `run-exit-demo-dispatch`. The rule table from D-4 is authoritative;
your job is to apply it, not extend it.

## Workflow

### 1. Branch selection — which reporter case are we in?

The dispatch return value uniquely identifies one of three branches per
D-9. Read the two flags exactly as defined:

- **Reporter present** —
  `dispatch_result.playwright_reporter_path != null`.
- **Reporter absent, missing-inventory preflight** —
  `dispatch_result.playwright_reporter_path == null` AND
  `dispatch_result.reporter_missing_post_spawn == false`.
- **Reporter absent, post-spawn artefact loss** —
  `dispatch_result.playwright_reporter_path == null` AND
  `dispatch_result.reporter_missing_post_spawn == true`.

### 2a. Branch — reporter present

1. Read the JSON at `dispatch_result.playwright_reporter_path`. Enumerate
   every spec via `suites[].specs[]` recursively (the reporter nests
   suites). For each spec, the spec identifier is the test title (per
   `plan-run-exit-demo.md §D-7`).

2. For each spec:
   - If the spec passed, append the title to `passed_specs[]`.
   - If the spec failed, build a `failing_specs[]` entry:
     - `spec_id` = the test title.
     - `reporter_error` = the first 256 characters of the reporter's
       per-spec `error.message` (or equivalent), or `null` if absent.
       This is by-reference only — full traces stay in
       `dispatch_result.run_logs_path`.
     - `category` = apply the D-4 rule table against
       `dispatch_result.summary.failure`,
       `dispatch_result.summary.failure_detail`, and the reporter
       error excerpt. See `run-exit-demo-recover.md` for the exact
       rules. The set of D-4 `harness` rows is:
       - `preflight` + `known_hosts` mismatch + fingerprint gate passes
         (otherwise → `unknown`).
       - `preflight` + missing remote workdir = inventory `remote_dir`.
       - `local_bringup` + `stack not up`.
       - `wait_registered` + zero CP log lines.
       - `distribute` + spawn-cwd fingerprint.
       Everything else → `unknown`.
     - `diagnosis` = short imperative description of why the category
       was chosen. For `real-bug` (only assigned on retry promotion —
       see step 2a.4 below), the dispatched Opus 4.7 sub-agent is
       allowed to enrich this with free-form diagnostic prose.

3. **Retry decision.** Examine `failing_specs[]`:
   - If any entry has `category == "harness"`, this is the **harness
     retry path**. Build a `requested_actions[]` list from those
     entries, call `run-exit-demo-recover` with `requested_actions`
     populated and the same `hosts_yaml`, then call
     `run-exit-demo-dispatch` once. Promote per step 2a.4. The
     `harness` retry path TAKES PRECEDENCE over the unknown retry
     path — if both `harness` and `unknown` entries exist on the
     first pass, run the harness retry and re-evaluate `unknown`
     entries against the SAME retry result (no separate budget).
   - Else if any entry has `category == "unknown"`, this is the
     **unknown retry path**. Skip `run-exit-demo-recover` entirely
     and call `run-exit-demo-dispatch` once with no recovery
     applied. Promote per step 2a.4.
   - Else (all `failing_specs[]` empty, or non-existent), no retry.

   The retry budget is ONE combined dispatch — i.e. at most TWO total
   dispatches per `/run-exit-demo` invocation. Never exceed this.

4. **Promotion rules on retry (D-4).** Examine the retry's
   reporter for each spec that was re-attempted:

   - **`harness` retry promotions** (per spec that was in the harness
     class on the first pass):
     - Pass on retry → move the title to `passed_specs[]`. Append an
       `auto_recovered[]` entry with `outcome: "applied"` if the
       recover sub-skill returned `applied`, else `"already-applied"`.
     - Fail on retry with the **same** `dispatch_result.summary.failure`
       phase → promote `category` to `real-bug`. The recovery was the
       wrong call; the underlying failure is real.
     - Fail on retry with a **different** failure phase → keep
       `category: "harness"` but set the matching `auto_recovered[]`
       entry's `outcome: "no-op"` and write top-level `status: "fail"`
       (recovery did not help; needs human investigation).

   - **`unknown` retry promotions** (per spec that was in the unknown
     class on the first pass — applies whether retry was the harness
     path or the unknown path):
     - Same `spec_id` + same `dispatch_result.summary.failure` phase
       + same normalised `reporter_error` (first 256 chars compared
       byte-for-byte after whitespace collapse) → promote to
       `real-bug`. Two-of-two identical means the failure is
       reproducible and the human gets a confirmed bug.
     - Anything less identical (different error, different failure
       phase, or pass on retry) → record `category: "unknown-flaky"`
       and write top-level `status: "fail"`. Flaky failures are NOT
       blockers; presenting a non-deterministic failure to the human
       as a confirmed bug is worse than reporting it as flaky.

### 2b. Branch — reporter absent, missing-inventory preflight

This is the documented pre-spawn null path
(`dev/demo-e2e/src/main.ts:163`). The harness returned before
Playwright was even spawned; per-spec data is not knowable.

1. Set `passed_specs = []` and `failing_specs = []`.
2. Set `status = "fail"` driven by `dispatch_result.summary` (failure
   phase + detail). Do NOT attempt per-spec triage.
3. Do not apply D-4. Do not retry — there are no specs to retry
   against, and the inventory absence is a human-input problem
   (`hosts.yaml` does not exist), not a recoverable harness state.
4. `blocker = null` — a missing inventory is `fail`, not `blocked`.

### 2c. Branch — reporter absent, post-spawn artefact loss

Playwright was spawned but the reporter artefact is missing. The
contract still requires the skill to attempt D-4 recovery at the
summary level so harness classes like `local_bringup` /
`wait_registered` / `distribute` remain reachable.

1. Set `passed_specs = []` and `failing_specs = []`.
2. Append a diagnostic entry to `auto_recovered[]`:
   ```jsonc
   {
     "class": "missing-reporter-diagnostic",
     "action": "<short description of the anomaly, e.g. 'playwright completed but results.json absent'>",
     "outcome": "no-op"
   }
   ```
3. Apply the D-4 rule table against `dispatch_result.summary` at the
   summary level. The `harness` rows that match `failure:"local_bringup"`,
   `failure:"wait_registered"`, `failure:"distribute"` still fire here —
   ask `run-exit-demo-recover` to apply the action (if any), then
   re-invoke `run-exit-demo-dispatch` once. Apply the harness-retry
   promotion rules at the **summary level**: success → set
   `status: "pass"` (and the original anomaly's `outcome` stays
   `"no-op"`; recovery did fix the run); failure on retry → write
   `status: "fail"`.
4. If no D-4 row matches at the summary level, write `status: "fail"`.
   Future work may add `real-bug` summary rules; today there are none.

### 3. Compose `auto_recovered[]`

The final array merges:
- `prior_recovered` from the initial recover pass (the argument).
- Any retry-recovery entries returned by `run-exit-demo-recover` on the
  retry pass.
- The diagnostic entry added in branch 2c.

For `class: "known_hosts"` rows, preserve the
`fingerprint_before_path` and `fingerprint_after_path` references
exactly as `run-exit-demo-recover` provided them — DO NOT inline the
fingerprint values.

### 4. Determine top-level `status`

- `passed_specs.length > 0` AND `failing_specs.length == 0` AND no
  branch-2b/2c failure → `status: "pass"`.
- Any `failing_specs[].category == "real-bug"` → `status: "blocked"`.
  Build the `blocker` object:
  ```jsonc
  {
    "summary": "<one-line description of the failing real-bug specs>",
    "evidence_paths": [
      "<dispatch_result.playwright_reporter_path>",
      "<dispatch_result.run_logs_path>",
      ...any auto_recovered[*].fingerprint_*_path entries
    ]
  }
  ```
- Otherwise → `status: "fail"`, `blocker: null`. This includes:
  - All `failing_specs[]` entries are `harness` with `outcome:"no-op"`.
  - All `failing_specs[]` entries are `unknown` or `unknown-flaky`.
  - Branch 2b (missing-inventory preflight).
  - Branch 2c with no D-4 match.

### 5. Write `demo-state.json` and validate

Compose the final object matching `.agentic/templates/demo-state.schema.json`:

```jsonc
{
  "status": "pass" | "blocked" | "fail",
  "plan": "<plan slug>",
  "ran_at": "<ISO-8601 UTC at dispatch time>",
  "harness_head_sha": "<dispatch_result.harness_head_sha>",
  "harness_worktree_dirty": <dispatch_result.harness_worktree_dirty>,
  "json_summary": <dispatch_result.summary, verbatim>,
  "playwright_reporter_path": "<dispatch_result.playwright_reporter_path>" | null,
  "passed_specs": [...],
  "failing_specs": [...],
  "auto_recovered": [...],
  "blocker": {...} | null
}
```

Validate the object against `.agentic/templates/demo-state.schema.json`
BEFORE writing. The schema has `additionalProperties: false` at every
level except `json_summary` — drop or rename any extra keys before
write. If validation fails, treat that as a hard skill error: do NOT
write a partial state file. Write a stderr diagnostic and return
non-zero so the entrypoint can surface the schema mismatch to the
human.

On successful validation, write the file atomically to `state_path`
(default `dev/<plan>/demo-state.json`): write to a sibling temp file,
fsync, rename.

## Output contract

Return to the entrypoint a single object describing the outcome:

```jsonc
{
  "state_path": "dev/<plan>/demo-state.json",
  "status": "pass" | "blocked" | "fail",
  "retries_used": 0 | 1,
  "validated_against_schema": true
}
```

The `validated_against_schema` flag is always `true` on a successful
return — if the schema check failed, the sub-skill never reached this
return; it errored out before writing the file.

The runner integration (see Phase 4 of `plan-run-exit-demo.md` and
`roadmap-runner.md` §D) reads `dev/<plan>/demo-state.json` directly via
`Read`; the four-key return above is for the entrypoint's
human-readable summary, not for cross-skill consumption.

## Cross-skill references

This sub-skill orchestrates exactly two other sub-skills:

- `run-exit-demo-dispatch` — the harness invoker. Called once on the
  retry path (the first dispatch happens before triage is invoked, by
  the entrypoint).
- `run-exit-demo-recover` — the action applier. Called via
  `requested_actions[]` on the harness-retry path to apply specific
  recovery actions matched from the D-4 rule table.

The cross-references are exact filename references (sans `.md`); the
entrypoint resolves them against `.agentic/skills/`.

## Anti-patterns

- **Spending more than one retry.** The budget is ONE combined dispatch
  (≤2 total). The `harness` retry path consumes that budget; the
  `unknown` retry path consumes that budget; they DO NOT both run.
- **Letting `unknown` retry pre-empt `harness` retry.** Round-2 of the
  plan review explicitly settled this: when both classes are present,
  the `harness` retry runs and the `unknown` entries are re-evaluated
  against the same retry's reporter without consuming a further
  budget.
- **Writing `demo-state.json` without schema validation.** The runner
  trusts the schema contract. An invalid state file silently breaks
  downstream consumers; fail loudly instead.
- **Inlining the Playwright reporter contents into `json_summary` or
  `failing_specs[].reporter_error`.** The reporter is referenced by
  path. The 256-char excerpt for `reporter_error` is the only place
  reporter text appears verbatim, and it is bounded for a reason.
- **Treating `unknown-flaky` as `blocked`.** Non-deterministic
  failures are `fail` with `blocker: null`. A flaky failure is not a
  confirmed bug and presenting one to the human as such would erode
  trust in the skill's verdicts.
- **Re-running recover or dispatch when the schema validation fails.**
  Validation failure means the triage logic produced a malformed
  object; the fix is in this sub-skill, not in re-executing the
  harness. Surface the error and stop.
