# Run Exit Demo — Recover

Reusable sub-skill for `/run-exit-demo`. Runs the harness preflight, applies
the **fixed set** of known-class recovery actions enumerated in
`plan-run-exit-demo.md §D-4`, and returns a structured `recovered[]` array
to the caller (the top-level `/run-exit-demo` entrypoint or
`run-exit-demo-triage.md` when a `harness`-classified retry asks for a
specific action). The sub-skill is consumer-agnostic: all paths are taken
from the args; nothing about a particular project is hard-coded.

## Arguments

- `plan` — the consumer plan slug (e.g. `durability`). Used only to scope
  the per-run logs archive directory; no business logic depends on it.
- `hosts_yaml` — repo-root-relative path to the inventory file the harness
  reads (typically `dev/demo-e2e/hosts.yaml`). The sub-skill loads this file
  to look up each host's `expected_host_key_fingerprint`.
- `run_logs_path` — path to the run-logs archive directory the dispatch
  sub-skill (or top-level caller) created for this invocation. Recovery
  artefacts (host-key fingerprint captures, mkdir transcripts, …) are
  written here by reference, not inlined into the return value.
- `requested_actions[]` — optional. When the caller is
  `run-exit-demo-triage.md` re-asking for a specific recovery on a retry,
  this is a list of `{class, host}` tuples to apply directly (skipping the
  preflight scan). When absent or empty, the sub-skill runs preflight and
  applies every matching D-4 rule.

## Role

You are a deterministic harness-recovery agent. You only touch the local
machine and the SSH client state of the operator's account. You DO NOT
edit the harness source, the consumer plan, or the runner state. Your
classifications must match the D-4 rule table byte-for-byte: a failure
class either matches a row exactly and you apply that row's action, or it
does not and you return it as `unknown` with no action. No heuristics. No
"close enough".

## Workflow

1. **Load inventory.** Read the YAML file at `hosts_yaml`. For each host
   record, retain `name`, `address`, `user`, `remote_dir`, and
   `expected_host_key_fingerprint` (the last one is OPTIONAL in the file
   schema; absence MUST be treated as "fingerprint gate fails" — never
   substitute a default).

2. **Run preflight (unless `requested_actions[]` was supplied).** Invoke
   `make demo-e2e-preflight` from the consumer repo root. Capture stdout
   and parse the last line as JSON — this matches the D-9 contract that
   `dev/demo-e2e/src/main.ts` uses for the full run. The parsed object
   carries `status`, `failure`, `failure_detail`, and an optional
   `failure_host` field naming the affected inventory host.

3. **Match each preflight failure against the D-4 rule table.** The
   table below is the complete list of classes you may recover; anything
   not listed is returned as `unknown` with no action.

   | D-9 `failure` | Detail predicate | Class | Action |
   |---|---|---|---|
   | `preflight` | `failure_detail` indicates a `known_hosts` mismatch for `failure_host` | `harness` (gated, see step 4) | Remove the offending line in `~/.ssh/known_hosts` for `failure_host` |
   | `preflight` | `failure_detail` indicates a missing remote workdir AND the path equals the inventory `remote_dir` for `failure_host` | `harness` | `ssh <user>@<address> "mkdir -p <remote_dir>"` |
   | `local_bringup` | `failure_detail` matches `stack not up` | `harness` | `make demo` and wait for the healthcheck to pass |
   | `wait_registered` | CP stdout has zero log lines (matches the fingerprint fixed on `main` in commit 819d549) | `harness` | No-op; record as `already-applied` — the fix is upstream |
   | `distribute` | matches the spawn-cwd error fingerprint fixed on `main` in commit 819d549 | `harness` | No-op; record as `already-applied` |
   | anything else | — | `unknown` | none |

4. **`known_hosts` fingerprint gate (MANDATORY).** Before removing any
   `known_hosts` entry, you MUST verify the new host key matches the
   inventory's expected value. This gate is the entire reason the
   recovery is safe to automate — skipping it would defeat SSH's
   host-identity warning. Steps:

   a. Look up `expected_host_key_fingerprint` for `failure_host` in the
      loaded inventory. If absent, ABORT this recovery: record the
      failure in `recovered[]` as class `known_hosts`, `outcome: "no-op"`,
      `action: "expected_host_key_fingerprint missing in hosts.yaml"`,
      and return the failure to the caller as `unknown` (no
      `known_hosts` line is removed).

   b. Capture the current advertised host key fingerprint:

      ```bash
      ssh-keyscan -t ed25519,rsa <address> 2>/dev/null \
        | ssh-keygen -lf -
      ```

      Write the raw output to
      `<run_logs_path>/known-hosts/<host>-before.txt`. Note this path —
      it goes into the return as `fingerprint_before_path`.

   c. Compare the captured fingerprint to
      `expected_host_key_fingerprint` using the SHA256 line that
      `ssh-keygen -lf` produces. Equality is exact-string on the
      `SHA256:…` token.

   d. **On mismatch:** ABORT this recovery. Record in `recovered[]` with
      class `known_hosts`, `outcome: "no-op"`, `action: "fingerprint
      mismatch — refused to edit known_hosts"`, and return the failure
      to the caller as `unknown`. The plan deliberately routes this to
      the human via the unknown-retry promotion rule rather than blind-
      deleting a possibly-malicious host's key.

   e. **On match:** edit `~/.ssh/known_hosts` to remove the offending
      line for `failure_host` (use `ssh-keygen -R <address>` — it
      performs the in-place removal with a `.old` backup). Re-run
      `ssh-keyscan` against the host to confirm the new state, write
      the result to `<run_logs_path>/known-hosts/<host>-after.txt`,
      and record both paths as
      `fingerprint_before_path` / `fingerprint_after_path` in the
      `recovered[]` entry.

5. **Apply each non-`known_hosts` matching action.** For each row that
   fires, run the command, capture stdout+stderr to
   `<run_logs_path>/<class>/<host>.log`, and add an entry to
   `recovered[]` with the appropriate `outcome`:
   - `applied` — the action was executed and returned 0.
   - `already-applied` — the row's "already fixed on main" rows
     (`wait_registered` and `distribute` fingerprints). The skill does
     not re-apply anything; it records the historical fact so the
     human can see why no action was needed.
   - `no-op` — the action was attempted but did not change observable
     state (e.g., `mkdir -p` on a path that already exists). Triage
     uses this to decide whether to promote the spec to `real-bug`.

6. **Compile the return object.** Sort `recovered[]` by application
   order (first match first). For unmatched failures, the caller (the
   entrypoint or triage) will see the absence of a matching `recovered[]`
   entry and is responsible for the `unknown` classification.

## Output contract

Return a single object to the caller:

```jsonc
{
  "recovered": [
    {
      "class": "known_hosts" | "missing_remote_workdir" | "local_bringup"
             | "wait_registered" | "distribute",
      "host": "<host name from inventory>" | null,
      "action": "<short imperative string>",
      "outcome": "applied" | "already-applied" | "no-op",

      // PRESENT iff class == "known_hosts" — these are paths inside
      // <run_logs_path> capturing the host-key fingerprint before and
      // after the recovery. NEVER inline the fingerprint values into
      // the return; the run-logs archive is the authority (R-10 in
      // plan-run-exit-demo.md).
      "fingerprint_before_path": "<run_logs_path>/known-hosts/<host>-before.txt" | null,
      "fingerprint_after_path":  "<run_logs_path>/known-hosts/<host>-after.txt"  | null
    }
  ]
}
```

The `expected_host_key_fingerprint` value itself is NEVER part of the
return — it is the inventory's secret-shape contract with the operator,
and the skill quotes it only inside the fingerprint comparison. Both
`fingerprint_before_path` and `fingerprint_after_path` keys exist on
every `known_hosts` row (`null` only when the gate aborted before
running `ssh-keyscan`, e.g. inventory absence).

## Anti-patterns

- **Editing `known_hosts` without the fingerprint gate.** Round-1 review
  of the plan explicitly rejected the blind-delete behaviour. Removing a
  warning the SSH client emits about an identity change is not a
  recovery — it is the operator silently accepting an impersonator.
  Without an inventory-declared `expected_host_key_fingerprint` and a
  match, the recovery aborts and the failure flows to the human.
- **Heuristic class matching.** If `failure_detail` does not match a
  rule row's predicate verbatim, return the failure as `unknown`. The
  rule table is the single source of truth; "this looks like a
  `known_hosts` mismatch" is not a match.
- **Inlining captured fingerprints into the return value.** Paths only.
  The run-logs archive is the durable record; the return shape is for
  the triage sub-skill's decision-making, not the human's audit trail.
- **Mutating the harness or the consumer plan.** This sub-skill only
  touches local SSH state (`~/.ssh/known_hosts`), remote directories
  via `ssh <host> mkdir -p`, and the `make demo` stack. It never edits
  files inside `dev/demo-e2e/`, the consumer plan markdown, or the
  runner state file.
