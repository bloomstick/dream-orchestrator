# Sync-Labels.ps1 - idempotent GitHub label bootstrap.
# Attended-only: run by a human in a live session. Never scheduled, never daemonized.
# Usage: .\Sync-Labels.ps1 [-Repo owner/name] [-DryRun]
# DryRun parses and lists actions without mutating anything (gh is never called).
param(
  [string]$Repo = "",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"

$Labels = @(
  @{ Name = "ready"; Color = "0E8A16"; Description = "Status: claimable by dispatcher" },
  @{ Name = "in-progress"; Color = "1D76DB"; Description = "Status: worker running in live session" },
  @{ Name = "in-review"; Color = "FBCA04"; Description = "Status: worker exited, architect judging" },
  @{ Name = "needs-fix"; Color = "D93F0B"; Description = "Status: architect requested fix" },
  @{ Name = "blocked-human"; Color = "B60205"; Description = "Status: needs human decision, dispatcher skips" },
  @{ Name = "area:dispatcher"; Color = "1D76DB"; Description = "Area: dispatcher scripts" },
  @{ Name = "area:templates"; Color = "0E8A16"; Description = "Area: issue PR templates and labels" },
  @{ Name = "area:prompts"; Color = "5319E7"; Description = "Area: worker and architect prompts" },
  @{ Name = "area:docs"; Color = "006B75"; Description = "Area: design notes" },
  @{ Name = "kind:milestone"; Color = "5319E7"; Description = "Kind: multi-step milestone" },
  @{ Name = "kind:bug"; Color = "D93F0B"; Description = "Kind: defect with repro proof" },
  @{ Name = "kind:task"; Color = "FBCA04"; Description = "Kind: small chore with single proof" }
)

$RepoArgs = @()
if ($Repo -ne "") { $RepoArgs = @("--repo", $Repo) }

foreach ($L in $Labels) {
  $Name = $L.Name
  $Color = $L.Color
  $Desc = $L.Description
  if ($DryRun) {
    Write-Output ("WOULD SYNC: {0} color={1} desc={2}" -f $Name, $Color, $Desc)
    continue
  }
  Write-Output ("SYNC: {0}" -f $Name)
  try {
    & gh label create $Name --color $Color --description $Desc @RepoArgs 2>$null
    if ($LASTEXITCODE -ne 0) { throw "create failed, trying edit" }
  } catch {
    & gh label edit $Name --color $Color --description $Desc @RepoArgs
    if ($LASTEXITCODE -ne 0) { throw ("label sync failed: {0}" -f $Name) }
  }
}
Write-Output ("DONE: {0} labels processed. DryRun={1}" -f $Labels.Count, $DryRun)
