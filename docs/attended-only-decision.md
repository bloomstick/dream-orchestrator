# Attended-only decision

Date: 2026-10-07. Task: P-orch-1.

Decision: everything in dream-orchestrator is on-demand and attended.
Entry is the human asking the Architect in a live session. Stop-at-ship:
when the task ships, every worker, server, and watcher stops. Notice at
every moment: foreground streams, background notifies on completion.

What was deliberately NOT built (and why):
- No scheduler (Scheduled Tasks, cron, timers). Would violate rule 1: work
  starting without a human request.
- No webhook listener / HTTP server. Would be a daemon surviving ship and an
  unattended entry point.
- No auto-merge. Main merge/push stays the human's manual step; the worker
  ban and the Architect runbook enforce branch-only pushes.
- No watcher / polling loop / FileSystemWatcher. Would be background
  persistence with idle cost and silent execution.
- No credential storage. Env/keyring referenced by name only.

Consequence: idle cost is zero by construction. There is nothing installed
that could run unattended. `dispatcher/Invoke-Dispatch.ps1` proves this per
run with `Confirm-QuietShip` (jobs + opencode procs empty).
