<#
.SYNOPSIS
    Post-merge closer: waits for issues to close, then labels done, prunes worktrees.

.DESCRIPTION
    Attended-only: run by the Architect inside a live session right after firing
    dispatches, to continue automatically once the human merges and closes.
    NEVER scheduled. FORBIDDEN: no schedules, services, watchers, polling loops,
    background persistence. Flow: bounded wait via Wait-IssuesClosed.ps1
    (explicit -IssueNumbers, -Timeout/-Poll caps, heartbeat lines) -> per issue:
    read merge SHA (merged feat/p-<N>-worker branch, or UNMERGED note), label
    in-review -> done, comment "Shipped <sha>. Silence confirmed below.",
    close if still open -> fetch origin in TargetRepo, prune work-p-<N>
    worktree -> final quiet check. Implements runbook step 4 (close), which the
    single-issue dispatcher does NOT perform on its own.

.PARAMETER TargetRepo
    Path to target repo for fetch + worktree prune. Required unless -DryRun.

.PARAMETER IssueNumbers
    Int list to watch and close. Required (explicit set, never default-all).

.PARAMETER Timeout
    Cap in seconds for the close-wait. Default 3600. Passed to Wait-IssuesClosed.

.PARAMETER Poll
    Heartbeat interval in seconds. Default 30. Passed to Wait-IssuesClosed.

.PARAMETER Repo
    Optional "owner/name" passed through to gh as --repo. Default "" resolves
    the repo from the current directory.

.PARAMETER DryRun
    Switch. Prints the close plan (one line per issue), exits 0. Waits for
    nothing, mutates nothing.

.EXAMPLE
    .\Close-Shipped.ps1 -TargetRepo <target-repo-path> -IssueNumbers 4,5 -Timeout 600 -Poll 15
    Waits up to 600s for #4 and #5 to close, then finishes the close procedure.

.NOTES
    Exit codes:
      0     - SHIP-CLOSED: waiter saw ALL-CLOSED and every close step finished.
      1     - TIMEOUT: waiter cap reached, or any close step failed (fail-sharp
              with the issue number and step; worktrees kept for diagnosis).
#>
# Close-Shipped.ps1 - bounded post-merge closer for dispatched issues.
# Attended-only: run by the Architect inside a live session. NEVER scheduled.
param(
  [string]$TargetRepo = "",
  [int[]]$IssueNumbers = @(),
  [int]$Timeout = 3600,
  [int]$Poll = 30,
  [string]$Repo = "",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"

if ($Timeout -lt 0) { throw "Timeout must be >= 0 seconds" }
if ($Poll -le 0) { throw "Poll must be > 0 seconds" }
if ($IssueNumbers.Count -eq 0) { throw "pass -IssueNumbers <n,...> (explicit watch set required)" }
if ($TargetRepo -eq "" -and -not $DryRun) { throw "pass -TargetRepo <path-to-target-repo>" }

$ScriptDir = $PSScriptRoot
$Waiter = (Join-Path $ScriptDir "Wait-IssuesClosed.ps1")
$RepoArgs = @()
if ($Repo -ne "") { $RepoArgs = @("--repo", $Repo) }

if ($DryRun) {
  foreach ($N in $IssueNumbers) {
    Write-Output ("DRY CLOSE: issue #{0} wait-closed -> label done -> comment shipped -> prune work-p-{0} (no mutate)" -f $N)
  }
  Write-Output "DRY DONE: close plan shown, nothing waited, nothing mutated"
  exit 0
}

Write-Output ("CLOSE-WAIT: arming bounded wait for issues [{0}]" -f ($IssueNumbers -join ","))
& $Waiter -IssueNumbers $IssueNumbers -Timeout $Timeout -Poll $Poll -Repo $Repo
if ($LASTEXITCODE -ne 0) { throw ("close-wait failed (timeout or query error) for issues [{0}]" -f ($IssueNumbers -join ",")) }

Push-Location $TargetRepo
try {
  # Canonical label set lives in templates/Sync-Labels.ps1 (single source):
  # ensure `done` etc. exist before applying them. CWD is the target repo,
  # so an empty -Repo still resolves there.
  $SyncScript = (Join-Path (Split-Path $ScriptDir -Parent) "templates\Sync-Labels.ps1")
  if ($Repo -ne "") { & $SyncScript -Repo $Repo } else { & $SyncScript }
  if ($LASTEXITCODE -ne 0) { throw "close failed: label sync" }

  foreach ($N in $IssueNumbers) {
    $Branch = ("feat/p-{0}-worker" -f $N)
    $StateRaw = & gh issue view $N --json state @RepoArgs --jq ".state"
    if ($LASTEXITCODE -ne 0) { throw ("close failed: cannot read issue #{0}" -f $N) }
    $State = ("$StateRaw").Trim().Trim('"')

    $ShaRaw = & gh pr list --head $Branch --state merged --json mergeCommit @RepoArgs --jq ".[0].mergeCommit.oid"
    if ($LASTEXITCODE -ne 0) { throw ("close failed: cannot read merged PR for issue #{0}" -f $N) }
    $Sha = ("$ShaRaw").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($Sha) -or $Sha -eq "null") { $Sha = "UNMERGED" }
    Write-Output ("CLOSE: issue #{0} state={1} ship={2}" -f $N, $State, $Sha)

    & gh issue edit $N --remove-label "in-review" --add-label "done" @RepoArgs
    if ($LASTEXITCODE -ne 0) { throw ("close failed: label done for issue #{0}" -f $N) }

    $ShipFile = (Join-Path ([IO.Path]::GetTempPath()) ("shipped-{0}.md" -f $N))
    [IO.File]::WriteAllText($ShipFile, ("Shipped {0}. Silence confirmed below." -f $Sha), (New-Object Text.UTF8Encoding $false))
    & gh issue comment $N --body-file $ShipFile @RepoArgs
    if ($LASTEXITCODE -ne 0) { throw ("close failed: shipped comment for issue #{0}" -f $N) }

    if ($State -ne "CLOSED") {
      & gh issue close $N @RepoArgs
      if ($LASTEXITCODE -ne 0) { throw ("close failed: closing issue #{0}" -f $N) }
    }
  }

  & git -C $TargetRepo fetch origin
  if ($LASTEXITCODE -ne 0) { throw "close failed: git fetch origin" }
  $MainSha = & git -C $TargetRepo rev-parse origin/main
  if ($LASTEXITCODE -ne 0) { $MainSha = "unknown" }
  Write-Output ("CLOSE: origin/main at {0}" -f ("$MainSha").Trim())

  foreach ($N in $IssueNumbers) {
    $WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("work-p-{0}" -f $N))
    $Listed = & git -C $TargetRepo worktree list --porcelain
    if (("$Listed") -match [regex]::Escape("$WorkDir")) {
      & git -C $TargetRepo worktree remove --force $WorkDir
      if ($LASTEXITCODE -ne 0) { throw ("close failed: pruning worktree for issue #{0}" -f $N) }
      Write-Output ("CLOSE: pruned worktree {0}" -f $WorkDir)
    } else {
      Write-Output ("CLOSE: worktree already gone for issue #{0}" -f $N)
    }
  }
  & git -C $TargetRepo worktree prune
} finally {
  Pop-Location
}

$Jobs = @(Get-Job -State Running -ErrorAction SilentlyContinue)
if ($Jobs.Count -gt 0) { throw "stop-at-ship violated: running jobs remain" }
Write-Output ("SHIP-CLOSED: issues [{0}] done, worktrees pruned, no running jobs" -f ($IssueNumbers -join ","))
