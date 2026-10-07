# Dispatcher DryRun (`dispatcher/Invoke-Dispatch.ps1 -DryRun`)

Scope: static description of the `-DryRun` path in `dispatcher/Invoke-Dispatch.ps1`
(lines 41–50), plus the preamble and `Confirm-QuietShip` lines it depends on.
No live run was performed to produce this document.

Source reviewed line-for-line: `dispatcher/Invoke-Dispatch.ps1:1-94`.

Usage (from `dispatcher/Invoke-Dispatch.ps1:7-8`):

```powershell
.\Invoke-Dispatch.ps1 -TargetRepo C:\my\projects\dream-monorepo [-IssueNumber 0] [-DryRun]
```

## Preamble that still executes in DryRun

- `dispatcher/Invoke-Dispatch.ps1:9-17` — params: `TargetRepo` (string, default
  `""`), `IssueNumber` (int, default `0`), `WorkerPrompt` (string, default `""`),
  `ReportFile` (string, default `""`), `DryRun` (switch), `Background` (switch),
  `NotifyCommand` (string, default `""`).
- `dispatcher/Invoke-Dispatch.ps1:18` — `$ErrorActionPreference = "Stop"`: any
  `throw` aborts with a non-zero exit.
- `dispatcher/Invoke-Dispatch.ps1:20-22` — background guard runs in ALL modes
  including DryRun: if `-Background` without `-NotifyCommand`, `throw
  "background only with notify-on-completion..."`.
- `dispatcher/Invoke-Dispatch.ps1:23` — `TargetRepo` guard is BYPASSED in DryRun:
  `if ($TargetRepo -eq "" -and -not $DryRun)`. DryRun therefore needs no target repo.
- `dispatcher/Invoke-Dispatch.ps1:25-31` — `Confirm-QuietShip` definition (see
  Quiet-ship proof below). Defining it has no side effects.
- `dispatcher/Invoke-Dispatch.ps1:33-34` — `$ScriptDir = $PSScriptRoot`;
  `$OrchestratorDir = Split-Path $ScriptDir -Parent`. Read-only path resolution.
- `dispatcher/Invoke-Dispatch.ps1:35-36` — defaults still resolve in DryRun:
  empty `WorkerPrompt` → `<orchestrator>/prompts\worker-prompt.md`; empty
  `ReportFile` → `<temp>\dispatch-report.md`. No files are read or written here,
  only paths are computed.
- `dispatcher/Invoke-Dispatch.ps1:38-39` — `$Number = $IssueNumber`; if DryRun
  and `$Number -eq 0`, `$Number = 999`. A DryRun with no `-IssueNumber` therefore
  documents against synthetic issue `#999`.

## DryRun block, line-for-line (`dispatcher/Invoke-Dispatch.ps1:41-50`)

The `if ($DryRun)` branch prints the would-be transitions and exits BEFORE
`dispatcher/Invoke-Dispatch.ps1:53` (`Push-Location`), so the live path
(lines 53–94) never executes and the working directory is unchanged.

| Line | Output / action | Live counterpart it mirrors (NOT executed) |
|------|-----------------|---------------------------------------------|
| 42 | `DRY CLAIM: issue #<n> ready -> in-progress (gh issue edit, no mutate in dry-run)` | Lines 61–63: `CLAIM: issue #<n> ready -> in-progress` + `gh issue edit $Number --remove-label "ready" --add-label "in-progress"`. DryRun emits the label transition text only; no `gh` process is spawned. |
| 43 | `DRY RUN: worktree+branch in TARGET repo for issue #<n> (git worktree add -b feat/p-<n>-worker)` | Lines 65–69: `$Branch = "feat/p-<n>-worker"`, `$WorkDir = <temp>\work-p-<n>`, `git -C $TargetRepo worktree add`. DryRun names the branch convention without creating a worktree or branch. |
| 44 | `DRY RUN: opencode run foreground streaming with prompt <WorkerPrompt>` | Lines 71, 75–79: `RUN: opencode run foreground streaming` + `Get-Content $WorkerPrompt` + `opencode run $PromptText`. DryRun prints the resolved prompt path; it never reads the prompt file and never spawns `opencode`. |
| 45 | Conditional: only if `-Background` was passed: `DRY NOTIFY: would run notify: <NotifyCommand>` | Lines 72–74: `RUN: background mode, notify=...`. Confirms the notify-on-completion wiring without running anything in the background. Omitted entirely for foreground DryRuns. |
| 46 | `DRY COMMENT: report <ReportFile> -> issue #<n> comment (gh issue comment, no mutate)` | Lines 84–85: `COMMENT: report <file> -> issue #<n>` + `gh issue comment $Number --body-file $ReportFile`. DryRun prints the resolved report path; no comment is posted and the report file is not read. |
| 47 | `DRY LABEL: issue #<n> in-progress -> in-review (gh issue edit, no mutate)` | Lines 87–88: `gh issue edit $Number --remove-label "in-progress" --add-label "in-review"`. DryRun prints the second label transition; no `gh` process is spawned. |
| 48 | `Confirm-QuietShip` invocation (real check, not a print) | Same function as live line 90. Enumerates running jobs and child worker procs; see below. |
| 49 | `DRY DONE: claim->run->comment->label transitions shown, processes empty` | Mirrors live line 91 `DONE: issue #<n> in-review, ship quiet`, but asserts only that the four transitions were DISPLAYED, not performed. |
| 50 | `exit 0` | Terminates before line 53. Guarantees none of the live `gh` / `git` / `opencode` calls, `Push-Location`/`Pop-Location`, or report posting can run. |

Transition summary shown by a DryRun: `claim -> run -> comment -> label`:

1. Claim: `ready -> in-progress` (line 42).
2. Run: worktree+branch `feat/p-<n>-worker` + foreground `opencode run` (lines 43–44, plus optional notify line 45).
3. Comment: report file → issue comment (line 46).
4. Label: `in-progress -> in-review` (line 47).

## Quiet-ship proof (runs in DryRun)

`Confirm-QuietShip` (`dispatcher/Invoke-Dispatch.ps1:25-31`):

```powershell
function Confirm-QuietShip {
  $Jobs = @(Get-Job -State Running -ErrorAction SilentlyContinue)
  $Kids = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $PID) -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(opencode|gh|git)(\.exe)?$" })
  Write-Output ("SHIP-CHECK: running jobs={0} child worker procs={1}" -f $Jobs.Count, $Kids.Count)
  if ($Jobs.Count -gt 0 -or $Kids.Count -gt 0) { throw "stop-at-ship violated: child processes alive" }
  Write-Output "SHIP-CHECK: PROCESS TABLE EMPTY (no dispatcher children, no running jobs)"
}
```

- Line 26: snapshot PowerShell jobs in `Running` state (silent on error).
- Line 27: snapshot child processes of the current `$PID` whose name matches
  `opencode|gh|git` (with optional `.exe`). These are the only worker-related
  children the dispatcher can produce.
- Line 28: always prints `SHIP-CHECK: running jobs=<j> child worker procs=<k>`.
- Line 29: if either count is non-zero, `throw`s — with `$ErrorActionPreference =
  "Stop"` this is a non-zero exit, so a dirty process table FAILS the DryRun.
- Line 30: on a clean table prints `SHIP-CHECK: PROCESS TABLE EMPTY ...`.
- Because line 48 calls this inside the DryRun branch, every DryRun ends with a
  two-line `SHIP-CHECK` proof in its stdout.

Expected quiet DryRun stdout shape (with `-IssueNumber 0`, foreground):

```text
DRY CLAIM: issue #999 ready -> in-progress (gh issue edit, no mutate in dry-run)
DRY RUN: worktree+branch in TARGET repo for issue #999 (git worktree add -b feat/p-999-worker)
DRY RUN: opencode run foreground streaming with prompt <orchestrator>\prompts\worker-prompt.md
DRY COMMENT: report <temp>\dispatch-report.md -> issue #999 comment (gh issue comment, no mutate)
DRY LABEL: issue #999 in-progress -> in-review (gh issue edit, no mutate)
SHIP-CHECK: running jobs=0 child worker procs=0
SHIP-CHECK: PROCESS TABLE EMPTY (no dispatcher children, no running jobs)
DRY DONE: claim->run->comment->label transitions shown, processes empty
```

With `-Background -NotifyCommand "<cmd>"`, one extra line appears after the
`DRY RUN: opencode...` line:

```text
DRY NOTIFY: would run notify: <cmd>
```

## Exit codes

| Case | Exit |
|------|------|
| Successful DryRun (quiet table, guards pass) | `0` via explicit `exit 0` (line 50). |
| `-Background` without `-NotifyCommand` | Non-zero via `throw` (lines 20–22). Fails BEFORE any `DRY ...` line. Applies to DryRun. |
| `Confirm-QuietShip` finds jobs or `opencode|gh|git` children | Non-zero via `throw "stop-at-ship violated..."` (line 29). The first `SHIP-CHECK` counts line is still printed; the `PROCESS TABLE EMPTY` and `DRY DONE` lines are NOT printed. |
| Any unexpected terminating error in the DryRun preamble | Non-zero via `$ErrorActionPreference = "Stop"` (line 18). |

There are no `$LASTEXITCODE` checks in the DryRun branch (contrast live lines 58,
63, 69, 79, 86, 88): DryRun spawns no external processes, so it has no external
exit codes to inspect. Its only failure modes are the PowerShell `throw`s above.

## What DryRun guarantees NOT to do

- No `gh issue list` (line 57), no `gh issue edit` (lines 62, 87), no `gh issue
  comment` (line 85).
- No `git -C $TargetRepo worktree add` (line 68) — `TargetRepo` may be empty.
- No `Get-Content $WorkerPrompt` (line 75), no `opencode run $PromptText`
  (line 78).
- No `Push-Location` / `Pop-Location` (lines 53, 76, 81, 93) — caller CWD unchanged.
- No report file read or write; `ReportFile` is only interpolated into line 46 text.
