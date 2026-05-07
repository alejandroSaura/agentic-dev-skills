# Plan — <Feature Title>

**Status:** Draft
**Originating proposal:** `docs/proposals/<feature>.md`

---

Canonical template for every plan doc authored under this harness (e.g.
`docs/plans/plan-<feature>.md`). The `/agentic-dev` initializer reads the
plan and refuses to dispatch phases until §4 "Decisions needed before
execution" is empty of unresolved entries.

Keep the section headings below byte-stable — the orchestrator greps them by
name to drive initialization, phase dispatch, and parallelism evaluation.
Anything optional lives inside a section; do not omit the headings.

---

## 1. Motivation

<!-- Why this change? What's the pain point it addresses? Reference the
incident, post-mortem, or user ask that triggered the proposal. One to three
paragraphs; prose over bullet lists. -->

## 2. Scope

**In scope:**
- <list>

**Out of scope:**
- <list>

**Constraints:** <load-bearing constraints — language version, runtime
target, backwards-compatibility obligations, no-new-dependencies promises,
etc. Anything a sub-agent could trip over if they didn't know. Pulled into
each phase context doc's §"Toolchain constraints" at dispatch time.>

## 3. Design Decisions

<!-- Decisions that shape the phase structure. Numbered D-1, D-2, ... Each
entry records the decision, the rationale, and (briefly) the alternatives
considered. Plan-level decisions are ratified when the user signs off on the
plan; they get imported into `dev/<feature>/DECISIONS.md` at initialization. -->

### D-1 — <short title>
<!-- Decision statement in one sentence, then rationale, then alternatives. -->

- **Decision:** <what was decided>
- **Rationale:** <why>
- **Alternatives considered:** <what was rejected and why>

### D-2 — <short title>
<!-- Repeat for each plan-level decision. -->

## 4. Decisions needed before execution

<!-- MANDATORY. Do NOT remove this heading even if the list is empty — the
initializer greps for "Decisions needed before execution" verbatim. -->

Initialization blocks until each decision listed here is recorded in
`dev/<feature>/DECISIONS.md`. The orchestrator will not dispatch any phase
while an entry remains unresolved; resolving an entry means writing a
dated D-N block to `DECISIONS.md` with a definitive answer (not a "we'll
decide later").

List every design question the user or orchestrator must resolve up-front.
Categories to cover, in rough priority order:

- **API shape** — public surface, method signatures, return types.
- **Layer / storage** — where data lives, which module owns it, read vs.
  write ownership.
- **Naming** — file names, type names, public identifiers that later phases
  will grep against.
- **Language / runtime** — version constraints, target framework, nullable
  context, feature-flag availability.
- **Scope ambiguity** — anything the plan leaves open that a sub-agent
  would otherwise have to guess.

### D-needed-1 — <question>

- **Category:** <API shape | layer/storage | naming | language-version | scope ambiguity>
- **Options:** <enumerate the realistic choices>
- **Default if omitted:** <what the orchestrator will assume if the user
  does not answer; may be "none — hard block">
- **Resolution target:** before phase-<N> dispatch

### D-needed-2 — <question>
<!-- Repeat per open question. Remove this whole section's body and leave
the heading if a plan genuinely has zero open questions — the heading
itself is what F-011 and the orchestrator greps require. -->

## 4a. Feature list — 1-entry scale-down rule

Per D-2, every feature carries a mandatory `dev/<feature>/feature-list.json`
drafted at initialization from §8 "Success Criteria" and §9 "Verification
Commands" below. The default shape is multi-entry — one entry per observable
acceptance check. Plans may scale down to a **1-entry feature-list** only
when ALL four of the following conditions hold:

- **exactly one observable behavior** added, changed, or removed by this
  feature (a single user-visible or test-visible effect, not a bundle).
- **exactly one verification command** whose exit code alone determines
  pass/fail. Shell pipelines that hide multiple sub-checks (`cmd1 && cmd2`,
  `cmd | grep ...`, `test -f X && test -f Y`) do NOT count as one command —
  they're multiple checks masquerading as one and each must be its own
  feature-list entry.
- **zero cross-phase dependencies** — the feature either lands entirely in
  one phase, or spans phases with no references back to earlier/later
  phases' artifacts.
- **touched-files ≤ 3** — the phase's declared touched-files set contains
  at most 3 paths. Four or more files implies surface area that's unlikely
  to be captured by a single observable behavior.

If any of these four conditions fails, the feature-list MUST have multiple
entries. This prevents "1-entry theater" on medium-sized work where the
single entry papers over real acceptance checks that should each stand
alone.

Mechanics:

- Initialization (`.agentic/skills/initialize-feature.md` §4a) checks the
  four conditions against the plan before accepting a 1-entry draft.
- If a 1-entry draft fails the check, the orchestrator drafts a
  multi-entry list and re-presents it to the user for sign-off.
- The example shape at `.agentic/templates/feature-list.example.json`
  shows a valid 1-entry case (single docs edit, single grep verification,
  single phase, single file).

## 5. Phases

<!-- Each phase has its own subsection. Keep phase numbering stable once the
plan is ratified; downstream artifacts (branches, state.json, feature-list)
reference phase ids by number. -->

### Phase 1 — <short title>

**Target files:**
- <path>

**Changes:**
- <bullet list of concrete edits>

**Acceptance:**
- <observable pass conditions; these become feature-list entries at
  initialization>

**Scope:** <trivial | small | small-medium | medium | medium-large | large>

### Phase 2 — <short title>
<!-- Repeat per phase. -->

## 6. Phase dependencies

<!-- DAG edges. Used by the initializer to build the phase dependency graph
and by the §Parallelism logic to evaluate candidate pairs. Every phase
referenced in §5 must appear here, even if it has no dependencies. -->

```
Phase 1 ──▶ Phase 3
Phase 2 ──▶ Phase 3
Phase 4 ──▶ (no downstream)
```

Recommended execution order:
1. Phase X (rationale — e.g., foundation, trivial-land-early, unblocks Phase Y).
2. Phase Y ...

### Bundling / splitting

<!-- Optional. If the plan intends any phases to ship in a single PR, or
explicitly not to, record it here. The orchestrator respects declared
bundling when staging merges. -->

## 7. Risks and Rollback

| Risk | Probability | Mitigation | Rollback |
|---|---|---|---|
| <risk> | <low / medium / high> | <mitigation> | <rollback path> |

All phases should be reversible by `git revert` of their landing commit
unless the plan explicitly calls out an irreversible step (e.g., schema
migration, public API deletion) and records the rollback plan above.

## 8. Success Criteria

<!-- Feature-level success conditions. These map to feature-list entries
via the initializer (one Success Criterion → one or more feature-list
entries). Keep each criterion observable — a shell command or a file
predicate should be derivable from it. -->

Feature is complete when:

1. <criterion>
2. <criterion>

## 9. Verification Commands (per phase)

<!-- Indicative commands per phase. The authoritative verification set is
`dev/<feature>/feature-list.json` (produced at initialization by the
orchestrator, signed off by the user). Commands here are the seeds the
orchestrator uses when drafting that file. Paths are repo-root-relative
per D-11. -->

```bash
# Phase 1 — <what it verifies>
test -f <path> && grep -q '<anchor>' <path>

# Phase 2 — ...
```

## 10. Open Questions (Non-Blocking)

<!-- Questions the plan does NOT need answered to start execution, but that
warrant follow-up. These do NOT block initialization — that is what §4 is
for. Keep §4 and §10 strictly separate; merging them defeats the purpose of
the initialization gate. -->

- <question>
- <question>
