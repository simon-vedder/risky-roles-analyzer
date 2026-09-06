# Known issues and sharp edges

Every entry says where it comes from: *(observed)* in this project's lab or a real run,
*(Microsoft)* from official documentation, *(to verify)* on the lab list. Nothing here is guessed.

## Behaviour

- *(to verify)* An **activated PIM assignment** appears in `roleManagement/directory/roleAssignments`
  like a permanent one. The module cannot tell the two apart yet and reports the activation as
  `Permanent`. Removing it through `Remove-RiskyRoleAssignment` ends the activation, the
  eligibility stays. The fix is `roleAssignmentSchedules` with its `assignmentType`, planned.
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
- *(observed)* `Out-ConsoleGridView` is not a dependency; install
  `Microsoft.PowerShell.ConsoleGuiTools` to use the pick-and-remove pipeline from the README on
  macOS or Linux. On Windows, `Out-GridView` works the same way.
