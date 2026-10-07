# First attended dispatch — operator walkthrough

Attended-only narrative for the first live dispatch. Source of truth:
`README.md` (rules) + `prompts/architect-runbook.md` (judge/fix/merge/close/silence).
No daemons, no schedulers, no background persistence — this whole walkthrough
happens inside one live session started by a human asking the Architect.

## 0. Preconditions (do not fire until all green)

- [ ] Live session: human asked the Architect directly. No other entry exists.
- [ ] You are on the orchestrator checkout for scripts only; worker work lands in
      the TARGET repo worktree/branch, never in this checkout, never in any
      other repo. Milestone issues live in the TARGET repo too (the working
      repo) — never in the orchestrator repo.
- [ ] `gh` authenticated, `opencode` on PATH, `git` on PATH.
- [ ] A `ready`-labelled issue exists in the TARGET repo (the working repo).
- [ ] Target repo path known (passed as `-TargetRepo <path-to-target-repo>`).
- [ ] Foreground console visible for streaming. If you plan `-Background`,
      a `-NotifyCommand` is mandatory — background without notify is forbidden.
- [ ] Quiet ship baseline: `Get-Job -State Running` empty,
      `Get-Process -Name opencode` empty, `git worktree list` shows no
      leftover `work-p-*` worktree.

Abort if any box is unchecked. Fix the precondition, do not work around it.

## 1. Fire order

All commands run by the Architect inside the live session, foreground unless
stated. Never schedule, never daemonize.

1. **Claim** — oldest `ready` issue → `in-progress` (run `gh` from the TARGET
   repo checkout so it resolves there, or pass `--repo`; dispatcher does the
   former via `Push-Location $TargetRepo`):
   `gh issue list --label "ready" --state open` (dispatcher picks oldest),
   then `gh issue edit <n> --remove-label "ready" --add-label "in-progress"`.
2. **Run** — worktree + branch in TARGET repo:
   `git -C <TargetRepo> worktree add <temp>/work-p-<n> -b feat/p-<n>-worker`,
   then `opencode run <worker-prompt + issue body>` with console streaming.
3. **Comment + label** — worker report → TARGET-repo issue, `in-progress` →
   `in-review`:
   `gh issue comment <n> --body-file <ReportFile>`,
   then `gh issue edit <n> --remove-label "in-progress" --add-label "in-review"`.
4. **Judge** (runbook step 1) — Architect reads worker report (task code first
   line) + diff + proofs. Fail on: main push, pipeline/schedule code,
   unrun tests, credentials, wrong repo.
5. **Merge** (runbook step 3) — human merges branch to main manually.
   Architect never pushes main.
6. **Close** (runbook step 4) — `gh issue edit <n> --remove-label in-review
   --add-label done` (or close), `gh issue comment <n> --body "Shipped <sha>.
   Silence confirmed below."`, `gh issue close <n>`.
7. **Confirm silence** (runbook step 5, also `Confirm-QuietShip` in
   `dispatcher/Invoke-Dispatch.ps1`) — `Get-Job -State Running` empty,
   `Get-Process -Name opencode` empty, `git worktree list` clean.
   Foreground streamed; background notified.

Shortcut: `dispatcher/Invoke-Dispatch.ps1 -TargetRepo <path> [-IssueNumber <n>]`
performs claim → run → comment/label → quiet-ship check. Add `-DryRun` for a
no-mutate rehearsal (uses issue #999, prints DRY CLAIM/RUN/COMMENT/LABEL lines).
Request-fix re-dispatch is `dispatcher/Invoke-Dispatch.ps1 -IssueNumber <n>`
in foreground.

## 2. What green looks like per step

| Step | Green |
| ---- | ----- |
| Preconditions | All checkboxes above ticked; silence baseline empty. |
| Claim | Console prints `CLAIM: issue #<n> ready -> in-progress`; `gh issue view <n>` shows `in-progress` label, no other change. |
| Run | Console prints `RUN: worktree+branch feat/p-<n>-worker at <temp>/work-p-<n>` then streams `opencode run` output live to the console. Branch exists only in TARGET repo. |
| Comment + label | Console prints `COMMENT: report <file> -> issue #<n>` and `DONE: issue #<n> in-review, ship quiet`; issue shows the task-code-first report + `in-review` label. |
| Judge | Report has task code first line, added files, SLOC, commands + outputs, caveats; diff touches only the TARGET branch, no main push, no schedule/watcher/pipeline code, no credentials, proofs actually ran. |
| Merge | Human merged; `main` advanced by exactly the reviewed branch. Architect pushed nothing to main. |
| Close | Issue labelled `done`, comment `Shipped <sha>. Silence confirmed below.`, issue closed. |
| Silence | `Get-Job -State Running` empty, `Get-Process -Name opencode` empty, `git worktree list` shows no worker worktree (pruned if kept for log). `SHIP-CHECK: PROCESS TABLE EMPTY` in dispatcher output. |

## 3. Abort paths

- **No `ready` issues** (`no ready issues found`): stop. File or re-label an
  issue first; do not invent work.
- **Claim fails** (`claim failed`): stop, stay on current labels. Check `gh`
  auth / issue number; re-fire only the claim.
- **Worktree add fails** (`worktree add failed`): stop. Inspect TARGET repo
  path, existing branch/worktree collision, `git worktree list`. Prune stale
  `work-p-*` only after confirming no live worker. Never proceed to `opencode run`
  without a fresh branch worktree.
- **Worker exits non-zero** (`worker exited non-zero`): keep the worktree for
  diagnosis. Do not comment a success report. Either request-fix
  (`--remove-label in-review --add-label needs-fix` + comment with what failed,
  `file:line`, expected proof) and re-dispatch foreground, or close as failed
  with the raw output pasted.
- **Background without notify** (`background only with notify-on-completion`):
  hard stop. Re-fire foreground, or supply `-NotifyCommand`. Silent background
  execution is a defect, not a feature.
- **Comment/label transition fails** (`comment failed`, `label transition failed`):
  stop. Do not re-run the worker. Retry the `gh` step by hand until the issue
  state matches the table above.
- **Judge fails** (main push, pipeline/schedule code, unrun tests, credentials,
  wrong repo): request-fix path from the runbook — relabel to `needs-fix`,
  comment exact failure, re-dispatch with `-IssueNumber <n>` foreground.
- **Silence check fails** (`stop-at-ship violated: child processes alive`):
  do not close, do not merge. Kill or wait for the listed jobs/child procs,
  re-run the silence commands until empty. Closing over live children violates
  rule 2.
- **Any confusion about which repo you are in**: abort immediately. Worker work
  and milestone issues live in the TARGET repo only; never touch any other
  repository. The orchestrator checkout provides scripts only.
