# Run Exit Demo — Dispatch

Reusable sub-skill for `/run-exit-demo`. Invokes the consumer repo's
`make demo-e2e` target, captures the D-9 JSON summary from the harness
stdout, locates the Playwright JSON reporter artefact, and captures the
two staleness signals (`harness_head_sha`, `harness_worktree_dirty`)
defined by `plan-run-exit-demo.md §D-10`. Returns a structured object
the triage sub-skill consumes. The sub-skill is consumer-agnostic; the
caller supplies all paths.

## Arguments

- `plan` — consumer plan slug. Scopes the run-logs archive directory and
  appears in the return for the triage sub-skill's bookkeeping.
- `spec_glob` — Playwright spec glob the harness should run. Passed
  through to `make demo-e2e` via the environment variable the harness
  reads (the consumer repo's Makefile is the source of truth for which
  variable name; this sub-skill is glob-agnostic and treats it as
  opaque). Required.
- `hosts_yaml` — inventory path; passed through to `make demo-e2e` the
  same way as `spec_glob`. Required so the harness preflight has its
  inventory.
- `run_logs_root` — directory under which this sub-skill creates a
  per-invocation archive (e.g. `dev/<plan>/run-logs/<ISO-UTC>/`).

## Role

You are the harness invoker. You run exactly one `make demo-e2e`,
collect its artefacts deterministically, and hand them upward. You do
NOT classify failures, you do NOT apply recovery actions, you do NOT
write `demo-state.json`. Those belong to triage and recover. Your one
job is to record what happened with byte-accurate fidelity to the
harness's outputs.

## Workflow

1. **Capture staleness signals BEFORE invoking the harness (D-10).**
   From the consumer repo root, run:

   ```bash
   git rev-parse HEAD                       # → harness_head_sha
   test -z "$(git status --porcelain)"      # exit 0 → dirty=false
   ```

   Store `harness_head_sha` as the 40-char lowercase hex string. Store
   `harness_worktree_dirty` as a boolean (`true` iff `git status
   --porcelain` produced any output). These MUST be captured before
   `make demo-e2e` runs so a mid-run commit / uncommitted change cannot
   make the stored values inconsistent with what the harness actually
   saw.

2. **Create the run-logs archive directory.** Use
   `<run_logs_root>/run-<ISO-UTC>/` (e.g.
   `dev/durability/run-logs/run-2026-05-12T18-04-22Z/`). Note this
   path — it goes into the return as `run_logs_path` and the triage
   sub-skill's `auto_recovered[]` entries refer to subpaths of it by
   reference (R-10).

3. **Invoke `make demo-e2e`.** From the consumer repo root, run the
   target with `spec_glob` and `hosts_yaml` exposed via the environment
   variables the consumer Makefile expects. Tee stdout+stderr into
   `<run_logs_path>/make-demo-e2e.log`. Record the exit code as
   `exit_code` (do not abort the sub-skill on non-zero; the harness's
   D-9 summary is structured and we want it regardless of exit code).

4. **Parse the D-9 summary.** Read `<run_logs_path>/make-demo-e2e.log`
   and isolate the **last line** of the harness's stdout that parses as
   JSON. Per `plan-run-exit-demo.md §D-9` and
   `dev/demo-e2e/src/main.ts`, the harness emits its final summary as
   the very last line of stdout (status / failure / failure_detail /
   …). The parsed object is `summary`. If no parseable JSON line is
   present, that is itself a dispatch failure — record
   `summary: null` and continue; triage will treat a missing summary
   as a hard `status:"fail"` with no per-spec data.

5. **Reporter detection is ARTEFACT-BASED, not enum-based.** After
   `make demo-e2e` returns, check whether the file
   `dev/demo-e2e/test-results/results.json` exists on disk. The
   answer is what populates `playwright_reporter_path`. There are
   exactly three branches; do NOT decide based on the D-9 `failure`
   enum:

   - **(a) File exists.** Copy it into the run-logs archive as
     `<run_logs_path>/playwright-results.json` (so the by-reference
     path is durable even if the harness rewrites `test-results/` on
     the next invocation). Record
     `playwright_reporter_path = "<run_logs_path>/playwright-results.json"`
     and `reporter_missing_post_spawn = false`.

   - **(b) File does not exist AND** the parsed `summary` has
     `failure == "preflight"` AND `summary.failure_detail` contains
     the literal substring `hosts.yaml not found` (the stable string
     in `dev/demo-e2e/src/main.ts:170` — the only pre-spawn return
     path in the harness). Record
     `playwright_reporter_path = null` and
     `reporter_missing_post_spawn = false`. This is the documented
     pre-Playwright failure; nothing to diagnose at the reporter
     level.

   - **(c) File does not exist AND** any other failure path. This is
     unexpected — Playwright was spawned (`globalSetup` ran) but the
     reporter artefact is missing. Record
     `playwright_reporter_path = null` and
     `reporter_missing_post_spawn = true`. The triage sub-skill will
     add a `class: "missing-reporter-diagnostic"` entry to
     `auto_recovered[]` so the human sees the run was degraded; D-4
     summary-level harness rules remain applicable on the retry.

   The `reporter_missing_post_spawn` flag's only consumer is the
   triage sub-skill. Branches (b) and (c) BOTH set
   `playwright_reporter_path = null`; the flag is what
   distinguishes "expected null" from "anomalous null".

6. **Return.** Hand the call site exactly the seven-key object shown
   in the output contract. Do not add fields. Do not omit fields.

## Output contract

The sub-skill returns exactly this shape (seven keys, no more, no
less). Triage assumes this shape literally — adding or removing keys
breaks the contract.

```jsonc
{
  "summary": { /* D-9 JSON object from the last line of make demo-e2e stdout */ }
             // or null if no parseable JSON line was emitted.
  ,
  "exit_code": 0 | <int>,                // raw exit status of `make demo-e2e`
  "run_logs_path": "<absolute or repo-relative path to the archive dir>",
  "playwright_reporter_path": "<path to copied reporter>" | null,
  "reporter_missing_post_spawn": true | false,
  "harness_head_sha": "<40-char lowercase hex from git rev-parse HEAD>",
  "harness_worktree_dirty": true | false
}
```

Notes on each key:

- `summary` is verbatim from the harness — it MUST NOT be re-keyed,
  normalised, or trimmed. The triage sub-skill reads `summary.failure`,
  `summary.failure_detail`, and similar fields by name.
- `run_logs_path` is the directory created in step 2. Every other
  by-reference path the triage sub-skill or `auto_recovered[]` entries
  cite resolves against this directory.
- `playwright_reporter_path` is the COPY at `<run_logs_path>/playwright-results.json`
  when the file existed, not the original `dev/demo-e2e/test-results/results.json`
  path. The copy is what survives subsequent runs and is what
  `demo-state.json.playwright_reporter_path` ultimately points to.
- `harness_head_sha` and `harness_worktree_dirty` flow straight into
  the matching top-level fields of `demo-state.json` (see §D-7 of the
  plan and the Phase 1 schema at
  `.agentic/templates/demo-state.schema.json`).

## Anti-patterns

- **Inferring reporter presence from the D-9 enum.** Round-3 review
  rejected this; the `failure` enum spans phases owned by Playwright's
  `globalSetup`, which DO produce the reporter. Always stat the file.
- **Treating non-zero exit as a fast-fail.** The harness emits the D-9
  summary on every code path. Capture the summary first, exit-code
  second; triage decides what the combination means.
- **Inlining reporter contents into the return.** The reporter can
  carry trace excerpts that R-10 forbids being inlined into
  `demo-state.json`. Always pass paths.
- **Re-running `git rev-parse` after the harness completes.** The
  staleness snapshot must reflect the tree the harness saw, not the
  tree after the harness possibly ran a sub-process that committed (it
  shouldn't, but the discipline matters).
- **Allowing the sub-skill to classify failures.** Classification is
  triage's job. Dispatch records artefacts and returns; it never
  decides whether a `failure:"wait_registered"` is `harness` or
  `real-bug`.
