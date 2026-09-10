# Show-RiskyRoleAssignment

> Pick findings in a grid and pass the picked ones down the pipeline.

Opens the findings in Out-ConsoleGridView (any platform, from the
Microsoft.PowerShell.ConsoleGuiTools module) or Out-GridView (Windows) with the columns that
matter for a decision, and returns the original finding objects for the rows you selected.
Protected findings are shown too; Remove-RiskyRoleAssignment refuses them later anyway.

## Syntax

```powershell
Show-RiskyRoleAssignment [-InputObject] <RiskyRoleAssignment[]> [[-Title] <string>] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: None. It filters objects you already have.

Prerequisites: A grid view and an interactive terminal. Out-ConsoleGridView from
Microsoft.PowerShell.ConsoleGuiTools on any platform, or Out-GridView on Windows. Without one it
throws and says what to install. Selecting nothing returns nothing rather than everything.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-InputObject` | Object[] | yes | yes |  | Findings from Get-RiskyRoleAssignment. |
| `-Title` | String | no | no | RiskyRolesAnalyzer: select assignments, then confirm | Window title. |

## Examples

### Example 1

```powershell
Get-RiskyRoleAssignment | Show-RiskyRoleAssignment | Remove-RiskyRoleAssignment -WhatIf
```

### Example 2

```powershell
$picked = $findings | Show-RiskyRoleAssignment -Title 'Contoso: assignments to remove'
```

## Output

- RiskyRolesAnalyzer.RiskyRoleAssignment

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
