# dream-orchestrator

Attended-only agent orchestration for the Dream monorepo. No daemons, no
schedulers, no background activity — everything starts when the user asks
the Architect, and everything stops when the task ships.

## Rules (non-negotiable)

1. **Entry point is the human asking an Architect.** No agent, script, server,
   or schedule starts work on its own, ever.
2. **Nothing runs past shipping.** When the task is done (merged, verified,
   reported), every worker, server, and watcher stops. Idle cost is zero by
   construction — there is nothing installed that could run unattended.
3. **Notice at every moment.** Any running agent is traceable to a live human
   request; foreground work streams to the console, background work notifies
   on completion. Silent indefinite execution is a defect, not a feature.

## Layout

- `.agents/skills/architect/` — the Architect skill itself (HOME — this is the source
  of truth; see below). Execution mechanics live only in the runbook —
  the skill points at them, never restates them.
- `dispatcher/` — on-demand dispatch scripts (run by the Architect inside a
  live session; never scheduled, never daemonized).
- `templates/` — GitHub issue/PR templates and label definitions (the six-section
  milestone prompt shape, report contract, acceptance gates).
- `prompts/` — worker-prompt wrappers (bans embedded: no main push, no pipeline
  stages, test discipline) and the Architect runbook for judging/merging.
- `docs/` — workflow design notes and the phased rollout log.
