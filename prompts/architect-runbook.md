# Architect runbook (attended-only)

Entry: human asks the Architect in a live session. No other entry exists.

1. Judge
   - Read the human report first (visible issue comment — 30-second verdict),
     then the machine report + transcript (collapsed) + diff + proofs on
     suspicion or per tier (SKILL.md §5).
   - Fail if: main push, pipeline/schedule code, unrun tests, credentials, wrong repo.
2. Request-fix
   - `gh issue edit <n> --remove-label in-review --add-label needs-fix`
   - `gh issue comment <n> --body "<what failed, file:line, expected proof>"`
   - Re-dispatch with `dispatcher/Invoke-Dispatch.ps1 -IssueNumber <n>` in foreground.
3. Merge
   - PR handoff: the dispatcher already opened a PR after COMMENT
     (ready by default; `-Draft` restores the draft handoff:
     `gh pr create [--draft] --head <branch> --base main`, title = trailing
     task-code line of the worker report, body per
     `templates/pull-request.md` with `Closes: #<n>`
     required; branch verified on origin via `git ls-remote --heads` first).
     Review THAT PR. Every dispatch stalls at in-review without it.
   - Human merges branch to main manually. Architect never pushes main — a human saying `push` never authorizes a `main` push (push vocabulary in the Architect skill: `push` = branch-only).
4. Close (armed, never assumed — `dispatcher/Close-Shipped.ps1`)
   - After firing, the Architect arms the closer in the same session:
     `dispatcher/Close-Shipped.ps1 -TargetRepo <path> -IssueNumbers <n,...>
     -Timeout <s> -Poll <s>` (explicit numbers only, never default-all watch).
     It waits bounded (heartbeat per poll) for the human's merges + closes,
     then per issue: label `in-review` -> `done`, comment
     "Shipped <sha>. Silence confirmed below.", prune the `work-p-<n>`
     worktree. No closer armed = HOLD waits on the human with no
     auto-continue; the single-issue dispatcher performs no close step itself.
   - Fetch origin in the target repo and report the `origin/main` sha after
     closing. Stale bases and dead worktrees never accumulate.
   - Standalone bounded wait (no close steps) stays available:
     `dispatcher/Wait-IssuesClosed.ps1 -IssueNumbers <n> -Timeout <s> -Poll <s>`.
5. Confirm silence (stop-at-ship proof per run — dispatcher children only,
   exactly `Confirm-QuietShip` in `dispatcher/Invoke-Dispatch.ps1`)
   - `Get-Job -State Running` must be empty.
   - No child `opencode|gh|git` processes under the dispatcher (not a
     machine-wide process sweep).
   - `git worktree list` shows no worker worktree left (prune if kept for log).
   - Foreground streamed; background notified. Silent indefinite execution is a defect.
