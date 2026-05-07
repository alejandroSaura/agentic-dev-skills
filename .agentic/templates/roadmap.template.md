# Roadmap — <Feature Title>

**Status:** Draft (v2)
**Originating spec / proposal:** `docs/proposals/<feature>.md` *(or external spec path)*
**Started:** <YYYY-MM-DD>

---

Canonical template for every roadmap doc authored under this harness (e.g.
`docs/roadmaps/<feature>.md`). A roadmap is the index for an initiative
that spans multiple plans, each implemented independently via `/agentic-dev`.

- `/adversarial-review-roadmap` reviews this document adversarially (slicing, ordering,
  exit demos, spec coverage, cross-plan coupling).
- `/roadmap-runner` consumes this document to dispatch each child plan in
  sequence: `/adversarial-review-plan` to author each child plan lazily, then
  `/agentic-dev` to implement it, gating on human approval at the points
  the runner promotes from agentic-dev.

Keep the section headings below byte-stable — both skills grep them by
name. Anything optional lives inside a section; do not omit the headings.

---

## 1. Motivation

<!-- Why this initiative? What does it deliver? Reference the spec or
proposal that triggered it. One to three paragraphs. -->

## 2. Scope

**In scope (this roadmap):**
- <list the major outcomes the roadmap will produce>

**Out of scope:**
- <items the spec covers but this roadmap explicitly defers or rejects>

**Constraints:** <load-bearing constraints — language version, runtime
target, deadline, must-not-break interfaces, etc.>

## 3. Sequencing principles

<!-- Why the cuts are where they are. Each principle is auditable: the
/adversarial-review-roadmap reviewer checks plans-as-listed against these. -->

- **Vertical slices.** Every plan ships an end-to-end demo, not a horizontal layer.
- **Risk first.** Front-load architecturally novel pieces.
- **(other principles specific to this roadmap)**

## 4. Plans

<!-- One subsection per child plan, in execution order. Each plan declares
slug, scope summary, exit demo, dependencies, and current status. The slug
is the stable identifier — once chosen, do not rename it (downstream
artifacts including `docs/plans/plan-<slug>.md`, `dev/<slug>/`, branches
`feature/<slug>-phase-<N>`, and the runner's child-plan entries all
reference it). -->

### Plan 1 — <short title>

- **Slug:** `<kebab-case-slug>`
- **Plan file:** `docs/plans/plan-<slug>.md` *(created lazily by `/adversarial-review-plan` when the runner reaches this plan)*
- **Scope:** <2-4 sentences on what this plan delivers>
- **Exit demo:** <a binary observable a human can verify with their eyes — "open the page, type, see characters round-trip" beats "spine works">
- **Depends on:** none / Plan N
- **Status:** `not_started`

### Plan 2 — <short title>
<!-- Repeat per plan. -->

## 5. Coverage map (spec → plans)

<!-- Required when the roadmap is distilled from a spec. Maps each spec
acceptance criterion (or non-goal) to the plan(s) that cover it. The
/adversarial-review-roadmap reviewer uses this to verify the roadmap covers the spec
without silent drift. If the roadmap has no upstream spec, replace the
table with a single line: "No upstream spec." -->

| Spec section / criterion | Covered by | Notes |
|---|---|---|
| <e.g. "User can sign in with Google"> | Plan 4 | |
| <"All inter-service traffic uses TLS"> | Plan 1 (mTLS spine), Plan 4 (browser TLS) | |
| <"Sandboxing beyond worker daemon"> | out of scope | per spec non-goal |

## 6. Cross-plan coupling

<!-- Optional but recommended. Where plan N sets up a contract that plan M
depends on, document the contract here. Helps the reviewer check that N
actually delivers what M assumes. Helps the planner of M anchor the work. -->

- **Plan N introduces `<thing>`** consumed by Plan M+: <one-line contract>.
- **Plan N defers `<thing>` to Plan M**: <one-line note>.

## 7. Risks

<!-- Roadmap-level risks. Per-plan risks live in each plan's own §"Risks".
Risks here are ones that span plans or threaten the roadmap as a whole
(e.g., "TOS gray area for subscription pooling — if rejected, swap
AuthSource implementations in Plan N"). -->

| Risk | Probability | Impact | Mitigation | Affected plans |
|---|---|---|---|---|
| <risk> | low/med/high | low/med/high | <mitigation> | Plan N, Plan M |

## 8. Status conventions

Each plan's `Status:` line takes one of:

| Status | Meaning |
|---|---|
| `not_started` | No work begun. |
| `planning` | `/adversarial-review-plan` is running for this plan. |
| `plan_ready` | Plan file exists and has been adversarially reviewed; awaiting human approval. |
| `implementing` | `/agentic-dev` is running for this plan. |
| `demo_pending` | `/agentic-dev` returned success; human exit-demo verification pending. |
| `complete` | Demo verified; plan landed. |
| `blocked` | See `dev/<roadmap-slug>/runner-state.json` blocker payload, or the notes referenced in the plan's Status line. |

Status is updated by `/roadmap-runner`. The roadmap doc is the
human-readable projection; `dev/<roadmap-slug>/runner-state.json` is the
canonical runner state.

## 9. Open questions (non-blocking)

<!-- Roadmap-level questions that don't block dispatching the next plan.
Per-plan open questions live in each plan's §10. Items that DO block
dispatch should not live here — split the affected plan or rework the
roadmap before running. -->

- <question>
