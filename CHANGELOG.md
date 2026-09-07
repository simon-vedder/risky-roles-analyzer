# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added
- A single-file audit script, `dist/Invoke-RiskyRolesAudit.ps1`, attached to every release.
  Download one file, run it, get the report. No module to install, no Gallery to trust, which is
  the right shape for something most people run once a quarter. It is generated from the module
  sources by `tools/Build-StandaloneScript.ps1`, so the rules in it are the tested ones, and CI
  fails when the committed file drifts. The write path is deliberately not in it: removing an
  assignment belongs where the input is typed, every call is confirmed and everything is backed up.
- `docs/commands`, a generated reference: one page per command with its parameters, permissions,
  examples and output type.

### Changed
- `docs/commands` documents the audit script as well, and leads with it. Its twelve parameters,
  the permissions it needs and its examples were only reachable through `Get-Help` before.
- The examples show the plain call. `-BreakGlassAccount` was in every one of them, which read as if
  the audit needed it; it does not, and the report is complete without it.
- The README leads with the script. The module is the second step, for acting on the findings.
- **The module is no longer published to the PowerShell Gallery.** `0.1.0-preview` is unlisted, which
  keeps the name and stops it being found. Installing a module to produce an HTML report is the wrong
  trade for a tool most people run once a quarter. Clone the repository and import it if you want the
  removal path. See [ADR 0003](docs/decisions/0003-the-report-is-a-script-the-module-is-optional.md).
- The report emits native commands only. Each finding already carried its Azure or Graph command; the
  bulk selection now copies those instead of a `Remove-RiskyRoleAssignment` line, with a line saying
  they ask for no confirmation. The report works with no module anywhere in sight.

### Fixed
- The cleanup commands in the report quote role, scope and principal values properly. A role named
  with an apostrophe produced a command that does not parse, and a name crafted as
  `x'; <command> #` would have turned the pasted line into something else. Role names come from the
  tenant being audited and the report offers these strings with a copy button, so they are treated
  as untrusted text now: apostrophes doubled, line breaks collapsed. `Remove-RiskyRoleAssignment`
  was never affected, it removes by role definition id and never builds a command string.

## [0.1.0-preview] - 2026-09-07

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

### Fixed
- Custom Azure roles are read from `Permissions[]`, the shape Az.Resources 10 returns, as well as
  from the flattened `Actions` properties of older versions. With Az.Resources 10 the module warned
  "Could not list role definitions" and rated every custom role as harmless.

### Verified
- Synthetic tenant fixture (two subscriptions, one inherited management group assignment, nested
  groups with a cycle, custom Azure and Entra roles, dormant and deactivated app registrations,
  disabled user, PIM eligibility and activation): 138 Pester tests, PSScriptAnalyzer clean. Sample
  report rendered in headless Chrome from synthetic findings.
- The report's interactive parts driven in headless Chrome over the DevTools protocol: filters,
  search, sorting, selection, removal command popup, clipboard copy, cleanup popups, accept and
  hide, CSV export, narrow viewport; 42 checks (`tests/manual/report-ui.py`).
- Read path on a real tenant (own, Entra ID P2): 8 findings in 56 seconds, report opened, no
  unresolved principals.
- Write path on the same tenant with a test user: Reader on a throwaway resource group and Directory
  Readers, removed with backup, verified gone, restored from the file, verified back, cleaned up.
- Group expansion, custom role rating and disabled-user scoring on the same tenant: a custom role
  assignable only in a throwaway resource group, assigned to a security group with the test user
  as member and directly to the user, user disabled for the audit; the inherited finding was
  refused by `Remove-`, the other two removed and restored from the backup, then everything
  deleted (`tests/manual/real-tenant-group-custom-role.ps1`).
- PIM activation detection on the same tenant, with a harmless role instead of a privileged one: a
  Directory Readers eligibility activated for an hour was typed `Activated` and protected, scored
  above its own eligibility, was not mistaken for a permanent assignment, and `Remove- -WhatIf`
  refused both (`tests/manual/real-tenant-pim-activation.ps1`). Details in docs/verification.md.
- `Show-RiskyRoleAssignment` driven against real findings with the grid substituted: the columns the
  grid is handed, the title and the multiple-selection mode, the originals coming back for the picked
  rows, an empty selection returning nothing. The three that need no tenant are Pester tests now.

[Unreleased]: https://github.com/simon-vedder/risky-roles-analyzer/compare/v0.1.0...HEAD
[0.1.0-preview]: https://github.com/simon-vedder/risky-roles-analyzer/releases/tag/v0.1.0
