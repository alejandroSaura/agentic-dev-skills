# Run Roadmap Review

Reusable sub-workflow for spawning and processing a single roadmap-review codex round. Invoked by `/adversarial-review-roadmap` once per round.

Analogous in shape to `.agentic/skills/run-plan-review.md` (which handles single-plan reviews) but operates on roadmap docs — index-of-plans documents whose review concerns are slicing, ordering, exit demos, spec coverage, and cross-plan coupling, not per-phase implementation detail.

## Inputs

- `feature_name`: review-session identifier (used for state paths). Conventionally the roadmap slug.
- `roadmap_path`: repo-root-relative path to the roadmap `.md` (typically `docs/roadmaps/<slug>.md`).
- `round`: round number (1-indexed).
- `prior_verdict`: `APPROVE_AS_IS | APPROVE_WITH_CHANGES | REVISE_AND_RESUBMIT | null`. Null iff round == 1.
- `prior_review_path`: path to the prior round's verdict JSON output file. Null iff round == 1.
- `prior_version` / `current_version`: roadmap version strings (e.g. `v3`, `v4`). Null/equal iff round == 1.
- `file_allowlist[]`: repo-root-relative paths the reviewer is allowed to read. Always includes the roadmap itself; should include the upstream spec (if any) and every existing child plan file.
- `spec_path`: optional repo-root-relative path to the upstream spec the roadmap was distilled from. `none` if absent.
- `writer_model`: recorded for the prompt only; this sub-workflow uses `codex` as reviewer.

## Prerequisites

- Roadmap file at `roadmap_path` exists and contains a changelog section if `round >= 2`.
- If `round >= 2`: prior review JSON exists at `prior_review_path`.
- Codex CLI is available on `PATH`.
- `.agentic/templates/roadmap-review-prompt.template.md` and `.agentic/templates/roadmap-review-verdict.schema.json` both exist.

## Procedure

### 1. Assemble the round-N prompt

Render the template `.agentic/templates/roadmap-review-prompt.template.md` into `docs/roadmaps/<roadmap-basename>.review-r<N>-prompt.md` by populating the placeholders:

**Stable-header placeholders (byte-identical across every round in the session):**
- `{{AGENTS_MD_INLINE}}` — inline the full contents of `.agentic/templates/AGENTS.md` verbatim.
- `{{FILE_ALLOWLIST}}` — render the allowlist as a bulleted list of repo-root-relative paths, one per line, terminated by the sentinel line `Files you must NOT read beyond this allowlist: everything else in the repository.`.
- `{{ROADMAP_TEXT_VERBATIM}}` — inline the full current roadmap `.md` body verbatim under a `### Roadmap text (under review)` subheading.

**Dynamic-suffix placeholders:**
- `{{FEATURE_NAME}}`, `{{ROUND_NUMBER}}`, `{{WRITER_MODEL}}`.
- `{{PRIOR_VERSION_OR_NONE}}` — `none` iff round 1, else the prior roadmap version string.
- `{{CURRENT_VERSION}}` — current roadmap version string.
- `{{SPEC_PATH_OR_NONE}}` — the upstream spec path, or `none` if the roadmap has no upstream spec. Round-N reviewers use this to decide whether `spec_coverage_audit` is required (non-null).
- `{{ROUND_1_INSTRUCTION_BLOCK}}` — if round == 1, populate with the sample Round-1 instruction text from the template; else empty string.
- `{{ROUND_N_INSTRUCTION_BLOCK}}` — if round >= 2, populate with the sample Round-N text, substituting `{{PRIOR_VERDICT}}`, `{{PRIOR_VERSION}}`, `{{CURRENT_VERSION}}`, `{{PRIOR_ROUND_NUMBER}}`; else empty string.
- `{{PRIOR_ROUND_FINDINGS_DIGEST}}` — present iff round >= 2. A pre-digested rendering of the prior round's `findings[]` + `cross_plan_coupling_audit[]` + `factual_corrections[]` (if any) as a compact bulleted list: `- [severity/dimension] <title> — <where>`. Do NOT embed the full prior review file.
- `{{AUTHOR_CHANGELOG_DIGEST}}` — present iff round >= 2. Extract the latest changelog entry from the roadmap (the `**Changelog v<prior> → v<current>**` section or equivalent). If the roadmap has no such section, the skill fails preflight rather than running the review.

Write the rendered prompt to `docs/roadmaps/<roadmap-basename>.review-r<N>-prompt.md`. Do not run codex if any placeholder is missing content.

### 2. Run codex

Byte-identical flag set across every round in the session:

```bash
codex exec --ephemeral \
  -s read-only \
  -c approval_policy="never" \
  --json \
  --output-schema .agentic/templates/roadmap-review-verdict.schema.json \
  --skip-git-repo-check \
  --cd <repo-root> \
  -o docs/roadmaps/<roadmap-basename>.review-r<N>.md \
  - < docs/roadmaps/<roadmap-basename>.review-r<N>-prompt.md \
  | tee docs/roadmaps/<roadmap-basename>.review-r<N>.progress.ndjson \
  > /dev/null 2>&1
```

Run in background via the `Bash` tool's `run_in_background: true` so the orchestrator can do non-overlapping work (state updates, preparing the next round's file allowlist). Wait for the completion notification; do not poll.

Flag drift between rounds invalidates codex's prefix cache. If the skill ever needs to change flags, document the change and accept that the session's cache is lost at that point.

### 3. Parse the structured verdict

Read `docs/roadmaps/<roadmap-basename>.review-r<N>.md`. Parse as JSON.

Extract:
- `verdict` (required)
- `summary` (required)
- `findings[]` (required; may be empty)
- `round_resolution_audit[]` (required iff round >= 2)
- `spec_coverage_audit` (null if no upstream spec; otherwise required — may be empty array)
- `cross_plan_coupling_audit[]` (required; may be empty array)
- `missed_risks[]` (required; may be empty array)

If parsing fails, record the failure in the review session's state and return to the orchestrator. Do not retry the round automatically — prompt drift is the usual cause and a retry with identical flags will fail the same way.

If `round >= 2` and `round_resolution_audit[]` is missing or empty, treat the review as a protocol failure and fail preflight on the next round. The reviewer must explicitly audit each prior finding; an absent audit is not the same as "all resolved".

### 4. Update review-session state

Append to `dev/<feature_name>/roadmap-review-state.json` under `rounds[]`:

```json
{
  "round": <N>,
  "prompt_path": "docs/roadmaps/<basename>.review-r<N>-prompt.md",
  "review_path": "docs/roadmaps/<basename>.review-r<N>.md",
  "progress_path": "docs/roadmaps/<basename>.review-r<N>.progress.ndjson",
  "verdict": "<APPROVE_AS_IS|APPROVE_WITH_CHANGES|REVISE_AND_RESUBMIT>",
  "finding_counts": { "critical": N, "important": N, "optional": N },
  "completed_at": "<ISO-8601 UTC>",
  "token_usage": { "input": N, "cached_input": N, "output": N }
}
```

Token usage is extracted from the `turn.completed` event in the `.progress.ndjson` stream (last such event in the file).

### 5. Return to orchestrator

Return the parsed verdict object (verdict + summary + findings + audits + missed_risks). The orchestrator decides whether to loop, approve, or hand back to the human based on:

- `verdict == APPROVE_AS_IS` → terminate successfully, hand to human for final approval.
- `verdict == APPROVE_WITH_CHANGES` → orchestrator applies surgical edits, bumps roadmap version, either continues to another round (if any critical-adjacent important findings) or terminates (if only optional).
- `verdict == REVISE_AND_RESUBMIT` → orchestrator applies surgical edits, bumps version, dispatches next round.
- Round cap reached → terminate with the last verdict, hand to human.

When applying surgical edits, the orchestrator routes by `dimension`:
- `slicing` → §4 Plans subsections (split / merge / re-scope plans).
- `ordering` → §4 `Depends on:` lines and the order of subsections.
- `exit_demo` → §4 `Exit demo:` lines (rewrite vague demos as binary observables).
- `spec_coverage` → §5 Coverage map (add missing rows, fix WRONG_PLAN attributions).
- `cross_plan_coupling` → §6 Cross-plan coupling.
- `risk_attribution` → §7 Risks.
- `scope_drift` → re-scope the offending plan in §4 and add/correct the §5 row.
- `status_convention` → §8.
- `factual` → wherever the factual claim lives.

## Anti-patterns

- **Embedding the prior review verbatim** in round-N prompts. The template explicitly digests prior findings into a compact bullet list; a verbatim embed wastes 1-3 KB per round and buys no reviewer signal.
- **Re-rendering the stable header** with any per-round variation. Any variation — even a trailing newline — invalidates codex's prefix cache. Round variation belongs in the suffix.
- **Reading files outside the allowlist** during prompt assembly. If the orchestrator needs to Grep a file not referenced by the roadmap to build the allowlist, that file is also off-limits to the reviewer.
- **Retrying a failed round** with the same flags/prompt. A failed parse means the prompt needs work, not a retry.
- **Treating per-plan implementation detail as roadmap concern.** If a finding boils down to "Phase 2 of Plan 5 should use approach X" — that's `/adversarial-review-plan`'s territory, not roadmap review. Such findings should be redirected ("the per-plan reviewer for Plan 5 will catch this") rather than burdened on the roadmap doc.
