#!/usr/bin/env bash
# Installs the agentic-dev-skills bundle into the user-global Claude Code locations.
# Run from the repo root: ./install.sh
#
# Source:
#   ./.claude/commands/*  ->  $HOME/.claude/commands/
#   ./.agentic/*          ->  $HOME/.agentic/
#
# Existing files at the destination are overwritten. Back up first if you have customisations.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src_commands="$repo_root/.claude/commands"
src_agentic="$repo_root/.agentic"

if [ ! -d "$src_commands" ]; then
  echo "Source missing: $src_commands. Are you running this from the repo root?" >&2
  exit 1
fi
if [ ! -d "$src_agentic" ]; then
  echo "Source missing: $src_agentic. Are you running this from the repo root?" >&2
  exit 1
fi

dst_commands="$HOME/.claude/commands"
dst_agentic="$HOME/.agentic"

mkdir -p "$dst_commands" "$dst_agentic"

echo "Copying $src_commands/* -> $dst_commands/"
cp -r "$src_commands/." "$dst_commands/"

echo "Copying $src_agentic/* -> $dst_agentic/"
cp -r "$src_agentic/." "$dst_agentic/"

echo
echo "Installed."
echo "Skills: agentic-dev, adversarial-review-plan, adversarial-review-roadmap, roadmap-runner, review-feature-phase"
echo "Restart Claude Code (or open a new session) for the harness to pick them up."
