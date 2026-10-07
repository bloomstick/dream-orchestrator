<#
.SYNOPSIS
    Bounded parallel fan-out: runs one Invoke-Dispatch per issue as a child job with heartbeat.

.DESCRIPTION
    Attended-only: run by the Architect inside a live session. NEVER scheduled.
    FORBIDDEN: no schedules, services, watchers, polling loops, background persistence.
    Single-issue Invoke-Dispatch.ps1 is the only worker-runner (no logic fork):
    this script only starts one `-IssueNumber` dispatch per issue number as a
    PowerShell child job, heartbeats on a bounded wait loop, then collects each
    job's output on completion. Landing discipline is unchanged: workers push
    branches only, the human merges sequentially, Close-Shipped.ps1 finishes.
    Bounded-attendance exception (same category as Wait-IssuesClosed.ps1 and
    merge-queue waits): jobs are children of this live session, every $Poll
    seconds prints a WAIT line, nothing survives past exit (timeout stops jobs).

.PARAMETER TargetRepo
    Path to target repo. Required unless -DryRun. Passed through to each dispatch.

.PARAMETER IssueNumbers
    Int list of issues to dispatch (explicit claim per issue). Required.

.PARAMETER Prompts
    Hashtable mapping issue number -> worker prompt markdown path, e.g.
    @{ 4 = "C:\tmp\worker-p-4.md"; 5 = "C:\tmp\worker-p-5.md" }.
    Every number in -IssueNumbers must have an entry whose file exists.

.PARAMETER ReportDir
    Directory for per-issue report files (dispatch-report-<N>.md). Default ""
    resolves to ([IO.Path]::GetTempPath()). Explicit -ReportFile is not
    supported here: per-issue files are what make concurrent runs safe.

.PARAMETER Timeout
    Cap in seconds for the whole fan-out. Default 3600. Elapsed >= Timeout with
    jobs still running stops the jobs, keeps worktrees for diagnosis, exits 1.

.PARAMETER Poll
    Heartbeat interval in seconds. Default 15.

.PARAMETER Draft
    Switch. Passed through to each dispatch (draft PR handoff). Default absent
    creates ready-for-review PRs.

.PARAMETER DryRun
    Switch. Prints the fan-out plan (one line per issue), exits 0. Starts no
    jobs, mutates nothing.

.EXAMPLE
    .\Invoke-Fanout.ps1 -TargetRepo <path> -IssueNumbers 4,5 -Prompts @{ 4 = "C:\tmp\w4.md"; 5 = "C:\tmp\w5.md" } -DryRun

.NOTES
    Exit codes:
      0     - ALL-DONE: every dispatch job completed without throw.
      1     - TIMEOUT: cap reached (running jobs stopped, worktrees kept).
      non-0 - Terminating error (throw): bad flags, missing prompt entry/file,
              or at least one dispatch job failed (failed numbers listed;
              per-issue fix path is request-fix + re-dispatch of that issue only).
#>
# Invoke-Fanout.ps1 - bounded parallel fan-out over Invoke-Dispatch.ps1.
# Attended-only: run by the Architect inside a live session. NEVER scheduled.
param(
  [string]$TargetRepo = "",
  [int[]]$IssueNumbers = @(),
  [hashtable]$Prompts = @{},
  [string]$ReportDir = "",
  [int]$Timeout = 3600,
  [int]$Poll = 15,
  [switch]$Draft,
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"

if ($Timeout -lt 0) { throw "Timeout must be >= 0 seconds" }
if ($Poll -le 0) { throw "Poll must be > 0 seconds" }
if ($IssueNumbers.Count -eq 0) { throw "pass -IssueNumbers <n,...> (explicit set required)" }
if ($TargetRepo -eq "" -and -not $DryRun) { throw "pass -TargetRepo <path-to-target-repo>" }

$ScriptDir = $PSScriptRoot
$DispatchScript = (Join-Path $ScriptDir "Invoke-Dispatch.ps1")
$OutDir = $ReportDir
if ($OutDir -eq "") { $OutDir = ([IO.Path]::GetTempPath()) }

foreach ($N in $IssueNumbers) {
  $Key = "$N"
  if (-not $Prompts.ContainsKey($N) -and -not $Prompts.ContainsKey($Key)) {
    throw ("no prompt for issue #{0} (pass -Prompts @{{ {0} = <path> }})" -f $N)
  }
  $P = $Prompts[$N]
  if ($null -eq $P) { $P = $Prompts[$Key] }
  if (-not (Test-Path "$P")) { throw ("prompt file missing for issue #{0}: {1}" -f $N, $P) }
}

if ($DryRun) {
  foreach ($N in $IssueNumbers) {
    $P = $Prompts[$N]
    if ($null -eq $P) { $P = $Prompts["$N"] }
    $R = (Join-Path $OutDir ("dispatch-report-{0}.md" -f $N))
    $Kind = "ready"
    if ($Draft) { $Kind = "draft" }
    Write-Output ("DRY FANOUT: issue #{0} prompt={1} report={2} pr={3} (no mutate)" -f $N, $P, $R, $Kind)
  }
  Write-Output "DRY DONE: fan-out plan shown, no jobs started"
  exit 0
}

$Jobs = @()
foreach ($N in $IssueNumbers) {
  $P = $Prompts[$N]
  if ($null -eq $P) { $P = $Prompts["$N"] }
  $R = (Join-Path $OutDir ("dispatch-report-{0}.md" -f $N))
  Write-Output ("FANOUT: starting dispatch job for issue #{0}" -f $N)
  $Jobs += Start-Job -Name ("dispatch-{0}" -f $N) -ScriptBlock {
    param($D, $T, $I, $Wp, $Rp, $Dr)
    $DispatchArgs = @("-TargetRepo", $T, "-IssueNumber", $I, "-WorkerPrompt", $Wp, "-ReportFile", $Rp)
    if ($Dr) { $DispatchArgs += "-Draft" }
    & $D @DispatchArgs
  } -ArgumentList $DispatchScript, $TargetRepo, $N, "$P", $R, ([bool]$Draft)
}

$Pending = @($IssueNumbers)
$JobState = @{}
$Watch = [Diagnostics.Stopwatch]::StartNew()
while ($Pending.Count -gt 0) {
  $Finished = @(Get-Job | Where-Object {
    ($_.Name -match "^dispatch-(\d+)$") -and ([int]$Matches[1] -in $Pending) -and ($_.State -ne "Running")
  })
  foreach ($J in $Finished) {
    $JN = [int]($J.Name -replace "^dispatch-", "")
    $JobState["$JN"] = ("{0}" -f $J.State)
    Write-Output ("===== issue #{0} job {1} =====" -f $JN, $J.State)
    Receive-Job $J
    Remove-Job $J
    $Pending = @($Pending | Where-Object { $_ -ne $JN })
  }
  if ($Pending.Count -eq 0) { break }
  $Elapsed = [int]$Watch.Elapsed.TotalSeconds
  if ($Elapsed -ge $Timeout) {
    Get-Job | Where-Object { $_.State -eq "Running" } | Stop-Job
    Write-Output ("TIMEOUT: still running [{0}] after {1}s cap (exit 1, worktrees kept for diagnosis)" -f ($Pending -join ","), $Elapsed)
    exit 1
  }
  Write-Output ("WAIT: running=[{0}] elapsed={1}s timeout={2}s poll={3}s" -f ($Pending -join ","), $Elapsed, $Timeout, $Poll)
  Start-Sleep -Seconds $Poll
}

$Failed = @()
foreach ($N in $IssueNumbers) {
  if ($JobState["$N"] -ne "Completed") { $Failed += $N }
}
if ($Failed.Count -gt 0) {
  throw ("fan-out incomplete, failed issues [{0}] (request-fix + re-dispatch those only; worktrees kept)" -f ($Failed -join ","))
}
Write-Output ("ALL-DONE: dispatches finished for issues [{0}]" -f ($IssueNumbers -join ","))
