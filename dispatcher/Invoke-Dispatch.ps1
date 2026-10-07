<#
.SYNOPSIS
    On-demand attended dispatcher: claims oldest ready issue, runs worker in target-repo worktree, comments report, moves label to in-review.

.DESCRIPTION
    Attended-only: run by the Architect inside a live session. NEVER scheduled.
    FORBIDDEN: no schedules, services, watchers, polling loops, background persistence.
    Flow: oldest ready issue in TARGET repo -> worktree+branch there ->
      opencode run (foreground streaming; background only with notify-on-completion) ->
      comment report on issue, set next label, verify child processes dead.
    No behavior changes in this help update; comments only.

.PARAMETER TargetRepo
    Path to target repo for `git -C <TargetRepo> worktree add`. Required unless -DryRun.
    Implementation: if ($TargetRepo -eq "" -and -not $DryRun) { throw "pass -TargetRepo <path-to-target-repo>" }.

.PARAMETER IssueNumber
    Issue number to claim in the TARGET repo. Default 0 = auto-claim oldest ready via
    `gh issue list --label "ready" --state open --json number,createdAt --jq "sort_by(.createdAt)[0].number"`.
    All `gh issue` operations run against the TARGET repo (the working repo) — never the orchestrator checkout.
    In -DryRun, 0 is coerced to 999 ($Number = 999). Otherwise parsed from gh output via [int]$Raw.Trim().Trim('"').

.PARAMETER WorkerPrompt
    Path to worker prompt markdown. Default "" resolves to <orchestrator>/prompts\worker-prompt.md.
    Consumed via Get-Content -Raw then `opencode run <PromptText>` after Push-Location to worktree dir.

.PARAMETER ReportFile
    Path to markdown report posted via `gh issue comment <Number> --body-file <ReportFile>`.
    Default "" resolves to Join-Path ([IO.Path]::GetTempPath()) "dispatch-report.md".

.PARAMETER DryRun
    Switch. When present: prints DRY CLAIM / DRY RUN worktree+branch (feat/p-<N>-worker) /
    DRY RUN opencode run / optional DRY NOTIFY / DRY COMMENT / DRY LABEL, calls Confirm-QuietShip,
    prints DRY DONE, then `exit 0`. No gh/git/opencode mutations.

.PARAMETER Background
    Switch. Foreground streaming by default. Background only with notify-on-completion:
    requires -NotifyCommand non-empty, else throw. Implementation only logs
    "RUN: background mode, notify=<NotifyCommand>"; the notify command itself is not invoked here.

.PARAMETER NotifyCommand
    Completion-notify command string used with -Background. Default "". Logged in DRY NOTIFY and RUN paths.

.EXAMPLE
    .\Invoke-Dispatch.ps1 -TargetRepo C:\my\projects\dream-monorepo [-IssueNumber 0] [-DryRun]
    Auto-claim oldest ready issue in target repo, create worktree+branch there, stream worker.

.EXAMPLE
    .\Invoke-Dispatch.ps1 -DryRun
    No -TargetRepo needed; simulates claim->run->comment->label for issue #999 and exits 0.

.EXAMPLE
    .\Invoke-Dispatch.ps1 -TargetRepo C:\my\projects\dream-monorepo -IssueNumber 12 -Background -NotifyCommand "msg done"
    Foreground gating example: allows background flag only because notify string is supplied.

.NOTES
    Exit codes (matches implementation line-for-line; only explicit `exit 0` is in the DryRun path,
    all failures are terminating throw -> non-zero host exit):
      0       - Success: DryRun path reached `exit 0` (DRY DONE); or non-DryRun path completed
                CLAIM -> RUN -> COMMENT -> label in-review -> Confirm-QuietShip -> DONE without throw.
      non-0   - Terminating error (throw). Mapping by throw site:
                * "background only with notify-on-completion: pass -NotifyCommand or run foreground"
                  - (-Background with empty -NotifyCommand).
                * "pass -TargetRepo <path-to-target-repo>" - (-TargetRepo empty without -DryRun).
                * "stop-at-ship violated: child processes alive" - (Confirm-QuietShip found
                  Get-Job -State Running or child opencode|gh|git(.exe) under $PID).
                * "no ready issues found" - (`gh issue list --label ready` non-zero exit or empty output
                  when -IssueNumber 0 and not -DryRun).
                * "claim failed" - (`gh issue edit <N> --remove-label ready --add-label in-progress` non-zero).
                * "worktree add failed" - (`git -C <TargetRepo> worktree add <WorkDir> -b feat/p-<N>-worker` non-zero).
                * "worker exited non-zero" - (`opencode run <PromptText>` non-zero).
                * "comment failed" - (`gh issue comment <N> --body-file <ReportFile>` non-zero).
                * "label transition failed" - (`gh issue edit <N> --remove-label in-progress --add-label in-review` non-zero).
                Plus any propagated host/cmdlet error (e.g. Get-Content on missing -WorkerPrompt,
                Push-Location/Pop-Location, Get-CimInstance) under $ErrorActionPreference = "Stop".
#>
# Invoke-Dispatch.ps1 - on-demand dispatcher skeleton.
# Attended-only: run by the Architect inside a live session. NEVER scheduled.
# FORBIDDEN: no schedules, services, watchers, polling loops, background persistence.
# Flow: oldest ready issue in TARGET repo -> worktree+branch there -> opencode run
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

# Issues live in the TARGET repo (the working repo). gh resolves its repo from the
# current directory, so the live section runs with the TARGET repo as CWD —
# never the orchestrator checkout (scripts only, no work items there).
Push-Location $TargetRepo
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
