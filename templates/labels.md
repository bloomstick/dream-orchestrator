# Labels

Single issue template + labels. No bug/task variant: bugs and tasks use
`templates/milestone-issue.md` with `kind:bug` / `kind:task`. The six-section
shape (base, context, scope, forbidden, acceptance, landing+report) is
identical; only acceptance content differs.

Bootstrap: `templates/Sync-Labels.ps1` (idempotent, safe re-runs).
Dry proof: `.\Sync-Labels.ps1 -DryRun` (parses, lists, never mutates).

## Status (exactly one per open issue)
| Label | Meaning |
|---|---|
| `ready` | Claimable. Dispatcher picks oldest `ready`. |
| `in-progress` | Claimed; worker running in a live session. |
| `in-review` | Worker exited; Architect judging. |
| `needs-fix` | Architect requested fix; ready to re-claim. |
| `blocked-human` | Needs human decision; dispatcher skips. |
| `done` | Shipped; set on close by `Close-Shipped.ps1` (created by `Sync-Labels.ps1`). |

## Area (zero or more)
| Label | Meaning |
|---|---|
| `area:dispatcher` | `dispatcher/` scripts |
| `area:templates` | `templates/` issue/PR/labels |
| `area:prompts` | `prompts/` worker/architect |
| `area:docs` | `docs/` design notes |

## Kind (exactly one per issue)
| Label | Meaning |
|---|---|
| `kind:milestone` | Multi-step milestone (default) |
| `kind:bug` | Defect; acceptance is repro + regression proof |
| `kind:task` | Small chore; acceptance is single proof |
