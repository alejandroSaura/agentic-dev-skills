# Build Phase Context

Reusable sub-workflow for generating minimal, focused context for a phase's agents. Replaces the old approach of sending full codebase analysis every time.

## Inputs

- `feature_name`: feature identifier
- `phase_id`: phase being prepared (e.g., "phase-2")
- `plan_content`: the phase scope and acceptance criteria from the plan
- `mode`: current execution mode

## Pre-dispatch steps

Before spawning the implementation agent for a phase, the orchestrator runs
two mandatory verification passes and embeds their output into the phase
context doc at `dev/<feature_name>/context/<phase_id>-context.md`. Both
sections are orchestrator-owned artifacts (D-10); phase sub-agents read them
and must not re-run the probes themselves.

### Scope verification
Follow `.agentic/templates/scope-verify.template.md`. The orchestrator runs
the canonical grep set against the phase's touched symbols/APIs and records
match counts, classifications, and any anomalies in a `## Scope verification`
section of the phase context doc. **This step blocks dispatch if the section
is missing or contains an unresolved anomaly.**

### Toolchain constraints probe
Follow `.agentic/templates/toolchain-probe.template.md`. The orchestrator
reads language-version and runtime-target pinning from `.csproj`,
`Directory.Build.props`, `tsconfig.json`, `Cargo.toml`, `pyproject.toml`,
`.editorconfig`, or equivalents for the languages the phase touches, and
records results in a `## Toolchain constraints` section. Cross-file
consistency checks (e.g., matching `LangVersion` across sibling csproj files)
belong here. **This step also blocks dispatch if the section is missing or
contains an unresolved anomaly** — a D-007-class language-version mismatch
must be caught here, not mid-write.

Phase sub-agents inspect both sections before touching code. If either
section is absent from the phase context doc the orchestrator has produced,
the sub-agent treats it as a dispatch violation and halts.

### Model choice

The orchestrator selects the implementation-agent model for this phase
dispatch using the 5-rule decision flow in
`.claude/commands/agentic-dev.md` §"Model Selection Heuristics" (plan
suggests → orchestrator validates against 5 promote conditions → fix rounds
auto-promote one tier → user override via context-doc metadata → record in
state). The outcome is written into a `## Model choice` section of this
context doc so the sub-agent sees the same binding the orchestrator
recorded in `state.json.current_phases[i]`. The section carries exactly two
bullets:

- `model_choice`: one of `opus`, `sonnet`, `haiku`, or `codex`. Sourced from
  `dev/<feature_name>/phase-manifest.json` (`phases[].suggested_model`) and
  then validated/promoted/overridden by the decision flow. `codex` uses the
  Codex CLI backend and stays flat rather than participating in the
  Claude-tier promotion ladder.
- `model_choice_rationale`: one of the 8 enum values documented in
  `.agentic/templates/state.schema.json` under
  `current_phases[].model_choice_rationale` — `plan_suggested`,
  `promoted_scope_ambiguity`, `promoted_unresolved_decision`,
  `promoted_cross_cutting`, `promoted_correctness_critical`,
  `promoted_foundational`, `promoted_fix_round`, `user_override`.

For v2 grandfathered features the section is omitted (no model_choice
fields exist under that schema; per D-7 the feature runs under its
original semantics). For v3 features the section is mandatory and
dispatch blocks if it is missing or carries a value outside the allowed
enums above.

## Procedure

### 1. Determine context needs

Read the phase scope from the plan and identify:
- Which files/modules the phase will touch
- Which interfaces are relevant
- Which tests need to run
- Dependencies on completed phases

### 2. Retrieve minimal context

**Lightweight mode:**
- Phase scope from plan
- SHARED_MEMORY.md current state section
- Relevant file contents (touched files only)

**Standard mode:**
- Everything in lightweight, plus:
- DECISIONS.md entries relevant to this phase
- Interface signatures for modules being modified
- Relevant test file locations

**Full mode:**
- Everything in standard, plus:
- CODEBASE_ANALYSIS.md (if it exists and is not stale)
- Dependency summaries for adjacent modules
- Cross-phase context from completed phases

### 3. Write phase context artifact

Write `dev/<feature_name>/context/phase-<N>-context.md`:

```md
# Phase Context — <phase_id>

## Phase Scope
<from plan>

## Acceptance Criteria
<from plan>

## Relevant Files
- <list of files this phase will touch or read>

## Key Interfaces
<signatures and contracts the agent needs to know>

## Dependencies on Prior Phases
<what was established in earlier phases that this phase builds on>

## Test Targets
<which tests to run, how to run them>

## Notes from Decisions Log
<relevant entries from DECISIONS.md, if any>

## Model choice
- model_choice: <opus|sonnet|haiku|codex>
- model_choice_rationale: <plan_suggested|promoted_scope_ambiguity|promoted_unresolved_decision|promoted_cross_cutting|promoted_correctness_critical|promoted_foundational|promoted_fix_round|user_override>
```

### 4. Update state.json

No state change — context building is a sub-step of the implementation cycle.

## Prompt assembly (stable prefix + dynamic suffix)

The phase-context artifact produced above is the *dynamic-suffix* payload the orchestrator plugs into `.agentic/templates/impl-prompt.template.md` before dispatching an implementation, fix, or review sub-agent. The template is the authoritative skeleton; this skill fills in one section of it.

Assembly rules (see `.claude/commands/agentic-dev.md` section "Prompt Cache Economics" for the rationale):

1. Load `.agentic/templates/impl-prompt.template.md` once per dispatch. Treat the `## Stable prefix` block as read-only text: inline the referenced files (`AGENTS.md`, feature `REQUIREMENTS.md`, plan Design Decisions excerpt) verbatim without reordering, rewrapping, or conditionally rewriting them. The stable prefix must be byte-identical across every sub-agent spawned within a session so Claude's automatic prompt cache can reuse the entry.
2. Do NOT inline `DECISIONS.md` into the stable prefix. It grows per phase and would invalidate the cache. Instead, in the dynamic suffix's "DECISIONS snapshot" section, record the path to `dev/<feature_name>/runs/<run-id>/decisions-snapshot.md` plus its sha256 digest; the sub-agent opens the snapshot if it needs the full text.
3. Fill the dynamic suffix sections from phase-scoped state:
   - "Phase context" = the artifact produced by this skill (`dev/<feature_name>/context/phase-<N>-context.md`).
   - "Run identity" = feature/phase/run-id/attempt/review-round/fix-round from `state.json`.
   - "DECISIONS snapshot" = snapshot path + sha256.
   - "Handoff format" and "Stale artifact self-audit" = kept as-is from the template. The self-audit contract is authoritative in `.agentic/templates/impl-prompt.template.md` §"Stale artifact self-audit"; reviewer enforcement lives in `.agentic/skills/run-review.md` §"Verify self-audit".
4. Dispatch blocks if the stable prefix cannot be assembled byte-identically for any reason (for example, `AGENTS.md` or the plan's Design Decisions section is missing). Surface the failure as a blocker rather than silently mutating the prefix.

## Output

- `dev/<feature_name>/context/phase-<N>-context.md` ready for agent consumption
- Focused context instead of full codebase dump
- Dynamic-suffix payload for `.agentic/templates/impl-prompt.template.md`; stable-prefix assembly is the orchestrator's responsibility and is byte-identical per session
