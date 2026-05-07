# Toolchain Probe Template

This template produces the `## Toolchain constraints` section embedded in
every phase context doc at `dev/<feature>/context/<phase-id>-context.md`.

The orchestrator runs the probe before dispatching the phase's implementation
agent. Dispatch blocks if the section is missing or contains an unresolved
anomaly (see `build-phase-context.md` §"Pre-dispatch steps").

Artifact ownership per D-10: orchestrator-owned. Phase sub-agents only read
the populated section; they are not permitted to re-run the probe.

## Why this exists

D-007-class issues (e.g., a phase planning to use `file-scoped namespaces`
only to discover the project pins `LangVersion` to C# 9.0) get caught at the
planning/dispatch boundary rather than mid-write. The probe is cheap, and a
missing pin is itself information that the phase must know about.

## Probe catalog

Pick the subset relevant to the phase's touched files. If multiple languages
are in scope, run every relevant section.

### C# / .NET

For every `.csproj` (and `Directory.Build.props` / `Directory.Build.targets`)
in the repo or in the phase's touched directories:

- `<TargetFramework>` / `<TargetFrameworks>`
- `<LangVersion>` — **this is the D-007 class of issue.** A C# 9.0 project
  cannot use file-scoped namespaces, global usings, raw string literals, or
  other C# 10/11/12 features. Record the exact value.
- `<Nullable>` — `enable`, `disable`, `warnings`, or `annotations`.
- `<TreatWarningsAsErrors>` — changes what "passes" looks like.
- `<AnalysisLevel>` / `<AnalysisMode>` — analyzer strictness.
- Cross-file consistency check: different `LangVersion` in sibling csproj
  files is itself a flag.

### TypeScript / JavaScript

- `tsconfig.json`: `target`, `module`, `moduleResolution`, `strict`, `lib`.
- `package.json`: `engines.node`, `type` (module vs commonjs).
- `.nvmrc`, `.node-version`.

### Rust

- `Cargo.toml`: `edition`, `rust-version` (MSRV).
- `rust-toolchain` / `rust-toolchain.toml`.

### Python

- `pyproject.toml`: `requires-python`, `[tool.*]` sections.
- Lock files: `poetry.lock`, `uv.lock`, `requirements.txt` pinned versions.
- `.python-version`.

### Unity-specific

- `ProjectSettings/ProjectVersion.txt` — Unity editor version.
- `Packages/manifest.json` — package versions the phase's code depends on.
- `ProjectSettings/ProjectSettings.asset` — scripting backend, API level.

### Generic / cross-language

- `.editorconfig` — indent, line endings, trim policies.
- `.tool-versions` (asdf), `mise.toml`.
- CI matrix files (`.github/workflows/*.yml`) — authoritative runtime pins.

## Result shape (paste into phase context doc)

```markdown
## Toolchain constraints

Run at: <ISO-8601 timestamp>
Cwd: <repo root>
Phase: <phase-id>

### C# / .NET

| File | TargetFramework | LangVersion | Nullable | TreatWarningsAsErrors |
|---|---|---|---|---|
| `src/Foo/Foo.csproj` | net8.0 | 9.0 | enable | true |
| `tests/Foo.Tests/Foo.Tests.csproj` | net8.0 | 9.0 | enable | true |

Consistency: all csproj agree on LangVersion=9.0. Phase must not use C# 10+
features (file-scoped namespaces, global usings, raw string literals).

### Unity

ProjectVersion.txt: 2022.3.42f1 — stable LTS.

Anomalies: none
```

If any field is missing from a probed file, record `missing` explicitly — do
not silently omit the row. A missing pin is itself an anomaly if the phase
depends on that tool.

## Anomaly flags that BLOCK dispatch

- Inconsistent `LangVersion` (or equivalent) across files the phase expects
  to be uniform.
- Language version strictly less than the phase plan's assumption (the phase
  cannot use language features it planned to use).
- `TreatWarningsAsErrors=true` when the phase plan silently assumed lenient
  compile.
- Missing pin for a tool the phase depends on (e.g., phase assumes Node 20
  but there is no `engines.node`, no `.nvmrc`, and no CI matrix entry).
- Target runtime mismatch between src and tests projects.

## Resolution workflow

1. Orchestrator records the anomaly in this section.
2. Either (a) amend the phase plan to match the real constraint (common: drop
   the language feature, use an older form), or (b) flag a cross-phase
   migration as an out-of-scope blocker and stop.
3. Dispatch unblocks when the section shows no unresolved anomalies.
