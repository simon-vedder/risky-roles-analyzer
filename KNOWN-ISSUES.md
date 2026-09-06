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

- *(observed)* `Import-Module RiskyRolesAnalyzer` pulls in `Az.Resources`, which takes a few
  seconds on first import.
- *(observed)* `Out-ConsoleGridView` is not a dependency; `Show-RiskyRoleAssignment` explains what
  to install when no grid is available (`Microsoft.PowerShell.ConsoleGuiTools` on macOS, Linux or
  Windows; `Out-GridView` ships with PowerShell on Windows).
- *(to verify)* The report's **Copy** buttons use the browser clipboard API, which some browsers
  refuse for `file://` pages. The command is always shown in full, so select-and-copy works regardless.
