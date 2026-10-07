# Invoke-Dispatch.ps1 - on-demand dispatcher skeleton.
# Attended-only: run by the Architect inside a live session. NEVER scheduled.
# FORBIDDEN: no schedules, services, watchers, polling loops, background persistence.
# Flow: oldest ready issue -> worktree+branch in TARGET repo -> opencode run
#   (foreground streaming; background only with notify-on-completion) ->
#   comment report on issue, set next label, verify child processes dead.
# Usage:
#   .\Invoke-Dispatch.ps1 -TargetRepo C:\my\projects\dream-monorepo [-IssueNumber 0] [-DryRun]
param(
  [string]$TargetRepo = "",
  [int]$IssueNumber = 0,
  [string]$WorkerPrompt = "",
  [string]$ReportFile = "",
  [switch]$DryRun,
  [switch]$Background,
  [string]$NotifyCommand = ""
)
$ErrorActionPreference = "Stop"

if ($Background -and $NotifyCommand -eq "") {
  throw "background only with notify-on-completion: pass -NotifyCommand or run foreground"
}
if ($TargetRepo -eq "" -and -not $DryRun) { throw "pass -TargetRepo <path-to-target-repo>" }

function Confirm-QuietShip {
  $Jobs = @(Get-Job -State Running -ErrorAction SilentlyContinue)
  $Kids = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $PID) -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(opencode|gh|git)(\.exe)?$" })
  Write-Output ("SHIP-CHECK: running jobs={0} child worker procs={1}" -f $Jobs.Count, $Kids.Count)
  if ($Jobs.Count -gt 0 -or $Kids.Count -gt 0) { throw "stop-at-ship violated: child processes alive" }
  Write-Output "SHIP-CHECK: PROCESS TABLE EMPTY (no dispatcher children, no running jobs)"
}

$ScriptDir = $PSScriptRoot
$OrchestratorDir = Split-Path $ScriptDir -Parent
if ($WorkerPrompt -eq "") { $WorkerPrompt = (Join-Path $OrchestratorDir "prompts\worker-prompt.md") }
if ($ReportFile -eq "") { $ReportFile = (Join-Path ([IO.Path]::GetTempPath()) "dispatch-report.md") }

$Number = $IssueNumber
if ($DryRun -and $Number -eq 0) { $Number = 999 }

if ($DryRun) {
  Write-Output ("DRY CLAIM: issue #{0} ready -> in-progress (gh issue edit, no mutate in dry-run)" -f $Number)
  Write-Output ("DRY RUN: worktree+branch in TARGET repo for issue #{0} (git worktree add -b feat/p-{0}-worker)" -f $Number)
  Write-Output ("DRY RUN: opencode run foreground streaming with prompt {0}" -f $WorkerPrompt)
  if ($Background) { Write-Output ("DRY NOTIFY: would run notify: {0}" -f $NotifyCommand) }
  Write-Output ("DRY COMMENT: report {0} -> issue #{1} comment (gh issue comment, no mutate)" -f $ReportFile, $Number)
  Write-Output ("DRY LABEL: issue #{0} in-progress -> in-review (gh issue edit, no mutate)" -f $Number)
  Confirm-QuietShip
  Write-Output ("DRY DONE: claim->run->comment->label transitions shown, processes empty")
  exit 0
}

Push-Location $OrchestratorDir
try {
  if ($Number -eq 0) {
    Write-Output "CLAIM: listing oldest ready issue"
    $Raw = & gh issue list --label "ready" --state open --json number,createdAt --jq "sort_by(.createdAt)[0].number"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Raw)) { throw "no ready issues found" }
    $Number = [int]$Raw.Trim().Trim('"')
  }
  Write-Output ("CLAIM: issue #{0} ready -> in-progress" -f $Number)
  & gh issue edit $Number --remove-label "ready" --add-label "in-progress"
  if ($LASTEXITCODE -ne 0) { throw "claim failed" }

  $Branch = ("feat/p-{0}-worker" -f $Number)
  $WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("work-p-{0}" -f $Number))
  Write-Output ("RUN: worktree+branch {0} at {1}" -f $Branch, $WorkDir)
  & git -C $TargetRepo worktree add $WorkDir -b $Branch
  if ($LASTEXITCODE -ne 0) { throw "worktree add failed" }

  Write-Output ("RUN: opencode run foreground streaming prompt={0}" -f $WorkerPrompt)
  if ($Background) {
    Write-Output ("RUN: background mode, notify={0}" -f $NotifyCommand)
  }
  $PromptText = Get-Content $WorkerPrompt -Raw
  Push-Location $WorkDir
  try {
    & opencode run $PromptText
    if ($LASTEXITCODE -ne 0) { throw "worker exited non-zero" }
  } finally {
    Pop-Location
  }

  Write-Output ("COMMENT: report {0} -> issue #{1}" -f $ReportFile, $Number)
  & gh issue comment $Number --body-file $ReportFile
  if ($LASTEXITCODE -ne 0) { throw "comment failed" }
  & gh issue edit $Number --remove-label "in-progress" --add-label "in-review"
  if ($LASTEXITCODE -ne 0) { throw "label transition failed" }

  Confirm-QuietShip
  Write-Output ("DONE: issue #{0} in-review, ship quiet" -f $Number)
} finally {
  Pop-Location
}
