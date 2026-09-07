# Known issues and sharp edges

Every entry says where it comes from: *(observed)* in this project's lab or a real run,
*(Microsoft)* from official documentation, *(to verify)* on the lab list. Nothing here is guessed.

## Behaviour

- *(observed)* An **activated PIM assignment** appears in `roleManagement/directory/roleAssignments`
  like a permanent one. The module reads `roleAssignmentSchedules` and types the ones it reports as
  `Activated`, which are protected. Verified on a real tenant with a directory-scoped activation
  (`tests/manual/real-tenant-pim-activation.ps1`): the activation was typed `Activated`, not
  `Permanent`, and `Remove-` refused it. *(to verify)* Activations scoped to an administrative unit
  rather than the whole directory; an activation the schedules miss would read as `Permanent`, and
  removing it would end the activation, not the eligibility.
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
- *(observed)* A **saved audit cannot be piped back in**. `Export-Clixml` and `Import-Clixml` round
  trip the data, but PowerShell renames the type to `Deserialized.RiskyRolesAnalyzer.RiskyRoleAssignment`,
  and `Remove-`, `Show-` and `Export-RiskyRoleReport` take typed input only, so they refuse it with a
  parameter binding error. `Restore-RiskyRoleAssignment` is unaffected: it reads the JSON backup and
  takes untyped input by design. Re-run `Get-RiskyRoleAssignment`, or put the type back:

  ```powershell
  $findings = @(Import-Clixml ./findings.xml | ForEach-Object {
      $copy = $_ | Select-Object -Property *
      $copy.PSObject.TypeNames.Insert(0, 'RiskyRolesAnalyzer.RiskyRoleAssignment')
      $copy
  })
  ```

- *(observed)* PIM refuses `selfDeactivate` in the first minutes after an activation, and it refuses
  `adminRemove` on an eligibility while an assignment derived from it is still active. Anything that
  activates a role for a test has to wait, deactivate, then remove the eligibility, in that order.
- *(observed)* Az.Resources 10 moved the actions of a role definition into `Permissions[]`; the
  module reads both that and the flattened properties of older versions. Other tooling that reads
  `$definition.Actions` stops seeing custom role permissions on Az.Resources 10.
