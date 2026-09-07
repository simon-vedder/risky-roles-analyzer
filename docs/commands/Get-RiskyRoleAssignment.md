# Get-RiskyRoleAssignment

> Every privileged Azure RBAC and Entra ID role assignment in the tenant, scored and explained.

Read-only audit of privileged access with the blind spots posture tools tend to have:

  - custom Azure RBAC and Entra directory roles whose actions confer privilege
    (roleAssignments/write, users/password/update, denyAssignments/delete and more)
  - assignments inherited through nested groups, listed per member with the group
  - app registrations holding privileged roles with expired or no credentials
  - app registrations deactivated in the portal, service principals with sign-in disabled
    or blocked by Microsoft
  - disabled users that still hold permanent privileged assignments
  - permanent versus PIM eligible Entra assignments, scored separately

Each finding carries a 0 to 10 risk score, a severity, the native cleanup command, and a
Protected flag for the assignments Remove-RiskyRoleAssignment must not touch: inherited
through a group, PIM eligible, break-glass accounts, and the identity running the audit.

Needs an existing Microsoft Graph session with the read scopes and, unless -SkipAzure is
set, an Az session in the same tenant. Connect-RiskyRolesAnalyzer sets both up.

## Syntax

```powershell
Get-RiskyRoleAssignment [[-SubscriptionId] <string[]>] [[-AdditionalAzureRole] <string[]>] [[-AdditionalEntraRole] <string[]>] [[-BreakGlassAccount] <string[]>] [[-MinimumSeverity] <string>] [-SkipAzure] [-SkipEntra] [-SkipPim] [<CommonParameters>]
```

## Requirements and notes

Required permissions, read path only:
  Graph: RoleManagement.Read.Directory, Directory.Read.All, Group.Read.All, Application.Read.All
  Azure: Reader on every subscription in scope (a management group assignment works)

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-SubscriptionId` | String[] | no | no |  | Audit only these subscriptions. Default: every enabled subscription in the tenant. |
| `-AdditionalAzureRole` | String[] | no | no |  | Built-in or custom Azure role names to treat as privileged on top of the catalog. |
| `-AdditionalEntraRole` | String[] | no | no |  | Entra directory role display names to treat as privileged on top of the catalog. |
| `-BreakGlassAccount` | String[] | no | no |  | User principal names or object ids of emergency access accounts. Their assignments are reported and marked Protected. The module cannot know which accounts these are; it warns when an unprotected principal is named like one. |
| `-SkipAzure` | SwitchParameter | no | no |  | Entra ID only; no Az session needed. |
| `-SkipEntra` | SwitchParameter | no | no |  | Azure RBAC only. |
| `-SkipPim` | SwitchParameter | no | no |  | Do not query PIM eligible assignments (tenants without Entra ID P2). |
| `-MinimumSeverity` | String | no | no | Info | Return findings of this severity and above. Default: Info, which is everything. |

## Examples

### Example 1

```powershell
Connect-RiskyRolesAnalyzer
Get-RiskyRoleAssignment | Format-Table
```

### Example 2

```powershell
Get-RiskyRoleAssignment -MinimumSeverity High -BreakGlassAccount 'breakglass@contoso.com' | Export-Csv privileged.csv
```

### Example 3

```powershell
Get-RiskyRoleAssignment -SkipAzure -SkipPim | Where-Object ActivityStatus -ne 'Active'
```

## Output

- RiskyRolesAnalyzer.RiskyRoleAssignment

---

[All commands](README.md) · [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
