# Run Review

Reusable sub-workflow for spawning and processing a review agent.

## Review prompt assembly

The orchestrator does NOT hand-write review prompts. Review prompts are
produced by the project-scoped `/review-feature-phase` skill
(`.claude/commands/review-feature-phase.md`), which emits the canonical
layout defined in `.agentic/templates/review-prompt.template.md`:

- A **stable header** (byte-identical across every review round in a
  session) containing project rules, the review rubric, the self-audit
  gate reference, and the D-9 flat-branch-naming / D-10 shared-artifact
  acknowledgments.
- A **phase-specific** suffix filled in per invocation from the
  orchestrator-supplied parameters (`phase_id`, `commits`,
  `specific_checks[]`, `deferred_findings[]`, and the diff-embedding
  decision — verbatim if the diff is ≤ 8 KB, commit-range + file
  allowlist otherwise).

This sub-workflow assumes the orchestrator has already invoked
`/review-feature-phase` and persisted the rendered prompt to
`dev/<feature-name>/reviews/phase-<N>-review-prompt[-rN].md`. The steps
below cover what happens after that file is written: spawning the agent,
processing the verdict, verifying the self-audit, and updating state.

If you find yourself assembling a review prompt by hand in the
orchestrator session, stop and delegate to `/review-feature-phase`
instead — hand-written prompts drift from the canonical template, which
breaks the prompt-cache byte identity (Claude side) and the
`--output-schema` / flag-identity contract (codex side).

## Inputs

- `feature_name`: feature identifier
- `phase_id`: phase being reviewed
- `review_model`: model to use for review (opus, sonnet, codex)
- `run_id`: current run identifier
- `plan_phase_content`: phase scope and acceptance criteria from the plan
- `verification_results`: output from run-verification (automated gates must all pass before review)

## Prerequisites

- All required automated verification gates must have passed
- If any gate failed, do NOT proceed — return to orchestrator for fix cycle

## Procedure

### 1. Prepare review prompt

The review prompt is produced by the `/review-feature-phase` skill (see
§"Review prompt assembly" above), not hand-assembled here. The skill
takes the orchestrator-supplied parameters and renders the canonical
template (`.agentic/templates/review-prompt.template.md`) into
`dev/<feature-name>/reviews/phase-<N>-review-prompt[-rN].md`.

Parameters the orchestrator passes to the skill:
- `phase_id`
- `commits` (base..head refs)
- `specific_checks[]` — drawn from the phase's acceptance criteria in the
  plan, plus any still-open items from prior rounds
- `deferred_findings[]` (optional, present when prior rounds deferred
  findings instead of resolving them)
- Verification gate results (so the reviewer knows what already passed)

The skill handles the 8 KB diff-embedding threshold, the file allowlist,
and the structured-verdict format. If the skill output is missing any
required section, treat that as a precondition failure and do not spawn
the review agent.

### 2. Spawn review agent

Using the configured `review_model`:
- If Claude model: use Agent tool with `model` parameter
- If codex: use Codex CLI in read-only mode

### 3. Process review result

Parse the review output for:
- Result: PASS or FAIL
- Findings (if FAIL): categorized by severity
- Any recommendations (even on PASS)

### 3a. Verify self-audit

This is the **verify self-audit** gate. The review agent MUST inspect the
impl agent's handoff for the mandatory `## Stale artifact self-audit`
section (contract defined in `.agentic/templates/impl-prompt.template.md`).
This gate runs in addition to the normal scope/correctness review; its
purpose is to verify the self-audit claims, not to re-run them end-to-end.

Procedure:

1. **Confirm presence.** Locate the `## Stale artifact self-audit` heading in
   the handoff. If the section is missing, the review is an automatic FAIL
   (blocker-level finding: "handoff missing mandatory self-audit section").
   Do not proceed to step 2.
2. **Cross-check at least one claim.** Pick one bullet from the self-audit
   (or the "None found after diff-grep sweep" claim if the agent reported no
   findings) and re-run the grep the agent claims to have run. For a
   non-empty bullet, spot-check that at least one listed entry still exists
   at the stated file/line and that the characterization is accurate. For a
   "None found" claim, pick one renamed/deleted symbol from the phase's diff
   and grep the working tree for it.
3. **Flag discrepancies.** If the cross-check grep returns a match the agent
   did not list, record a finding (severity: important, or critical if the
   match is in shipped user-facing docs or load-bearing comments). If the
   agent reported "None found" but the reviewer's grep surfaces a plausible
   stale artifact (comment referencing a renamed symbol, test asserting on
   removed behavior, doc still describing the old contract), that is an
   automatic REVIEW FAIL — the null claim is false.

Record the self-audit verification outcome in the review log (see step 4)
under a dedicated `## Self-audit verification` subsection: which claim was
cross-checked, the grep command used, and the result (consistent /
discrepancy / null-claim-falsified).

### 4. Write review log

Append to `dev/<feature_name>/reviews/review-phase-<N>.md`:

```md
## Round <N>
- Run ID: <run_id>
- Result: PASS / FAIL
- Verification gates: all passed
- Critical issues: <list or none>
- Important issues: <list or none>
- Optional issues: <list or none>
- Required next action: <merge / fix specific findings>
```

### 5. Update state.json

- Update `verification.last_results.review` to pass/fail
- Increment `current_phase.review_round`
- Update `next_action` accordingly

### 6. Budget check

Check against `budgets.max_review_rounds_per_phase`. If exceeded:
- Set blocker: `blocked_needs_human_decision`
- Update `next_action` to escalation
- Inform orchestrator

## Output

- Review result: PASS or FAIL
- Review log updated
- state.json updated
- If FAIL: structured findings for fix agent
