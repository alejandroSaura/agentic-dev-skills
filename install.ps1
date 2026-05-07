# Installs the agentic-dev-skills bundle into the user-global Claude Code locations.
# Run from the repo root: .\install.ps1
#
# Source:
#   .\.claude\commands\*  ->  $env:USERPROFILE\.claude\commands\
#   .\.agentic\*          ->  $env:USERPROFILE\.agentic\
#
# Existing files at the destination are overwritten. Back up first if you have customisations.

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcCommands = Join-Path $repoRoot ".claude\commands"
$srcAgentic = Join-Path $repoRoot ".agentic"

if (-not (Test-Path $srcCommands)) {
    Write-Error "Source missing: $srcCommands. Are you running this from the repo root?"
    exit 1
}
if (-not (Test-Path $srcAgentic)) {
    Write-Error "Source missing: $srcAgentic. Are you running this from the repo root?"
    exit 1
}

$dstCommands = Join-Path $env:USERPROFILE ".claude\commands"
$dstAgentic = Join-Path $env:USERPROFILE ".agentic"

New-Item -ItemType Directory -Force -Path $dstCommands | Out-Null
New-Item -ItemType Directory -Force -Path $dstAgentic | Out-Null

Write-Host "Copying $srcCommands\* -> $dstCommands\"
Copy-Item -Recurse -Force -Path (Join-Path $srcCommands "*") -Destination $dstCommands

Write-Host "Copying $srcAgentic\* -> $dstAgentic\"
Copy-Item -Recurse -Force -Path (Join-Path $srcAgentic "*") -Destination $dstAgentic

Write-Host ""
Write-Host "Installed."
Write-Host "Skills: agentic-dev, adversarial-review-plan, adversarial-review-roadmap, roadmap-runner, review-feature-phase"
Write-Host "Restart Claude Code (or open a new session) for the harness to pick them up."
