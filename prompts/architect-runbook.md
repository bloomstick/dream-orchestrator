# Architect runbook (attended-only)

Entry: human asks the Architect in a live session. No other entry exists.

1. Judge
   - Read worker report (task code first) + diff + proofs.
   - Fail if: main push, pipeline/schedule code, unrun tests, credentials, wrong repo.
2. Request-fix
   - `gh issue edit <n> --remove-label in-review --add-label needs-fix`
   - `gh issue comment <n> --body "<what failed, file:line, expected proof>"`
   - Re-dispatch with `dispatcher/Invoke-Dispatch.ps1 -IssueNumber <n>` in foreground.
3. Merge
   - Draft-PR handoff: the dispatcher already opened a DRAFT PR after COMMENT
     (`gh pr create --draft --head <branch> --base main`, title = worker-report
     first line, body per `templates/pull-request.md` with `Closes: #<n>`
     required; branch verified on origin via `git ls-remote --heads` first).
     Review THAT draft PR. Every dispatch stalls at in-review without it.
   - Human merges branch to main manually. Architect never pushes main — a human saying `push` never authorizes a `main` push (push vocabulary in the Architect skill: `push` = branch-only).
4. Close (automatic after merge — no separate step)
   - `gh issue edit <n> --remove-label in-review --add-label done` (or close)
   - `gh issue comment <n> --body "Shipped <sha>. Silence confirmed below."`
   - `gh issue close <n>`
   - Confirm the close propagated via bounded wait (explicit numbers only, never default-all watch):
     `dispatcher/Wait-IssuesClosed.ps1 -IssueNumbers <n> -Timeout <s> -Poll <s>`
   - Pull main (`git pull --ff-only`) in every live checkout used this task, then prune worker worktrees (`git worktree remove --force <path>`; `git worktree prune`). Stale bases and dead worktrees never accumulate — the dispatcher performs this on close without being asked.
5. Confirm silence (stop-at-ship proof per run — dispatcher children only,
   exactly `Confirm-QuietShip` in `dispatcher/Invoke-Dispatch.ps1`)
   - `Get-Job -State Running` must be empty.
   - No child `opencode|gh|git` processes under the dispatcher (not a
     machine-wide process sweep).
   - `git worktree list` shows no worker worktree left (prune if kept for log).
   - Foreground streamed; background notified. Silent indefinite execution is a defect.
