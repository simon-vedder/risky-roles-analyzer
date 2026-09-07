# Restore-RiskyRoleAssignment

> Put back assignments from a backup file that Remove-RiskyRoleAssignment wrote.

Reads the JSON backup (or takes the same objects from the pipeline) and recreates each
permanent assignment: Azure with New-AzRoleAssignment by principal, role definition id and
scope; Entra by posting a new role assignment for the principal, role and directory scope.
Restoring privilege is as serious as removing it, so every assignment is confirmed
(ConfirmImpact High) and -WhatIf shows the plan.

Entries the module cannot restore are reported and skipped: PIM eligibility and activations
(manage them in PIM), assignments inherited through a group (the group's assignment was
never removed), entries without the ids needed.

## Syntax

```powershell
Restore-RiskyRoleAssignment [-Path] <string> [-WhatIf] [-Confirm] [<CommonParameters>]

Restore-RiskyRoleAssignment -InputObject <Object[]> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

Required permissions: Azure: Microsoft.Authorization/roleAssignments/write on the scope.
Entra: RoleManagement.ReadWrite.Directory (Connect-RiskyRolesAnalyzer -RequestWriteScopes).

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Path` | String | yes | no |  | A backup file written by Remove-RiskyRoleAssignment. |
| `-InputObject` | Object[] | yes | yes |  | Backup entries, for example from Get-Content backup.json \| ConvertFrom-Json. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
Restore-RiskyRoleAssignment -Path ./RiskyRolesAnalyzer-backup-20260906-142200.json -WhatIf
```

### Example 2

```powershell
Get-Content ./backup.json | ConvertFrom-Json | Where-Object PrincipalName -eq 'Deploy App' | Restore-RiskyRoleAssignment
```

## Output

- RiskyRolesAnalyzer.RiskyRoleAssignmentRestore

---

[All commands](README.md) · [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
