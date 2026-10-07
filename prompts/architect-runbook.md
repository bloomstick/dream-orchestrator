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
   - Human merges branch to main manually. Architect never pushes main.
4. Close
   - `gh issue edit <n> --remove-label in-review --add-label done` (or close)
   - `gh issue comment <n> --body "Shipped <sha>. Silence confirmed below."`
   - `gh issue close <n>`
5. Confirm silence (stop-at-ship proof per run)
   - `Get-Job -State Running` must be empty.
   - `Get-Process -Name opencode` must be empty.
   - `git worktree list` shows no worker worktree left (prune if kept for log).
   - Foreground streamed; background notified. Silent indefinite execution is a defect.
