# Dispatcher DryRun (`dispatcher/Invoke-Dispatch.ps1 -DryRun`)

Scope: static description of the `-DryRun` path in `dispatcher/Invoke-Dispatch.ps1`
(the `if ($DryRun)` branch), plus the preamble and the `Confirm-QuietShip`
definition it depends on. Anchors below name statements and parameters, never
line numbers, so this document survives script edits.
No live run was performed to produce this document.

Source reviewed anchor-by-anchor against `dispatcher/Invoke-Dispatch.ps1` in full
(comment header, `param(...)` block, guards, `Confirm-QuietShip`, path and
default resolution, the `if ($DryRun)` branch, the live path).

Usage (from the `.EXAMPLE` entries in the script comment header):

```powershell
.\Invoke-Dispatch.ps1 -TargetRepo <target-repo-path> [-IssueNumber 0] [-DryRun]
```

## Preamble that still executes in DryRun

- The `param(...)` block — params: `TargetRepo` (string, default
  `""`), `IssueNumber` (int, default `0`), `WorkerPrompt` (string, default `""`),
  `ReportFile` (string, default `""`), `DryRun` (switch), `Background` (switch),
  `NotifyCommand` (string, default `""`).
- The `$ErrorActionPreference = "Stop"` statement: any
  `throw` aborts with a non-zero exit.
- The background guard (`-Background` requires `-NotifyCommand`) runs in ALL modes
  including DryRun: if `-Background` without `-NotifyCommand`, `throw
  "background only with notify-on-completion..."`.
- The `TargetRepo` guard is BYPASSED in DryRun:
  `if ($TargetRepo -eq "" -and -not $DryRun)`. DryRun therefore needs no target repo.
- The `Confirm-QuietShip` function definition (see
  Quiet-ship proof below). Defining it has no side effects.
- The path-resolution preamble (`$ScriptDir = $PSScriptRoot`;
  `$OrchestratorDir = Split-Path $ScriptDir -Parent`. Read-only path resolution.
- The prompt/report default resolution still applies in DryRun:
  empty `WorkerPrompt` → `<orchestrator>/prompts\worker-prompt.md`; empty
  `ReportFile` → per-issue `<temp>\dispatch-report-<n>.md` (so concurrent
  dispatches never share a report). No files are read or written here,
  only paths are computed.
- The `$Number` coercion (`$Number = $IssueNumber`; if DryRun
  and `$Number -eq 0`, `$Number = 999`. A DryRun with no `-IssueNumber` therefore
  documents against synthetic issue `#999`.

## DryRun block, statement-by-statement (the `if ($DryRun)` branch)

The `if ($DryRun)` branch prints the would-be transitions and exits BEFORE
the live path's `Push-Location $TargetRepo`, so the live path
(claim → run → comment/label → quiet-ship check) never executes and the
working directory is unchanged.

| Step | Output / action | Live counterpart it mirrors (NOT executed) |
|------|-----------------|---------------------------------------------|
| Claim | `DRY CLAIM: issue #<n> ready -> in-progress (gh issue edit, no mutate in dry-run)` | The live claim step (`CLAIM: issue #<n> ready -> in-progress` + `gh issue edit $Number --remove-label "ready" --add-label "in-progress"`). DryRun emits the label transition text only; no `gh` process is spawned. |
| Run (worktree) | `DRY RUN: worktree+branch in TARGET repo for issue #<n> (git worktree add -b feat/p-<n>-worker)` | The live worktree step (`$Branch = "feat/p-<n>-worker"`, `$WorkDir` under temp, `git -C $TargetRepo worktree add`). DryRun names the branch convention without creating a worktree or branch. |
| Split | `DRY SPLIT: human-report block visible + transcript collapsed in details (no mutate)` | The live split step (last ```human-report fence posted visible, transcript inside `<details>`, 60000-char cap). DryRun splits nothing. |
| Sanitize | `DRY SANITIZE: report -> UTF-8 no BOM, ANSI stripped (no mutate)` | The live sanitize step (`Convert-ReportToUtf8`: BOM-aware decode, ANSI CSI/OSC strip, NUL strip, UTF-8-no-BOM rewrite). DryRun converts nothing. |
| Fetch | `DRY FETCH: live issue body for issue #<n> appended to prompt (gh issue view, no mutate)` | The live fetch step (issue body is the single source of scope). DryRun fetches nothing. |
| Run (worker) | `DRY RUN: opencode run foreground streaming with prompt <WorkerPrompt>` | The live worker step (`RUN: opencode run foreground streaming` + `Get-Content $WorkerPrompt` + `opencode run $PromptText`). DryRun prints the resolved prompt path; it never reads the prompt file and never spawns `opencode`. |
| Notify (conditional) | Conditional: only if `-Background` was passed: `DRY NOTIFY: would run notify: <NotifyCommand>` | The live background log line (`RUN: background mode, notify=...`). Confirms the notify-on-completion wiring without running anything in the background. Omitted entirely for foreground DryRuns. |
| Comment | `DRY COMMENT: report <per-issue-report> -> issue #<n> comment (gh issue comment, no mutate)` | The live comment step (`COMMENT: report <file> -> issue #<n>` + `gh issue comment $Number --body-file $ReportFile`). DryRun prints the resolved report path; no comment is posted and the report file is not read. |
| Label | `DRY LABEL: issue #<n> in-progress -> in-review (gh issue edit, no mutate)` | The live label step (`gh issue edit $Number --remove-label "in-progress" --add-label "in-review"`). DryRun prints the second label transition; no `gh` process is spawned. |
| Quiet-ship | `Confirm-QuietShip` invocation (real check, not a print) | The same function the live path calls before its `DONE` line. Enumerates running jobs and child worker procs; see below. |
| Done | `DRY DONE: claim->run->comment->label transitions shown, processes empty` | Mirrors the live `DONE: issue #<n> in-review, ship quiet` line, but asserts only that the four transitions were DISPLAYED, not performed. |
| Exit | `exit 0` | Terminates before the live path. Guarantees none of the live `gh` / `git` / `opencode` calls, `Push-Location`/`Pop-Location`, or report posting can run. |

Transition summary shown by a DryRun: `claim -> run -> sanitize -> comment -> pr -> label`:

1. Claim: `ready -> in-progress` (the `DRY CLAIM` line).
2. Run: worktree+branch `feat/p-<n>-worker` + foreground `opencode run` (the two `DRY RUN` lines, plus the optional `DRY NOTIFY` line).
3. Comment: report file → issue comment (the `DRY COMMENT` line).
4. Label: `in-progress -> in-review` (the `DRY LABEL` line).

## Quiet-ship proof (runs in DryRun)

`Confirm-QuietShip` (the function definition in the script preamble):

```powershell
function Confirm-QuietShip {
  $Jobs = @(Get-Job -State Running -ErrorAction SilentlyContinue)
  $Kids = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $PID) -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(opencode|gh|git)(\.exe)?$" })
  Write-Output ("SHIP-CHECK: running jobs={0} child worker procs={1}" -f $Jobs.Count, $Kids.Count)
  if ($Jobs.Count -gt 0 -or $Kids.Count -gt 0) { throw "stop-at-ship violated: child processes alive" }
  Write-Output "SHIP-CHECK: PROCESS TABLE EMPTY (no dispatcher children, no running jobs)"
}
```

- First statement: snapshot PowerShell jobs in `Running` state (silent on error).
- Second statement: snapshot child processes of the current `$PID` whose name matches
  `opencode|gh|git` (with optional `.exe`). These are the only worker-related
  children the dispatcher can produce.
- Third statement: always prints `SHIP-CHECK: running jobs=<j> child worker procs=<k>`.
- Fourth statement: if either count is non-zero, `throw`s — with `$ErrorActionPreference =
  "Stop"` this is a non-zero exit, so a dirty process table FAILS the DryRun.
- Fifth statement: on a clean table prints `SHIP-CHECK: PROCESS TABLE EMPTY ...`.
- Because the DryRun branch calls this before its trailing `exit 0`, every DryRun ends with a
  two-line `SHIP-CHECK` proof in its stdout.

Expected quiet DryRun stdout shape (with `-IssueNumber 0`, foreground):

```text
DRY CLAIM: issue #999 ready -> in-progress (gh issue edit, no mutate in dry-run)
DRY RUN: worktree+branch in TARGET repo for issue #999 (git worktree add -b feat/p-999-worker)
DRY RUN: opencode run foreground streaming with prompt <orchestrator>\prompts\worker-prompt.md
DRY FETCH: live issue body for issue #999 appended to prompt (gh issue view, no mutate)
DRY SANITIZE: report -> UTF-8 no BOM, ANSI stripped (no mutate)
DRY SPLIT: human-report block visible + transcript collapsed in details (no mutate)
DRY COMMENT: report <temp>\dispatch-report-999.md -> issue #999 comment (gh issue comment, no mutate)
DRY PR: verify branch feat/p-999-worker exists on origin (git ls-remote --heads, no mutate)
DRY PR: gh pr create --head feat/p-999-worker --base main --title <trailing-task-code-line> --body-file <pr-body-file> (no mutate, never merge)
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
| Successful DryRun (quiet table, guards pass) | `0` via the explicit trailing `exit 0` of the DryRun branch. |
| `-Background` without `-NotifyCommand` | Non-zero via `throw` (the background guard). Fails BEFORE any `DRY ...` line. Applies to DryRun. |
| `Confirm-QuietShip` finds jobs or `opencode|gh|git` children | Non-zero via `throw "stop-at-ship violated..."` (the guard statement inside `Confirm-QuietShip`). The first `SHIP-CHECK` counts line is still printed; the `PROCESS TABLE EMPTY` and `DRY DONE` lines are NOT printed. |
| Any unexpected terminating error in the DryRun preamble | Non-zero via the `$ErrorActionPreference = "Stop"` statement. |

There are no `$LASTEXITCODE` checks in the DryRun branch (contrast the live
claim/run/comment/label steps, which check `$LASTEXITCODE` after each native
call): DryRun spawns no external processes, so it has no external
exit codes to inspect. Its only failure modes are the PowerShell `throw`s above.

## What DryRun guarantees NOT to do

- No `gh issue list` (the live auto-claim step), no `gh issue edit` (the live
  claim/label steps), no `gh issue comment` (the live comment step).
- No `git -C $TargetRepo worktree add` (the live worktree step) — `TargetRepo` may be empty.
- No `Get-Content $WorkerPrompt` (the live prompt-read step), no `opencode run $PromptText`
  (the live worker step), no `Convert-ReportToUtf8` conversion (the live sanitize step).
- No `Push-Location` / `Pop-Location` (the live directory-switch steps) — caller CWD unchanged.
- No report file read or write; `ReportFile` is only interpolated into the `DRY COMMENT` text.

## Fan-out and closer DryRuns

`dispatcher/Invoke-Fanout.ps1 -DryRun` prints one `DRY FANOUT` line per
issue (prompt path, per-issue report path, ready/draft) plus `DRY DONE`,
then exits 0: no jobs started, nothing mutated. `dispatcher/Close-Shipped.ps1
-DryRun` prints one `DRY CLOSE` line per issue plus `DRY DONE`, then exits 0:
nothing waited, nothing mutated.
