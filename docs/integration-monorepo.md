# Using the orchestrator with dream-monorepo (reference, never vendored)

The orchestrator is maintained here (`bloomstick/dream-orchestrator`) and
consumed from dream-monorepo checkouts by path reference. No files are copied
between repos — copies drift, references don't.

## Convention

- One environment variable names the orchestrator checkout (example name:
  `DREAM_ORCHESTRATOR`; any name the operator exports consistently works):
  the directory holding `dispatcher/`, `templates/`, `prompts/` of a current
  `main`.
- Architect sessions working on dream-monorepo invoke orchestrator scripts by
  absolute path (`<orchestrator>/dispatcher/Invoke-Dispatch.ps1`,
  `<orchestrator>/templates/Sync-Labels.ps1`). No copy step, no sync step,
  nothing to go stale.
- Worker prompts reference the orchestrator path for the single phase they
  need (usually dispatch only); workers never write to it.
- Milestone issues and status labels (`ready`, `in-progress`, `in-review`,
  `needs-fix`, `blocked-human`) live in the working repo — never in the
  orchestrator repo. The dispatcher claims, comments, and labels there
  (`Push-Location $TargetRepo`); sync labels per working repo with
  `templates/Sync-Labels.ps1 --repo <owner/name>`.

## Why not vendoring or submodules

Vendored copies fork on day one (fixes land in one repo, users run the other);
submodules add checkout-state failure modes on Windows for zero benefit here
(the consumer needs a live directory, not a pinned blob — orchestration
scripts are always run at HEAD with human attendance). If reproducibility ever
requires pinning, pin the commit sha in the milestone issue, not a copy.

## Freshness

Pull the orchestrator checkout (`git pull --ff-only`) at session start when
it matters (new dispatcher flags, new templates). Stale orchestrator + fresh
monorepo is a user error the runbook's preflight should catch: compare
`git log --oneline -1` of both checkouts before dispatching.

## Landing-rule seam (stated here, changed nowhere)

Landing in the orchestrator is always a human manual merge of the worker's
feature branch to `main` — the Architect never pushes `main`, and no merge
queue runs in the orchestrator checkout. The merge-queue wording
(`acquire -> merge -> finish -> release`) in
`.agents/skills/architect/references/prompt-template.md` is the
dream-monorepo instantiation of this seam and is parked for orchestrator use:
a consumer repo may define its own landing procedure on its side of the seam,
but nothing in this repo changes the rule — worker pushes the branch,
human performs the merge, Architect verifies read-only.
