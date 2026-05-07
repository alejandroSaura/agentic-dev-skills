# Install

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and working.
- `git` available on your machine.
- For the adversarial review skills (`/adversarial-review-plan`, `/adversarial-review-roadmap`): the [`codex` CLI](https://github.com/openai/codex) must be on `PATH`. The cross-model reviewer is load-bearing — without codex, the review skills will fail at round 1.

## Quick install

Clone this repo, then run the install script for your platform from the repo root:

### Windows (PowerShell)

```powershell
git clone <repo-url> agentic-dev-skills
cd agentic-dev-skills
.\install.ps1
```

### macOS / Linux

```bash
git clone <repo-url> agentic-dev-skills
cd agentic-dev-skills
chmod +x install.sh
./install.sh
```

The scripts copy:
- `.claude/commands/*` → `~/.claude/commands/`
- `.agentic/*` → `~/.agentic/`

Existing files at those destinations are **overwritten**. If you have customised `~/.claude/commands/` or `~/.agentic/` outside of this bundle, back them up first.

## Manual install (no script)

If you'd rather copy files yourself, the destinations are:

```
.claude/commands/<file>.md   →  ~/.claude/commands/<file>.md
.agentic/<everything>        →  ~/.agentic/
```

On Windows, `~/` is `%USERPROFILE%\`. On macOS/Linux, it's `$HOME/`.

## Verify the install

Open Claude Code; the available-skills list should now include:

- `agentic-dev`
- `adversarial-review-plan`
- `adversarial-review-roadmap`
- `roadmap-runner`
- `review-feature-phase`

If any are missing, restart Claude Code (or open a new session). The harness re-scans `~/.claude/commands/` on session start.

## Updating

Pull the latest, re-run the install script. Files at the destination are overwritten with the new version.

## Agent-driven install

If you want an agent (e.g. Claude Code on the new machine) to install this for you, point it at this file and tell it to:

1. Clone this repo to a path it controls (e.g. `~/code/agentic-dev-skills`).
2. From the repo root, run `.\install.ps1` on Windows or `./install.sh` on macOS/Linux. The agent has Bash / PowerShell tools to do this — the steps are mechanical.
3. List available skills (or restart the Claude Code session and check the skill listing) to confirm the four new skills appear: `agentic-dev`, `adversarial-review-plan`, `adversarial-review-roadmap`, `roadmap-runner`. (`review-feature-phase` may already be present from a prior install — that's fine; this bundle includes the same canonical version.)
4. Verify `codex` is on `PATH` if the user intends to use the adversarial review skills or codex-as-implementer in `/agentic-dev`. If not, install codex first or document the limitation.

The agent should NOT push, modify, or commit anything in the user-global skill locations beyond what the install script does. If the install script fails (permissions, missing dirs), surface the error rather than working around it.

## Troubleshooting

- **"Skill not found" after install**: Claude Code caches the skill list per session. Restart the session.
- **Codex review fails with permission errors**: ensure `codex` is on `PATH` in the same shell Claude Code launches sub-processes from.
- **Install script fails on Windows with execution policy error**: run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once, or invoke as `powershell -ExecutionPolicy Bypass -File .\install.ps1`.
- **Existing customisations overwritten**: there is no merge — re-apply your changes after install. Consider keeping local edits in a separate fork of this repo.
