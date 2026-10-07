<#
.SYNOPSIS
    Bounded one-shot waiter: blocks until a set of GitHub issues is closed.

.DESCRIPTION
    Attended-only bounded exception to the no-watcher / no-polling-loop rule
    (see docs/attended-only-decision.md): a foreground, one-shot wait with a
    mandatory -Timeout cap and a -Poll interval, same category as merge-queue
    waits. It performs no scheduling, installs no service, spawns no daemon,
    and persists nothing past exit.
    Loop: query open issues, print a heartbeat line per poll (count +
    elapsed), empty watch set = print ALL-CLOSED and exit 0, cap reached =
    exit 1. Native calls are judged by $LASTEXITCODE explicitly (same
    contract as the repo INSTALL / run scripts).

.PARAMETER Timeout
    Cap in seconds for the whole wait. Default 3600. Elapsed >= Timeout with
    issues still open prints TIMEOUT and exits 1. The loop never runs without
    this cap.

.PARAMETER Poll
    Interval in seconds between open-issue queries. Default 30. Every sleep
    honors this value; there is no fixed-interval sleep anywhere.

.PARAMETER IssueNumbers
    Int list to watch. Required outside -DryRun (throw when empty).
    In -DryRun, empty means list all open issues once. An
    explicit number that is already closed (or does not exist) simply never
    appears in the remaining set.

.PARAMETER DryRun
    Switch. Lists the watch set once, prints DRY WATCH lines, exits 0.
    Never sleeps, never waits.

.PARAMETER Repo
    Optional "owner/name". Default "" resolves the repo from the current
    directory (gh default). Passed through as --repo only when non-empty.

.EXAMPLE
    .\Wait-IssuesClosed.ps1 -DryRun
    Lists all open issues in the cwd-resolved repo, exits 0.

.EXAMPLE
    .\Wait-IssuesClosed.ps1 -IssueNumbers 12,13 -Timeout 600 -Poll 15
    Waits up to 600s for issues #12 and #13 to close, polling every 15s.

.NOTES
    Exit codes:
      0     - ALL-CLOSED: watch set empty (or -DryRun listed the set).
      1     - TIMEOUT: cap reached with issues still open (fail-sharp).
      non-0 - Terminating error (throw): bad flags, missing -IssueNumbers
              outside -DryRun, or the gh open-issue
              query itself failed (judged by $LASTEXITCODE, $null = 0).
#>
# Wait-IssuesClosed.ps1 - bounded one-shot issue-close waiter.
# Foreground only. No schedules, no services, no daemons, no persistence.
# Usage:
#   .\Wait-IssuesClosed.ps1 [-Timeout 3600] [-Poll 30] [-IssueNumbers 12,13] [-DryRun] [-Repo owner/name]
param(
  [int]$Timeout = 3600,
  [int]$Poll = 30,
  [int[]]$IssueNumbers = @(),
  [switch]$DryRun,
  [string]$Repo = ""
)
$ErrorActionPreference = "Stop"

if ($Timeout -lt 0) { throw "Timeout must be >= 0 seconds" }
if ($Poll -le 0) { throw "Poll must be > 0 seconds" }

$RepoArgs = @()
if ($Repo -ne "") { $RepoArgs = @("--repo", $Repo) }

function Get-RemainingOpen {
  $Raw = & gh issue list --state open --json number --limit 1000 --jq ".[].number" @RepoArgs
  $Code = $LASTEXITCODE
  if ($null -eq $Code) { $Code = 0 }
  if ($Code -ne 0) { throw ("query failed: gh issue list exited {0}" -f $Code) }
  $Open = @()
  foreach ($Line in @($Raw)) {
    $T = ("$Line").Trim()
    if ($T -ne "") { $Open += [int]$T }
  }
  if ($IssueNumbers.Count -gt 0) {
    $Remaining = @()
    foreach ($N in $IssueNumbers) {
      if ($Open -contains $N) { $Remaining += $N }
    }
    return $Remaining
  }
  return $Open
}

if ($DryRun) {
  $Watched = @(Get-RemainingOpen)
  if ($IssueNumbers.Count -gt 0) {
    Write-Output ("DRY WATCH: explicit issues [{0}]" -f ($IssueNumbers -join ","))
  } else {
    Write-Output "DRY WATCH: all open issues"
  }
  if ($Watched.Count -eq 0) {
    Write-Output "DRY WATCH: none open (no wait, exit 0)"
  } else {
    foreach ($N in $Watched) { Write-Output ("DRY WATCH: #{0} open" -f $N) }
  }
  exit 0
}

if ($IssueNumbers.Count -eq 0) { throw "pass -IssueNumbers <n,...> (explicit watch set required outside -DryRun)" }

$Watch = [Diagnostics.Stopwatch]::StartNew()
while ($true) {
  $Remaining = @(Get-RemainingOpen)
  $Elapsed = [int]$Watch.Elapsed.TotalSeconds
  if ($Remaining.Count -eq 0) {
    Write-Output ("ALL-CLOSED: no open issues remain (elapsed {0}s)" -f $Elapsed)
    exit 0
  }
  if ($Elapsed -ge $Timeout) {
    Write-Output ("TIMEOUT: still open [{0}] after {1}s cap (exit 1)" -f ($Remaining -join ","), $Elapsed)
    exit 1
  }
  Write-Output ("WAIT: open={0} issues=[{1}] elapsed={2}s timeout={3}s poll={4}s" -f $Remaining.Count, ($Remaining -join ","), $Elapsed, $Timeout, $Poll)
  Start-Sleep -Seconds $Poll
}
