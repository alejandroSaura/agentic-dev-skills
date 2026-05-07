# /review-feature-phase

Generates a canonical codex review prompt for an agentic-dev workflow phase. Project-scoped per D-1.

---

## Skill asset lookup (global installation)

This skill ships in two locations: project-local (`<repo-root>/.claude/commands/` + `<repo-root>/.agentic/`) and user-global (`~/.claude/commands/` + `~/.agentic/`).

When this file references `.agentic/templates/<X>` or `.agentic/skills/<X>`, resolve in this order:
1. `<cwd>/.agentic/<X>` — project-local override (preferred when present).
2. `~/.agentic/<X>` — user-global fallback.

Output paths (`dev/<feature-name>/...`) are always relative to `<cwd>`.

---

## Arguments

- `phase_id=<string>` (required): e.g. `phase-3`, `phase-5b`.
- `commits=<sha[,sha]...>` (required): commit(s) under review on the phase branch.
- `specific_checks=<json-array>` (optional): additional phase-specific checks the reviewer should perform. Default: `[]`.
- `deferred_findings=<json-array>` (optional): items the phase brief intentionally flagged as out-of-scope; reviewer must acknowledge but not block on them. Default: `[]`.

---

## Role

You are the `review-feature-phase` skill. You don't run the review yourself — you assemble the review prompt that the orchestrator passes to codex via `codex exec`.

---

## Output contract

Produce a review prompt file at `dev/<feature-name>/reviews/<phase-id>-review-prompt.md` with TWO sections:

### `## Stable header` (byte-identical across reviews in a session)

Per `.agentic/templates/review-prompt.template.md`. Contains:
- Project rules (AGENTS.md inlined verbatim)
- Review rubric — the reviewer's final message MUST be a **single JSON object** conforming to `.agentic/templates/review-verdict.schema.json` (enforced by codex `--output-schema`). Markdown prose `VERDICT: PASS` / `VERDICT: FAIL` text is NO LONGER the rubric; the structured `verdict` field is authoritative.
- Reference to `.agentic/skills/run-review.md §"Verify self-audit"` gate (MANDATORY — reviewer must verify the impl agent's self-audit section AND populate `self_audit_verification` in the JSON)
- D-9 flat branch naming rule acknowledgment (no hierarchical `feature/<name>/phase-<N>` references)

### `## Phase-specific section` (dynamic suffix)

Filled from the parameters:
- Phase ID + commit SHAs
- Files to read (allowlist derived from `git diff --name-only <base>..<head>`)
- **Diff embedding decision**: if `git diff --no-color --no-ext-diff <base>..<head> | wc -c` ≤ **8192** bytes (8 KB), embed the diff verbatim in the prompt. Otherwise, provide commit-range summary (`git log --stat`) + explicit file allowlist; reviewer will `Read` files as needed.
- `specific_checks[]` enumerated as bullet-list
- `deferred_findings[]` enumerated with "acknowledge but don't block" annotation
- Expected verdict format reminder

---

## Codex invocation flags (MUST be byte-identical across rounds)

The orchestrator calls:

```bash
codex exec --ephemeral \
  -s read-only \
  -c approval_policy="never" \
  --json \
  --output-schema .agentic/templates/review-verdict.schema.json \
  -o dev/<feature-name>/reviews/<phase-id>-review[-rN].md \
  < dev/<feature-name>/reviews/<phase-id>-review-prompt.md \
  > dev/<feature-name>/reviews/<phase-id>-review[-rN].progress.ndjson 2>&1
```

Any drift in flags (adding `-s workspace-write`, dropping `--json`, changing model) invalidates codex's prompt cache.

---

## Warmed-cache measurement protocol

When measuring codex token usage before/after a template change:

1. Run the SAME review prompt three times back-to-back with identical flags.
2. Skip run 1 (cold-cache write cost, 1.25× base price).
3. Compare runs 2 and 3 (both cache-warm, 0.1× base price).
4. Record baseline tokens as the mean of runs 2 and 3 — this is the steady-state.
5. Repeat after the template change. The same run-2-and-3 mean is the comparable post-change figure.
6. A meaningful improvement is > 30% reduction in steady-state input tokens.

---

## Output-schema for verdicts

Use the structured output schema at `.agentic/templates/review-verdict.schema.json` so the orchestrator parses `verdict`, `findings[]{severity, title, file, line, suggested_fix}`, `summary` without regex-matching markdown. Enables reliable `PASS`/`FAIL` branching across review rounds.

---

## When to NOT use this skill

- Initial feature design review (before plan §4 decisions are resolved) — that's a user conversation, not a codex review.
- Non-agentic-dev reviews (ad-hoc). This skill assumes the agentic-dev workflow state (state.json, DECISIONS.md, feature-list.json).

---

## Example usage

```
/review-feature-phase phase_id=phase-5 commits=80a55821 specific_checks='["Targeted-read rule is ASCII-safe"]'
```

Emits `dev/agentic-harness-improvements/reviews/phase-5-review-prompt.md` ready for the orchestrator's `codex exec`.
