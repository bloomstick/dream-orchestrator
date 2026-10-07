# Prompt template (copy, fill, fire — delete nothing)
#
# The fired prompt must work in a NEW agent session with zero prior
# context (fresh worktree, fresh branch, no memory of the investigation
# or sibling prompts). Restate everything the reader needs inline.

```text
<P-ID> — <one-line scope> (allowed: <full repo-relative paths ONLY, e.g.
apps/foo/lib/src/bar ONLY — never a bare src/...>)

You are a NEW agent session with zero prior context: fresh worktree +
fresh feature branch on latest local main CONTAINING <merge-sha>
(verify with `git log --oneline -3` or stop). You have not seen the
investigation, the board, or any sibling prompt — everything you need
is in this prompt plus the docs below.
Read FIRST (in this order): <ordered doc list, closest AGENTS.md
files first>. Load skill: <ids, or the literal line `none (no skill
required)` when no skill applies, plus companion skills with the one-line
reason each (see architect SKILL.md §6)>.
Run every command from <owning directory, e.g. apps/foo or packages/bar>
(never from repo root).
GATES (if any gate fails, the milestone does not exist): <platform/debug/
toggle/branch conditions>. No-device rule (when it applies): <which
attached before-record counts as the gate; after-evidence is analyzer +
named suites + code-level reasoning; the human captures device numbers —
never attempt device repro yourself>. Nothing in <forbidden trees as full
repo-relative paths>.
CONTEXT (landed, do not redo): <what's underneath>. Deliberately out of scope:
<parked items by name>.
SCOPE (only these files/areas): <numbered changes with file:line anchors
where known, each path repo-relative>.
FORBIDDEN: <anti-goals — new deps/flags without asking; second systems;
out-of-area edits; tool-specific bans; process bans (e.g. never execute
pipeline stages; fixtures only)>.
ACCEPTANCE: <analyzer + exact test command with file paths, e.g.
`flutter test test/a_test.dart test/b_test.dart` — one single run, never the
whole suite unless every file is named>; <docs/CHANGELOG/regen obligations>;
<named perf/behavior gates re-proven by name — plus the flutter-performance
checklist (docs/docs/operations/performance.md) whenever UI-thread/raster
paths are touched or jank is answered (its skill line goes in the preamble
with the one-line reason)>; SLOC: <metric + gate — e.g. `non-blank
non-comment lines, format-normalized; net-negative, or net-positive only
with structural justification`> + structural-vs-cheap split in the report;
no gaming (goal-sloc §2: no comment/format/packing churn as strategy, no
ruler edits, no silent feature cuts).
LAND: <one of the two below — delete the other>.
FRONT OF QUEUE: commit on your branch, then dart tools/merge_to_main.dart
acquire -> merge -> finish -> release streaming to console (never
main worktree, never push main; confirm `git rev-list --count main..<branch>`
is 0).
FOLLOWER (queue position N>1): commit on your branch, then STOP — do not run
acquire, merge, finish, or release. Never take a queue ticket on your own:
wait for the human's explicit `GO <P-ID>` naming every prior landing it
depends on, then run acquire -> merge -> finish -> release streaming to
console (never main worktree, never push main; confirm rev-list 0). Your
report states ready-to-land (branch, base sha, rev-list vs main) and ends
with the standard shape below.
Ask before deleting branches with unreleased work. End with: <report shape —
behavior delta, SLOC + split %, tests with counts, perf checklist, Caveats>.
```

## Filling rules (where prompts die)

- **Base first**: name the exact merge that must be underneath. "Latest main" rots within hours on an active pipeline — a sha doesn't. State whether the sha is a START gate (may branch alongside siblings from one base) or a LANDING gate (must wait for the prior merge to land).
- **Fresh session, full paths, or it rots**: the reader never saw your investigation. Allowed/forbidden trees are full repo-relative paths (never bare `src/...`); commands name their owning directory; test acceptance is one exact command with file paths. `Load skill: none (no skill required)` when no skill applies — never a bare `none`; companion skills carry the one-line reason (§6).
- **No-device work says so**: when the agent has no device, write the no-device rule inline (which attached before-record is the gate; after-evidence is analyzer + named suites + reasoning; the human captures device numbers). Never let a fresh session attempt device repro on its own.
- **Disjoint or sequential, never hopeful**: two prompts sharing a file must be ordered (second gates on the first's merge) or the shared surface must be split. Parallel-safe means disjoint directories; everything else is a queue.
- **Reuse or delete, never duplicate**: prior perf mechanisms are load-bearing until proven otherwise. Every prompt names the live mechanisms it extends (with file:line), requires building on them instead of around them, and requires deleting in the same diff anything the change fully supersedes (no legacy duplicates, no second systems, no stranded helpers). Acceptance always includes a `git grep` proof of no second system plus an explicit dead-code verdict (deleted X, or "none superseded").
- **Order is enforced by paper, not the queue**: the merge scripts serialize but know nothing about milestone order — whoever calls `acquire` first merges first. Simultaneous prompts land in order only by writing it: position 1 gets FRONT OF QUEUE, every follower gets FOLLOWER with commit-and-stop plus the exact `GO <P-ID>` dependency. Never leave followers on a bare "land in order <order>".
- **Disjoint or sequential, never hopeful**: two prompts sharing a file must be ordered (second gates on the first's merge) or the shared surface must be split. Parallel-safe means disjoint directories; everything else is a queue.
- **Forbid the attractive mistake explicitly**: each scope's most likely overreach gets a named FORBIDDEN line (a second routing system, a port instead of a launcher, executing what only fixtures may prove). If you can picture the wrong diff, forbid it in writing.
- **Acceptance names gates, not vibes**: suite names, invocation counts, and the exact checklist strings — "green" alone is unverifiable. Effectiveness prompts additionally name the SLOC metric + gate and the gaming bans (goal-sloc §2); the split is structural-vs-cheap, never a single number.
- **Effectiveness prompts load goal-sloc**: any prompt whose goal is a simpler/faster/leaner system carries `Load skill: goal-sloc` (in addition to domain skills) plus the SLOC rider above. A report whose cheap share dominates is gaming until proven otherwise — send it back or record the finding, never silently bank it.
- **Reports are load-bearing**: behavior delta, SLOC + structural-vs-cheap %, test counts, perf checklist, Caveats. A report missing any of the five is incomplete — send it back, don't compensate by re-verifying everything yourself (spot-check on main read-only instead).
- **Task code first**: every agent report opens with its milestone code (`M1a`,
  `P-regional`, `P-admin-C`…) as the very first line. Parallel pipelines make
  code-less reports unroutable — no code, no triage.
