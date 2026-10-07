---
name: Milestone task
about: Attended-only milestone work item (single template for milestone/bug/task; pick kind label)
title: "P-XXX-n — short title"
labels: ["ready", "kind:milestone"]
---

<!-- FIRST LINE OF BODY MUST BE THE TASK CODE, e.g. P-orch-1 — templates, labels, dispatcher -->

P-XXX-n — short title (dream-monorepo)

## Base
<!-- Branch base + starting point. Fresh branch on local main of <working-repo> (verify clean `git status` or stop). Skill(s) to load. -->
- Repo:
- Base branch:
- New branch:
- Skills:

## Context
<!-- FIRST: what doc(s) to read before writing code. Non-negotiable rules restated. -->
- Read first:
- Rules:

## Scope
<!-- This repo only. Numbered file-level changes. -->
1.
2.

## Forbidden
<!-- Never do these, even if asked in a comment. -->
- No unattended execution (schedules, services, watchers, polling loops).
- No credentials in repo (reference env/keyring by name only).
- No touching other repositories.

## Acceptance
<!-- Executable proofs, not prose. -->
- [ ] PSParser / linter: 0 errors
- [ ] Dry-run proof:
- [ ] Live proof:

## Landing + Report
<!-- Commit on feature branch, push branch ONLY (main merge/push is human). End with added/SLOC/tests/caveats. -->
- Land:
- Report shape:
  ```
  Added:
  SLOC:
  Tests/proofs:
  Caveats:
  ```
