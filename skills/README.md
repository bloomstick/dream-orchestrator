# Skills owned here

Source of truth for agent skills maintained alongside this orchestrator.
Consumers take pinned installs (see each skill's `INSTALLED_FROM` convention
in the consuming repo) — never live references, never copies without a pin.

- `architect/` — planning-and-oversight skill (laws, investigation, P0
  planning, prompt anatomy, dispatcher verification). Execution mechanics
  (§7) point at `../prompts/architect-runbook.md`, the single source —
  mechanics are never restated in the skill.
