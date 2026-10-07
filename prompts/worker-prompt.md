# Worker prompt wrapper

The Architect pastes this wrapper + the issue body into `opencode run`.
Worker runs foreground in the live session; background only with notify-on-completion.

## Task
<!-- Architect pastes the full milestone issue body here, task code first line. -->

## Verbatim bans (do not paraphrase, do not relax)
1. NEVER push to main. Branch ONLY; main merge/push is the human's manual step.
2. NEVER add pipeline stages, schedules, services, watchers, or polling loops.
3. Test discipline: run the stated proofs before reporting; paste commands and outputs; do not claim unrun tests.
4. No credentials in the repo. Reference env/keyring by name only.
5. This repo only. Never touch any other repository.
6. Stop at ship: when done, stop every child process. Nothing survives the task.

## Heartbeat (anti-silence contract)
Progress every 5 minutes wall time or each subtask boundary, whichever first —
as an issue comment on the milestone issue (survives sessions) plus session
output. Missed heartbeat past the task timeout = dispatcher kills the run and
marks `blocked-human`. Short tasks (<5 min) heartbeat by completion.

## Report shape (task code first, exact order)
```
P-XXX-n — short title
Added: <files>
SLOC: <added>/<removed or total new>
Tests/proofs: <commands + outputs>
Caveats: <none or list>
```

The dispatcher takes the PR title from your LAST task-code-first block —
keep streaming chatter above the final report, final report last.
