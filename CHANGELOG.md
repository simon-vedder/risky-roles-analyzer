# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Module `RiskyRolesAnalyzer` (PowerShell 7.2+), rebuilt from the `RiskyRolesAnalyzer.ps1` script:
  `Connect-RiskyRolesAnalyzer`, `Get-RiskyRoleAssignment`, `Remove-RiskyRoleAssignment`.
- Every rule is a pure function with fixture tests: wildcard action matching with `NotActions`,
  scope classification, scoring, severity bands, credential validity, principal activity, cleanup
  commands, finding assembly.
- Role lists, risky actions and scoring weights in one data file, `RiskyRoleCatalog.psd1`.
- Findings carry a stable `Id`, the underlying `AssignmentId`, `Severity`, and a `Protected` flag
  with reason: inherited through a group, PIM eligible, break-glass (`-BreakGlassAccount`), the
  identity running the audit.
- `Remove-RiskyRoleAssignment`: ShouldProcess with `ConfirmImpact = 'High'`, JSON backup before
  every call, Azure removal by principal, role definition id and scope, Entra removal by
  assignment id, write scope checked before anything happens.
- Default table view for findings and removal results.

### Changed, compared to the script
- An Entra assignment scoped tenant-wide is scored with multiplier 1.0 (the script used 0.85 for
  every Entra scope, which rated a permanent Global Administrator below an Owner at root).
- Assignments inherited from a management group or the root are reported once, not once per
  subscription that inherits them.
- Scores round away from zero (7.65 reads 7.7).
- Az context is restored to the original subscription after the scan.
- PIM eligibility, group-inherited assignments, break-glass accounts and the auditing identity are
  never removed by the tool; the script only printed cleanup commands.

- `Export-RiskyRoleReport`: the script's self-contained HTML report, rebuilt from a template file
  with summary cards, filters, sorting, CSV export, the native cleanup command per finding and a
  selection that builds the `Remove-RiskyRoleAssignment` command for the PowerShell session.
- `Show-RiskyRoleAssignment`: pick findings in `Out-ConsoleGridView` or `Out-GridView`, get the
  original objects back for the pipeline.
- `Restore-RiskyRoleAssignment`: recreate permanent assignments from a backup file, with the same
  confirmation and scope checks as the removal.
- PIM activations are recognised through `roleAssignmentSchedules`, typed `Activated` and protected.
- `Get-RiskyRoleAssignment` warns when an unprotected principal is named like an emergency access
  account (break-glass, emergency access, bg1) and `-BreakGlassAccount` was not passed for it.
- The report shows the organisation display name next to the tenant id when Graph lets it read one.

### Verified
- Synthetic tenant fixture (two subscriptions, one inherited management group assignment, nested
  groups with a cycle, custom Azure and Entra roles, dormant and deactivated app registrations,
  disabled user, PIM eligibility and activation): 130 Pester tests, PSScriptAnalyzer clean. Sample
  report rendered in headless Chrome from synthetic findings.
- Read path on a real tenant (own, Entra ID P2): 8 findings in 56 seconds, report opened, no
  unresolved principals.
- Write path on the same tenant with a test user: Reader on a throwaway resource group and Directory
  Readers, removed with backup, verified gone, restored from the file, verified back, cleaned up.
  Details in docs/verification.md.
