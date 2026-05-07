# Implementation Agent Prompt Template

Canonical prompt layout for every sub-agent invocation (implementation, fix,
review). Enforces a byte-identical stable prefix so Claude's automatic
prompt-cache has a consistent entry to hit across the session.

Authoritative caching rules live in `.claude/commands/agentic-dev.md`
(§"Prompt Cache Economics"). Authoritative assembly procedure lives in
`.agentic/skills/build-phase-context.md`. This template is the shape those
two agree on.

Rules of use:
- Assemble the stable prefix byte-identically across every sub-agent spawned
  within a single orchestrator session. Any change here invalidates the cache
  for every subsequent sub-agent.
- Anything that varies per phase, per attempt, or per fix-round belongs in the
  dynamic suffix. Never in the stable prefix.
- `DECISIONS.md` content is dynamic (it grows as execution proceeds). Reference
  it by snapshot hash + path from the dynamic suffix; do not inline the file
  contents into the stable prefix.

## Stable prefix
<!-- This section's byte content must be identical across all sub-agent
invocations within a session. Changes here invalidate the prompt cache for
every subsequent sub-agent in the session. Do not add per-phase material,
per-attempt counters, timestamps, or any field that mutates during execution. -->

### Project rules (from .agentic/templates/AGENTS.md)
<!-- Inline the full contents of .agentic/templates/AGENTS.md verbatim here.
The file is a pinned repo-level document; if it changes during a session the
stable-prefix byte identity breaks for that session only, which is expected
and acceptable. -->

### Feature requirements (from dev/<feature-name>/REQUIREMENTS.md)
<!-- Inline the full contents of dev/<feature-name>/REQUIREMENTS.md verbatim.
Stable for the lifetime of the feature. Edits to REQUIREMENTS.md mid-feature
are an orchestrator-only action (per D-10) and reset the prefix cache for any
remaining sub-agents. -->

### Plan excerpt — Design Decisions
<!-- Inline the §"Design Decisions" section (or equivalent locked-decisions
section) from the plan file passed as `plan=<path>` to /agentic-dev. This is
the static design-frame the whole feature executes against, so it belongs in
the stable prefix. Per-phase decision deltas live in the dynamic suffix under
"DECISIONS snapshot". -->

## Dynamic suffix
<!-- Per-phase content. Changes every dispatch; does not affect the stable
prefix's cache entry. Orchestrator populates these sections from the
authoritative sources named below. -->

### DECISIONS snapshot
<!-- Reference the current state of dev/<feature-name>/DECISIONS.md by
snapshot hash and path. The orchestrator writes the snapshot under
dev/<feature-name>/runs/<run-id>/decisions-snapshot.md right before
dispatching this agent; the path + sha256 are the only fields that appear
here. The sub-agent reads the snapshot file if it needs the full text. Do
NOT inline the DECISIONS.md content into this prompt; it grows per phase. -->

- path: dev/<feature-name>/runs/<run-id>/decisions-snapshot.md
- sha256: <hex digest>

### Phase context
<!-- Inline the content of dev/<feature-name>/context/<phase-id>-context.md
verbatim. This is produced by `.agentic/skills/build-phase-context.md` and is
scoped to the single phase being dispatched. -->

### Run identity
<!-- Run-level fields that belong with the suffix (not the prefix). -->

- feature_name: <feature-name>
- phase_id: <phase-id>
- run_id: <phase_id>-<agent_type>-<sequence>
- attempt: <n>
- review_round: <n>
- fix_round: <n>

### Handoff format
<!-- Standard handoff template expected back from the sub-agent. Reproduced
here so the agent knows the exact report structure without an extra round
trip. Each bullet is a required section. -->

1. Files touched — per-file line delta and brief purpose.
2. Verification results — outcome of every gate this phase declares.
3. Deviations — any brief departure from the phase context, with rationale.
4. Stale artifact self-audit — the formal section defined below. MUST appear
   in every handoff, even when no stale artifacts are found.

### Stale artifact self-audit
<!-- MANDATORY section in every impl-agent handoff. The sub-agent fills in
the three bullets below by diffing this phase's changes against the base
commit and grep-sweeping the working tree for references to any renamed or
deleted symbols. The reviewer will cross-check at least one claim (see
`.agentic/skills/run-review.md` §"Verify self-audit"), so listing the exact
grep commands you ran is load-bearing, not decorative. -->

The handoff MUST include a top-level `## Stale artifact self-audit` heading
followed by these three bullets. Each bullet enumerates matches found outside
this phase's diff, or states "None found after diff-grep sweep" if the sweep
turned up nothing.

- **Comments or XML docs** that reference renamed/deleted symbols from this
  phase's diff. Run a grep of each old name against the final working tree
  and list any match that is NOT part of the diff itself (i.e. lines the
  phase did not already rewrite). Example: if the phase renamed
  `OldThing` → `NewThing`, run `grep -rn 'OldThing' <repo>` and list any
  surviving comment, `///`/`/** */` doc-comment, or inline note.
- **Tests** whose assertions are about behavior this phase changed or
  removed. Grep test files for the old API names and for string literals
  that encoded the old behavior (error messages, log prefixes, fixture
  identifiers). List any test that asserts on the pre-change shape and was
  not updated in this phase's diff.
- **Docs** (README, architecture doc, plan file, proposals, ADRs, skill/
  template files) that mention the changed API surface. Grep the `docs/`
  tree, top-level markdown files, `.claude/`, and `.agentic/` for the old
  names; list any doc that still describes the pre-change contract.

#### How to populate

1. Run `git diff <base-commit>..HEAD` (or the phase's equivalent base-to-head
   diff) and extract every symbol, filename, or string literal that got
   renamed or deleted in the diff. "Deleted" counts only if the name no
   longer exists anywhere the diff introduced; transient renames that still
   resolve don't count.
2. For each extracted name, run `grep -rn '<name>' <repo>` (scoped to the
   trees listed above; use `--include` filters as needed for speed).
3. Filter out matches that are themselves part of the diff (i.e. lines the
   phase already rewrote — these are not stale). Any surviving match is a
   candidate for the audit list; record file path, line number, and a
   one-line reason.
4. If a match is intentional (e.g. a changelog entry deliberately naming the
   old symbol, or a test fixture that documents historical behavior), still
   list it and tag the reason `intentional: <why>`. The reviewer decides
   whether to accept the tag.

#### Null-finding rule

If the diff-grep sweep genuinely surfaces no stale artifacts, the section
MUST still appear in the handoff with the exact phrase
`None found after diff-grep sweep` under each of the three bullets (or once
under the heading if the agent prefers a single consolidated line). Omitting
the section, or replacing it with "N/A" or silence, is a handoff violation
and the reviewer will block on it.
