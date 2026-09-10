# Remove-RiskyRoleAssignment

> Remove privileged role assignments that Get-RiskyRoleAssignment found, one prompt at a time.

The write path, built so that nothing happens by accident:

  - accepts only the objects Get-RiskyRoleAssignment produced, never free-form names
  - asks before every assignment (ConfirmImpact High); -WhatIf shows the plan
  - writes every assignment to a JSON backup file before the call that removes it
  - refuses Protected findings and reports them instead: inherited through a group,
    PIM eligible, break-glass accounts, the identity running the audit

Azure RBAC assignments are removed with Remove-AzRoleAssignment by principal, role
definition id and scope. Entra permanent assignments are removed by their assignment id
through Graph, which needs RoleManagement.ReadWrite.Directory
(Connect-RiskyRolesAnalyzer -RequestWriteScopes). Nothing is removed for a group's
members: remove the group's own assignment, or the membership, deliberately.

## Syntax

```powershell
Remove-RiskyRoleAssignment [-InputObject] <RiskyRoleAssignment[]> [[-BackupPath] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: On Azure, Microsoft.Authorization/roleAssignments/delete on the scope
(Owner or User Access Administrator). On Entra, RoleManagement.ReadWrite.Directory plus a role
that may remove the assignment (Privileged Role Administrator).

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-InputObject` | Object[] | yes | yes |  | Findings from Get-RiskyRoleAssignment. |
| `-BackupPath` | String | no | no | (Join-Path (Get-Location) ('RiskyRolesAnalyzer-backup-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))) | JSON file that receives every assignment before it is removed. Default: ./RiskyRolesAnalyzer-backup-<timestamp>.json in the current directory. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
Get-RiskyRoleAssignment -MinimumSeverity High | Remove-RiskyRoleAssignment -WhatIf
```

### Example 2

```powershell
Get-RiskyRoleAssignment | Where-Object ActivityStatus -eq 'Disabled' | Show-RiskyRoleAssignment | Remove-RiskyRoleAssignment
```

## Output

- RiskyRolesAnalyzer.RiskyRoleAssignmentRemoval

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
