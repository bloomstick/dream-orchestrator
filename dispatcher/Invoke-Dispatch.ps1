<#
.SYNOPSIS
    On-demand attended dispatcher: claims oldest ready issue, runs worker in target-repo worktree, comments report, opens PR, moves label to in-review.

.DESCRIPTION
    Attended-only: run by the Architect inside a live session. NEVER scheduled.
    FORBIDDEN: no schedules, services, watchers, polling loops, background persistence.
    Flow: oldest ready issue in TARGET repo -> worktree+branch there ->
      live issue body fetched at claim (single source of scope) ->
      opencode run (foreground streaming; background only with notify-on-completion) ->
      sanitize report to UTF-8, split human-report block (visible) from transcript
      (collapsed details), comment both on issue, verify branch exists
      on origin, open PR (ready by default, -Draft for draft;
      --head <branch> --base main, body per templates/pull-request.md
      with Closes: #<n>, What from the human report, title = trailing
      task-code line of the report), set next label,
      verify child processes dead. NEVER merges, NEVER pushes main.

.PARAMETER TargetRepo
    Path to target repo for `git -C <TargetRepo> worktree add`. Required unless -DryRun.
    Implementation: if ($TargetRepo -eq "" -and -not $DryRun) { throw "pass -TargetRepo <path-to-target-repo>" }.

.PARAMETER IssueNumber
    Issue number to claim in the TARGET repo. Default 0 = auto-claim oldest ready via
    `gh issue list --label "ready" --state open --json number,createdAt --jq "sort_by(.createdAt)[0].number"`.
    All `gh issue` operations run against the TARGET repo (the working repo) - never the orchestrator checkout.
    In -DryRun, 0 is coerced to 999 ($Number = 999). Otherwise parsed from gh output via [int]$Raw.Trim().Trim('"').
    Explicit non-zero normalizes labels (clears ready and needs-fix, adds in-progress) for
    request-fix re-dispatch; auto-claim (0) clears ready only and is unchanged.

.PARAMETER WorkerPrompt
    Path to worker prompt markdown. Default "" resolves to <orchestrator>/prompts\worker-prompt.md.
    Consumed via Get-Content -Raw then `opencode run <PromptText>` after Push-Location to worktree dir.

.PARAMETER ReportFile
    Path to markdown report posted via `gh issue comment <Number> --body-file <ReportFile>`.
    Default "" resolves per-issue to Join-Path ([IO.Path]::GetTempPath()) "dispatch-report-<N>.md"
    once the issue number is known (after claim; #999 in -DryRun), so concurrent
    dispatches of different issues never clobber each other's report.
    Worker stdout streams to console and is captured via Tee-Object to this path,
    then sanitized to UTF-8 without BOM with ANSI escapes stripped (Tee-Object
    writes UTF-16LE on Windows PowerShell 5.1, which GitHub renders as mojibake
    when posted raw), so COMMENT posts the real report.

.PARAMETER Draft
    Switch. When present, `gh pr create` gets --draft (draft PR handoff).
    Default (absent) creates a ready-for-review PR: merges stay the human's
    manual step either way, and the runbook judge verdict precedes any merge,
    so the draft gate is opt-in friction, not safety.

.PARAMETER DryRun
    Switch. When present: prints DRY CLAIM / DRY RUN worktree+branch (feat/p-<N>-worker) /
    DRY RUN opencode run / optional DRY NOTIFY / DRY COMMENT / DRY PR (branch-on-origin
    verify + gh pr create [--draft] --head <branch> --base main) / DRY LABEL,
    calls Confirm-QuietShip, prints DRY DONE, then `exit 0`. No gh/git/opencode mutations.

.PARAMETER Background
    Switch. Foreground streaming by default. Background only with notify-on-completion:
    requires -NotifyCommand non-empty, else throw. Implementation only logs
    "RUN: background mode, notify=<NotifyCommand>"; the notify command itself is not invoked here.

.PARAMETER NotifyCommand
    Completion-notify command string used with -Background. Default "". Logged in DRY NOTIFY and RUN paths.

.EXAMPLE
    .\Invoke-Dispatch.ps1 -TargetRepo <target-repo-path> [-IssueNumber 0] [-DryRun]
    Auto-claim oldest ready issue in target repo, create worktree+branch there, stream worker.

.EXAMPLE
    .\Invoke-Dispatch.ps1 -DryRun
    No -TargetRepo needed; simulates claim->run->comment->label for issue #999 and exits 0.

.EXAMPLE
    .\Invoke-Dispatch.ps1 -TargetRepo <target-repo-path> -IssueNumber 12 -Background -NotifyCommand "msg done"
    Foreground gating example: allows background flag only because notify string is supplied.

.NOTES
    Exit codes (matches implementation line-for-line; only explicit `exit 0` is in the DryRun path,
    all failures are terminating throw -> non-zero host exit):
      0       - Success: DryRun path reached `exit 0` (DRY DONE); or non-DryRun path completed
                CLAIM -> RUN -> COMMENT -> PR (ready, or draft with -Draft) -> label in-review -> Confirm-QuietShip -> DONE without throw.
      non-0   - Terminating error (throw). Mapping by throw site:
                * "background only with notify-on-completion: pass -NotifyCommand or run foreground"
                  - (-Background with empty -NotifyCommand).
                * "pass -TargetRepo <path-to-target-repo>" - (-TargetRepo empty without -DryRun).
                * "stop-at-ship violated: child processes alive" - (Confirm-QuietShip found
                  Get-Job -State Running or child opencode|gh|git(.exe) under $PID).
                * "no ready issues found" - (`gh issue list --label ready` non-zero exit or empty output
                  when -IssueNumber 0 and not -DryRun).
                * "claim failed" - (`gh issue edit` claim transition non-zero: auto-claim removes ready,
                  explicit removes ready and needs-fix, both add in-progress).
                * "worktree add failed" - (`git -C <TargetRepo> worktree add <WorkDir> -b feat/p-<N>-worker` non-zero).
                * "worker exited non-zero" - (`opencode run <PromptText>` non-zero).
                * "issue body fetch failed" - (`gh issue view <N> --json body` non-zero).
                * "comment failed" - (`gh issue comment <N> --body-file <ReportFile>` non-zero).
                * "pr verify failed: branch missing on origin" - (`git ls-remote --heads origin <Branch>`
                  non-zero, or empty output meaning the worker branch was never pushed; fail-sharp,
                  no PR attempted).
                * "pr create failed" - (`gh pr create [--draft] --head <Branch> --base main
                  --title <trailing-task-code-line> --body-file <PrBodyFile>` non-zero. Never merges,
                  never pushes main: no `gh pr merge`, no auto-merge flags anywhere in this file).
                * "label transition failed" - (`gh issue edit <N> --remove-label in-progress --add-label in-review` non-zero).
                Plus any propagated host/cmdlet error (e.g. Get-Content on missing -WorkerPrompt,
                Push-Location/Pop-Location, Get-CimInstance) under $ErrorActionPreference = "Stop".
#>
# Invoke-Dispatch.ps1 - on-demand dispatcher skeleton.
# Attended-only: run by the Architect inside a live session. NEVER scheduled.
# FORBIDDEN: no schedules, services, watchers, polling loops, background persistence.
# Flow: oldest ready issue in TARGET repo -> worktree+branch there -> fetch live
#   issue body (single source of scope) -> opencode run (foreground streaming;
#   background only with notify-on-completion) -> sanitize report (UTF-8,
#   no ANSI) -> comment human-report visible + transcript collapsed, verify
#   branch on origin, open PR (ready by default, -Draft for draft; never merge,
#   never push main), set next label, verify child processes dead.
# Usage:
#   .\Invoke-Dispatch.ps1 -TargetRepo <target-repo-path> [-IssueNumber 0] [-DryRun] [-Draft]
param(
  [string]$TargetRepo = "",
  [int]$IssueNumber = 0,
  [string]$WorkerPrompt = "",
  [string]$ReportFile = "",
  [switch]$Draft,
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

$Number = $IssueNumber
if ($DryRun -and $Number -eq 0) { $Number = 999 }

function Get-DefaultReportFile {
  param([int]$N)
  return (Join-Path ([IO.Path]::GetTempPath()) ("dispatch-report-{0}.md" -f $N))
}

function Convert-ReportToUtf8 {
  # Tee-Object writes UTF-16LE on Windows PowerShell 5.1; gh --body-file posts
  # bytes raw, so an unsanitized report lands on GitHub as NUL-mojibake.
  # Decode BOM-aware, strip ANSI CSI/OSC escapes and stray NULs, rewrite
  # UTF-8 without BOM (explicit .NET encoding: Out-File utf8 varies by PS version).
  param([string]$Path)
  $Raw = Get-Content $Path -Raw
  $Clean = [regex]::Replace("$Raw", "\x1b\[[0-9;?]*[A-Za-z]", "")
  $Clean = [regex]::Replace($Clean, "\x1b\][^\x07]*\x07", "")
  $Clean = $Clean -replace "\x00", ""
  [IO.File]::WriteAllText($Path, $Clean, (New-Object Text.UTF8Encoding $false))
}

function Get-HumanReport {
  # Visible part of the issue comment: the worker's final ```human-report
  # fence (plain prose). Returns "" when absent; the caller then falls back
  # to the trailing task-code line so old-style reports still post readable.
  param([string]$Path)
  $Text = Get-Content $Path -Raw
  $Ms = @([regex]::Matches("$Text", '(?ms)```human-report\s*\r?\n(.*?)\r?\n```'))
  if ($Ms.Count -eq 0) { return "" }
  return ($Ms[$Ms.Count - 1].Groups[1].Value.Trim())
}

function Get-ReportTitle {
  # The captured file holds streaming chatter ABOVE the final report, so the
  # title is the trailing task-code line (scanned from the end), not the first
  # non-empty line. Task codes look like P-hello-1 or M1a. Falls back to first
  # non-empty line, then the branch.
  param([string]$Path, [string]$Fallback)
  $Found = ""
  $AllLines = @(Get-Content $Path)
  for ($i = $AllLines.Count - 1; $i -ge 0; $i--) {
    $T = ("{0}" -f $AllLines[$i]).Trim()
    if ($T -match "^P-\S+\s" -or $T -match "^M\d+\S*\s") { $Found = $T; break }
  }
  if ([string]::IsNullOrWhiteSpace($Found)) {
    $Found = (@(Get-Content $Path) | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
  }
  if ([string]::IsNullOrWhiteSpace("$Found")) { $Found = $Fallback }
  return ("$Found").Trim()
}

if ($DryRun) {
  $ShowReport = $ReportFile
  if ($ShowReport -eq "") { $ShowReport = Get-DefaultReportFile -N $Number }
  $DraftFlag = ""
  if ($Draft) { $DraftFlag = " --draft" }
  Write-Output ("DRY CLAIM: issue #{0} ready -> in-progress (gh issue edit, no mutate in dry-run)" -f $Number)
  Write-Output ("DRY RUN: worktree+branch in TARGET repo for issue #{0} (git worktree add -b feat/p-{0}-worker)" -f $Number)
  Write-Output ("DRY RUN: opencode run foreground streaming with prompt {0}" -f $WorkerPrompt)
  if ($Background) { Write-Output ("DRY NOTIFY: would run notify: {0}" -f $NotifyCommand) }
  Write-Output ("DRY FETCH: live issue body for issue #{0} appended to prompt (gh issue view, no mutate)" -f $Number)
  Write-Output ("DRY SANITIZE: report -> UTF-8 no BOM, ANSI stripped (no mutate)")
  Write-Output ("DRY SPLIT: human-report block visible + transcript collapsed in details (no mutate)")
  Write-Output ("DRY COMMENT: report {0} -> issue #{1} comment (gh issue comment, no mutate)" -f $ShowReport, $Number)
  Write-Output ("DRY PR: verify branch feat/p-{0}-worker exists on origin (git ls-remote --heads, no mutate)" -f $Number)
  Write-Output ("DRY PR: gh pr create{0} --head feat/p-{1}-worker --base main --title <trailing-task-code-line> --body-file <pr-body-file> (no mutate, never merge)" -f $DraftFlag, $Number)
  Write-Output ("DRY LABEL: issue #{0} in-progress -> in-review (gh issue edit, no mutate)" -f $Number)
  Confirm-QuietShip
  Write-Output ("DRY DONE: claim->run->comment->pr->label transitions shown, processes empty")
  exit 0
}

# Issues live in the TARGET repo (the working repo). gh resolves its repo from the
# current directory, so the live section runs with the TARGET repo as CWD --
# never the orchestrator checkout (scripts only, no work items there).
Push-Location $TargetRepo
try {
  if ($Number -eq 0) {
    Write-Output "CLAIM: listing oldest ready issue"
    $Raw = & gh issue list --label "ready" --state open --json number,createdAt --jq "sort_by(.createdAt)[0].number"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Raw)) { throw "no ready issues found" }
    $Number = [int]$Raw.Trim().Trim('"')
  }
  if ($IssueNumber -ne 0) {
    Write-Output ("CLAIM: issue #{0} ready/needs-fix -> in-progress" -f $Number)
    & gh issue edit $Number --remove-label "ready,needs-fix" --add-label "in-progress"
  } else {
    Write-Output ("CLAIM: issue #{0} ready -> in-progress" -f $Number)
    & gh issue edit $Number --remove-label "ready" --add-label "in-progress"
  }
  if ($LASTEXITCODE -ne 0) { throw "claim failed" }

  if ($ReportFile -eq "") { $ReportFile = Get-DefaultReportFile -N $Number }

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
  Write-Output ("FETCH: live issue body for issue #{0} (single source of scope)" -f $Number)
  $IssueBody = & gh issue view $Number --json body --jq ".body"
  if ($LASTEXITCODE -ne 0) { throw "issue body fetch failed" }
  $IssueBody = ("$IssueBody")
  if ($IssueBody.StartsWith('"') -and $IssueBody.EndsWith('"') -and $IssueBody.Length -ge 2) { $IssueBody = $IssueBody.Substring(1, $IssueBody.Length - 2) }
  $PromptText = $PromptText + "`r`n`r`n## Live issue body (single source of scope)`r`n" + $IssueBody
  Push-Location $WorkDir
  try {
    & opencode run $PromptText | Tee-Object -FilePath $ReportFile
    if ($LASTEXITCODE -ne 0) { throw "worker exited non-zero" }
  } finally {
    Pop-Location
  }

  Write-Output ("COMMENT: report {0} -> issue #{1}" -f $ReportFile, $Number)
  Convert-ReportToUtf8 -Path $ReportFile
  $HumanReport = Get-HumanReport -Path $ReportFile
  if ([string]::IsNullOrWhiteSpace($HumanReport)) {
    $HumanReport = Get-ReportTitle -Path $ReportFile -Fallback $Branch
  }
  $Transcript = Get-Content $ReportFile -Raw
  if (("$Transcript").Length -gt 60000) {
    $Transcript = ("$Transcript").Substring(0, 60000) + "`r`n`r`n[... transcript truncated at 60000 chars ...]"
  }
  $CommentLines = @(
    $HumanReport,
    "",
    "<details><summary>Full worker transcript (machine detail)</summary>",
    "",
    ("{0}" -f $Transcript),
    "",
    "</details>"
  )
  $CommentFile = (Join-Path ([IO.Path]::GetTempPath()) ("comment-{0}.md" -f $Number))
  [IO.File]::WriteAllText($CommentFile, ($CommentLines -join "`r`n"), (New-Object Text.UTF8Encoding $false))
  & gh issue comment $Number --body-file $CommentFile
  if ($LASTEXITCODE -ne 0) { throw "comment failed" }

  Write-Output ("PR: verifying branch {0} exists on origin" -f $Branch)
  $LsRemote = & git -C $TargetRepo ls-remote --heads origin $Branch
  if ($LASTEXITCODE -ne 0) { throw "pr verify failed: branch missing on origin" }
  if ([string]::IsNullOrWhiteSpace("$LsRemote")) { throw "pr verify failed: branch missing on origin" }

  $ReportText = Get-Content $ReportFile -Raw
  $TitleLine = Get-ReportTitle -Path $ReportFile -Fallback $Branch
  $PrBodyFile = (Join-Path ([IO.Path]::GetTempPath()) ("pr-body-{0}.md" -f $Number))
  $PrBodyLines = @(
    ("Closes: #{0}" -f $Number),
    "",
    "## What",
    ("Worker report for issue #{0} (branch `{1}`, awaiting human review):" -f $Number, $Branch),
    "",
    ("{0}" -f $HumanReport),
    "",
    "## Checklist",
    "- [ ] SLOC counted and reported below",
    "- [ ] Tests/proofs executed (commands + outputs pasted or linked)",
    "- [ ] Perf impact: none / measured",
    "- [ ] Caveats listed (or None)",
    "- [ ] Branch-only push (no main push; main merge is human)",
    "- [ ] No scheduler/service/watcher/polling code added",
    "- [ ] No credentials in repo (env/keyring names only)",
    "",
    "## Report (machine detail)",
    "<details><summary>Full worker report + transcript</summary>",
    "",
    ("{0}" -f $ReportText),
    "",
    "</details>"
  )
  [IO.File]::WriteAllText($PrBodyFile, ($PrBodyLines -join "`r`n"), (New-Object Text.UTF8Encoding $false))
  $PrCreateArgs = @("pr", "create", "--head", $Branch, "--base", "main", "--title", $TitleLine, "--body-file", $PrBodyFile)
  $PrKind = "ready"
  if ($Draft) {
    $PrCreateArgs = @("pr", "create", "--draft", "--head", $Branch, "--base", "main", "--title", $TitleLine, "--body-file", $PrBodyFile)
    $PrKind = "draft"
  }
  Write-Output ("PR: creating {0} PR head={1} base=main title={2}" -f $PrKind, $Branch, $TitleLine)
  & gh @PrCreateArgs
  if ($LASTEXITCODE -ne 0) { throw "pr create failed" }

  & gh issue edit $Number --remove-label "in-progress" --add-label "in-review"
  if ($LASTEXITCODE -ne 0) { throw "label transition failed" }

  Confirm-QuietShip
  Write-Output ("DONE: issue #{0} in-review, ship quiet" -f $Number)
} finally {
  Pop-Location
}
