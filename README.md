<p align="center"><img src="docs/images/hero.png" alt="RiskyRolesAnalyzer: Every privileged role assignment in your tenant, including the ones hiding behind groups, custom roles and dormant apps." width="100%"></p>

<p align="center">
  <a href="https://github.com/simon-vedder/risky-roles-analyzer/actions/workflows/ci.yml"><img src="https://github.com/simon-vedder/risky-roles-analyzer/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://www.powershellgallery.com/packages/RiskyRolesAnalyzer"><img src="https://img.shields.io/powershellgallery/v/RiskyRolesAnalyzer?include_prereleases&label=PowerShell%20Gallery" alt="PowerShell Gallery"></a>
  <img src="https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white" alt="PowerShell 7.2+">
  <img src="https://img.shields.io/badge/access-read--only%20by%20default-16a34a" alt="Read-only by default">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
</p>

**Every privileged role assignment in your tenant, including the ones hiding behind groups, custom roles and dormant apps.**

Finds privileged Azure RBAC and Entra ID role assignments that posture tools miss, and lets you remove them safely.

## Why

- What Microsoft ships for this, and where it stops.
- What the community has, and what it does not cover.
- The population this is for.

## Features

- **Read-only by default.** `Get-RiskyRoleAssignment` needs read scopes only and returns objects, not a log.
- **Rules you can read.** Every decision is a pure function with a test on a fixture.
- **Remove with a safety net.** `Remove-RiskyRoleAssignment` prompts per object, writes a JSON backup before
  it acts, and refuses anything marked protected.
- **Honest about limits.** [When not to use this](docs/when-not-to-use-this.md) and
  [KNOWN-ISSUES.md](KNOWN-ISSUES.md) list every sharp edge found.

## Quick start

```powershell
Install-Module RiskyRolesAnalyzer -AllowPrerelease

# 1. Look. Nothing changes.
Get-RiskyRoleAssignment | Format-Table Name, Severity, Reason

# 2. Pick and remove, with a prompt per object and a backup file. -WhatIf shows the plan.
Get-RiskyRoleAssignment -MinimumSeverity High | Remove-RiskyRoleAssignment -WhatIf
Get-RiskyRoleAssignment | Out-ConsoleGridView -PassThru | Remove-RiskyRoleAssignment
```

## Safety

The tool proposes, you decide. `Remove-RiskyRoleAssignment` accepts only objects that `Get-RiskyRoleAssignment` produced,
asks before every object (`ConfirmImpact = 'High'`), writes every object to a JSON file before the
call, and reports protected objects instead of touching them. `-WhatIf` works everywhere.


## Permissions

```
<exact Graph scopes or RBAC actions for the read path>
```

The write path adds `<...>` and is only requested with the switch that enables it.

## Status

Pre-release `0.1.0-preview`. What is verified is in [docs/verification.md](docs/verification.md);
what is not is in [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

## Documentation

- Tool page: [simonvedder.com/tools/risky-roles-analyzer](https://simonvedder.com/tools/risky-roles-analyzer)
- [Verification log](docs/verification.md), [known issues](KNOWN-ISSUES.md), [when not to use this](docs/when-not-to-use-this.md)
- [Architecture decisions](docs/decisions), [releasing](docs/release.md), [contributing](CONTRIBUTING.md), [security](SECURITY.md), [changelog](CHANGELOG.md)

## License

MIT.
