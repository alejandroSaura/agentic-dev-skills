# Review Prompt Template

Canonical prompt layout for every review sub-agent invocation spawned by the
orchestrator. Structurally symmetric with `impl-prompt.template.md`: a
byte-identical **stable header** (reusable across every review round in a
session) followed by a **phase-specific** dynamic suffix.

Authoritative assembly lives in `.claude/commands/review-feature-phase.md`
(the project-scoped skill that emits the final prompt). Authoritative review
procedure — verdict handling, self-audit gate, review-log writing — lives in
`.agentic/skills/run-review.md`. This template is the shape those two agree
on.

Rules of use:
- Assemble the stable header byte-identically across every review agent
  spawned within a single orchestrator session. Any change here invalidates
  both Claude's automatic prompt cache and codex's prefix cache for every
  subsequent review in the session.
- Anything that varies per phase, per round, or per diff belongs in the
  phase-specific suffix. Never in the stable header.
- `DECISIONS.md` content is dynamic (it grows as execution proceeds). The
  header references it by path + snapshot hash; the suffix supplies the
  actual hash for the current round. Never inline `DECISIONS.md` contents
  into the stable header.

## Stable header
<!-- This section's byte content must be identical across every review
agent invocation within a session. Changes here invalidate the prompt
cache for every subsequent review agent. Do not add phase IDs, commit
ranges, timestamps, round counters, or any field that mutates during
execution. -->

### Project rules (from .agentic/templates/AGENTS.md)
<!-- Inline the full contents of .agentic/templates/AGENTS.md verbatim
here. The file is a pinned repo-level document; if it changes during a
session the stable-header byte identity breaks for that session only,
which is expected and acceptable. Inlining (rather than referencing by
path) is deliberate so codex does not need a `Read` tool call to pick
up the rules — the rules are part of the cached prefix. -->

### Review rubric
<!-- Reviewer contract. Stable across the whole session: verdict format,
severity grouping, blocker conditions. -->

The review agent MUST return a structured verdict with the following shape.
Orchestrator parses the verdict rather than regex-matching markdown, so the
field names are load-bearing.

- **verdict**: exactly one of `PASS` or `FAIL`.
- **summary**: one-paragraph rationale for the verdict. Required on both
  PASS and FAIL.
- **findings[]**: an array. Empty on PASS; non-empty on FAIL. Each finding
  has:
  - **severity**: one of `critical`, `important`, `optional`.
  - **title**: one-line summary of the issue.
  - **file**: repo-root-relative path; `null` if the finding is not file-
    local (e.g. a missing gate).
  - **line**: integer line number in `file`; `null` if not applicable.
  - **suggested_fix**: one-to-three-sentence concrete remediation the fix
    agent can execute without additional context.

Severity grouping rules (applied by the reviewer, not the orchestrator):
- `critical` — the phase is not acceptable at any round. Examples: scope
  breach outside the declared touched-files set, missing mandatory handoff
  sections, null self-audit claim falsified by cross-check grep, safety-
  constraint violation from `AGENTS.md` §Safety Constraints, verification
  gate result contradicts the diff (e.g. tests claim to pass but the
  command output shows failures).
- `important` — the phase is FAIL-worthy but a fix cycle can reasonably
  address it. Examples: missed specific_check, weak self-audit evidence
  that the reviewer confirmed is incomplete, an acceptance criterion from
  the plan not visibly satisfied by the diff.
- `optional` — the phase can PASS with this recorded. Examples: style
  suggestions, future refactor hints, minor doc polish. `optional`
  findings MUST NOT by themselves produce a FAIL verdict.

A verdict is `FAIL` if and only if `findings[]` contains at least one
`critical` or `important` entry. All-`optional` findings yield `PASS` with
the findings still recorded.

### Verify self-audit gate

Before returning the verdict, execute the self-audit verification gate
defined in `.agentic/skills/run-review.md` §"Verify self-audit". In
summary:

1. Locate the `## Stale artifact self-audit` heading in the impl agent's
   handoff. If missing, the review is an automatic FAIL with a `critical`
   finding titled "handoff missing mandatory self-audit section". Do not
   proceed.
2. Cross-check at least one claim. For a non-empty bullet, confirm one
   listed entry still exists at the stated file/line. For a "None found
   after diff-grep sweep" claim, pick one renamed or deleted symbol from
   the phase's diff and grep the working tree; if the grep surfaces a
   plausible stale artifact the agent did not list, that is an automatic
   FAIL with a `critical` finding titled "self-audit null claim falsified".
3. Record the cross-check grep command and its outcome in the review
   output under a `self_audit_verification` field with keys
   `claim_checked`, `grep_command`, `result`
   (`consistent` / `discrepancy` / `null_claim_falsified`).

The self-audit gate runs in addition to — not in place of — scope and
correctness review.

### Branch naming acknowledgment (D-9)

Per Decision D-9, phase branches are named flat:
`feature/<feature-name>-phase-<N>`. Git refs cannot support the
hierarchical `feature/<name>/phase-<N>` form. Any finding that references
the old hierarchical layout as current practice is incorrect; flag it as
a `critical` reviewer-side error and correct it before emitting the
verdict.

### Shared-artifact ownership acknowledgment (D-10)

Per Decision D-10, every path under `dev/<feature-name>/` is orchestrator-
only-writable by default. Sub-agent writes to shared artifacts
(`DECISIONS.md`, `SHARED_MEMORY.md`, telemetry, review logs, feature-list)
are a scope breach unless the phase's context doc explicitly listed the
path as phase-scoped. Reviewer flags any such write as `critical`.

### DECISIONS snapshot reference

`DECISIONS.md` is dynamic. The phase-specific suffix supplies the current
snapshot path and sha256. Do not inline `DECISIONS.md` into this header.

## Phase-specific section
<!-- Dynamic suffix. Changes every dispatch; does not affect the stable
header's cache entry. The `/review-feature-phase` skill populates these
fields from the authoritative sources named below. -->

### Phase identity

- feature_name: `<feature-name>`
- phase_id: `<phase-id>`
- run_id: `<phase_id>-review-<round>`
- review_round: `<n>`
- commits_under_review: `<base>..<head>` (e.g.
  `feature/<feature-name>...feature/<feature-name>-phase-<N>`)

### DECISIONS snapshot

- path: `dev/<feature-name>/runs/<run-id>/decisions-snapshot.md`
- sha256: `<hex digest>`

### Files to read (allowlist)

<!-- Explicit allowlist reduces codex's tool-use tokens and focuses
attention. The reviewer MUST NOT Read files outside this list. The diff
(embedded below or referenced by commit range) counts as already-read. -->

- `<path-1>`
- `<path-2>`
- `<path-N>`

Files you must NOT read beyond this allowlist and the embedded/referenced
diff: everything else in the repo.

### Diff embedding decision

Threshold: **8 KB**. Measured as the byte length of
`git diff --no-color --no-ext-diff <base>..<head>`.

- If diff size ≤ **8 KB**: the skill embeds the full diff verbatim under a
  `### Diff (embedded verbatim)` subheading below. Cheaper than a round-
  trip `git diff` tool call plus per-file `Read`s, and keeps the prompt
  self-contained for codex's prefix cache.
- If diff size > **8 KB**: the skill falls back to a commit-range header
  plus the file allowlist above. The reviewer runs
  `git diff --no-color --no-ext-diff <base>..<head>` and targeted
  `Read --offset --limit` calls only against the allowlist. Embedding a
  multi-KB diff verbatim would blow the prompt out past the cache-friendly
  size and defeat the point of the stable header.

The `/review-feature-phase` skill records which pathway it chose (embedded
vs. commit-range) in the review-log frontmatter so the measurement trail
is auditable.

### Diff (embedded verbatim)
<!-- Present only when diff size ≤ 8 KB. Verbatim output of
`git diff --no-color --no-ext-diff <base>..<head>`. The `--no-color` and
`--no-ext-diff` flags are required so the bytes are reproducible across
runs and the codex prefix cache stays warm. -->

```diff
<diff bytes here, or omit this subsection entirely when the commit-range
fallback applies>
```

### Specific checks

<!-- Array of focused review checks supplied by the orchestrator, one per
bullet. Each check is a specific, falsifiable claim the reviewer must
either confirm or refute in the verdict. These come from the phase's
acceptance criteria in the plan, plus any open items from prior review
rounds. -->

- `<specific_check_1>`
- `<specific_check_2>`
- `<specific_check_N>`

### Deferred findings (optional)

<!-- Present only when round > 1, or when prior rounds raised findings
that were explicitly deferred rather than fixed. Pre-digest: a short
paragraph per deferred finding summarizing what was said before and why
it was deferred, so codex does not have to re-read the prior round's
verdict. When absent, the skill omits this entire subsection. -->

- `<deferred_finding_summary_1>`
- `<deferred_finding_summary_N>`

### What was addressed since the last round (optional)

<!-- Present only when round > 1. One short paragraph describing which
findings the fix agent claims to have addressed, with commit SHAs. The
reviewer checks those claims against the diff rather than re-reading the
prior round's verdict end-to-end. -->

- `<fix_summary_for_finding_X>` (commit `<sha>`)

### Expected verdict format

Return the verdict as a single JSON object matching the schema in
`.claude/commands/review-feature-phase.md` §"Output schema". Field names
are load-bearing; the orchestrator parses by field, not by markdown
regex. The structured output is what the codex `--output-schema` flag
enforces; for Claude-model reviewers, the same JSON shape applies inside
the final message.

Remember:
- `verdict` ∈ {`PASS`, `FAIL`}.
- `findings[]` empty on PASS, otherwise grouped by severity at parse time.
- `self_audit_verification` is mandatory regardless of verdict.
- `summary` is mandatory regardless of verdict.
