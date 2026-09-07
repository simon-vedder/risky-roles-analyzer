# RiskyRolesAnalyzer command reference

Finds privileged Azure RBAC and Entra ID role assignments that posture tools miss, and lets you remove them safely.

## Requirements

| | |
|---|---|
| Module version | 0.1.0-preview |
| PowerShell | 7.2+ (Core) |
| Required modules | `Az.Accounts` 3.0.0+, `Az.Resources` 7.0.0+, `Microsoft.Graph.Authentication` 2.15.0+ |
| Getting it | Clone the repository and `Import-Module ./src/RiskyRolesAnalyzer/RiskyRolesAnalyzer.psd1` |

Per-command permissions are on each page under **Requirements and notes**.

## Commands

| Command | What it does |
|---|---|
| [Connect-RiskyRolesAnalyzer](Connect-RiskyRolesAnalyzer.md) | Sign in to Microsoft Graph and Azure with exactly the scopes the audit needs. |
| [Export-RiskyRoleReport](Export-RiskyRoleReport.md) | Write the findings to a self-contained HTML report. |
| [Get-RiskyRoleAssignment](Get-RiskyRoleAssignment.md) | Every privileged Azure RBAC and Entra ID role assignment in the tenant, scored and explained. |
| [Remove-RiskyRoleAssignment](Remove-RiskyRoleAssignment.md) | Remove privileged role assignments that Get-RiskyRoleAssignment found, one prompt at a time. |
| [Restore-RiskyRoleAssignment](Restore-RiskyRoleAssignment.md) | Put back assignments from a backup file that Remove-RiskyRoleAssignment wrote. |
| [Show-RiskyRoleAssignment](Show-RiskyRoleAssignment.md) | Pick findings in a grid and pass the picked ones down the pipeline. |

---

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not these files.*
