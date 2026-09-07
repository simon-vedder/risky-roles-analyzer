# Known issues and sharp edges

Every entry says where it comes from: *(observed)* in this project's lab or a real run,
*(Microsoft)* from official documentation, *(to verify)* on the lab list. Nothing here is guessed.

## Behaviour

- *(to verify)* An **activated PIM assignment** appears in `roleManagement/directory/roleAssignments`
  like a permanent one. The module reads `roleAssignmentSchedules` and types the ones it reports as
  `Activated`, which are protected. Whether every activation shows up there with the same
  `directoryScopeId` as in `roleAssignments` is on the lab list; until then an activation the
  schedules miss reads as `Permanent`, and removing it would end the activation, not the eligibility.
- *(Microsoft)* The app registration **Deactivated** toggle (`isDisabled`) is only exposed on the
  Graph `/beta` endpoint. When that call fails the module warns and treats those apps as active.
- *(Microsoft)* **PIM eligible** assignments (`roleEligibilitySchedules`) need Entra ID P2. Without
  it the module warns once and continues with permanent assignments; `-SkipPim` silences the warning.
- *(observed, script era)* `/directoryObjects/{id}` does not reliably return `accountEnabled`, so
  users and service principals cost a second Graph call each. Results are cached per object id;
  a tenant with a thousand distinct privileged principals makes about two thousand calls.
- *(to verify)* Root-scope (`/`) Azure assignments are visible through subscription scope only
  when the caller can read them; an account without elevated access may not see root assignments
  at all. The module reports what it can see and does not claim completeness at root.
- *(observed)* The **identity running the audit** is protected by user principal name. App-only
  Graph sessions carry no account, so the protection does not apply to them.

## Platform

- *(observed)* The Graph session from `Connect-RiskyRolesAnalyzer` lives in the PowerShell process
  that created it; a new `pwsh` starts without it, while the Az session is picked up from disk.
  Run `Connect-` and `Get-` in the same session, or scripts end with "Not connected to Microsoft Graph".

- *(observed)* `Import-Module RiskyRolesAnalyzer` pulls in `Az.Resources`, which takes a few
  seconds on first import.
- *(observed)* `Out-ConsoleGridView` is not a dependency; `Show-RiskyRoleAssignment` explains what
  to install when no grid is available (`Microsoft.PowerShell.ConsoleGuiTools` on macOS, Linux or
  Windows; `Out-GridView` ships with PowerShell on Windows).
- *(observed)* The report's **Copy** buttons write to the clipboard when the page is served over
  `http` (checked in Chrome); *(to verify)* some browsers refuse the clipboard API for `file://`
  pages. The command is always shown in full, so select-and-copy works regardless.
- *(observed)* A Graph session built from an Az token (`Connect-MgGraph -AccessToken` with
  `Get-AzAccessToken -ResourceTypeName MSGraph`) reads role assignments, users and groups but gets
  403 on the PIM schedule endpoints, so eligibility and activations are missing. Use
  `Connect-RiskyRolesAnalyzer` for a full audit.
- *(observed)* Az.Resources 10 moved the actions of a role definition into `Permissions[]`; the
  module reads both that and the flattened properties of older versions. Other tooling that reads
  `$definition.Actions` stops seeing custom role permissions on Az.Resources 10.
