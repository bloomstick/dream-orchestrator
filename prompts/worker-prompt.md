# Worker prompt wrapper

The dispatcher runs `opencode run` with this wrapper + the live milestone
issue body, fetched at claim time (the issue is the single source of scope).
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

## Report shape — TWO blocks, in this order

1. Machine report (task code first, exact order — full detail for the judge):
```
P-XXX-n — short title
Added: <files>
SLOC: <added>/<removed or total new>
Tests/proofs: <commands + outputs>
Caveats: <none or list>
```

2. Human report LAST (your stdout MUST end with this fenced block — plain prose
a human can read, no chatter inside, at most 15 lines; posted visible on the
issue while the transcript collapses, and reused as the PR description):
```human-report
P-XXX-n — one-line outcome naming what changed
Changed: <files, plain words>
Proofs: <one line per proof, command — result>
Caveats: <none or list>
```

The dispatcher takes the PR title from your LAST task-code-first block —
keep streaming chatter above the machine report, machine report above the
human report, human report last.
