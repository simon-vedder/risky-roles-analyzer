# Export-RiskyRoleReport

> Write the findings to a self-contained HTML report.

One file, no external resources, opens anywhere: summary cards, search, filters, sortable
columns, CSV export, the native cleanup command per finding, and a checkbox per removable
finding that builds the Remove-RiskyRoleAssignment command for your PowerShell session.
Nothing runs from the page; it only helps you decide and copy.

## Syntax

```powershell
Export-RiskyRoleReport [[-InputObject] <RiskyRoleAssignment[]>] [[-Path] <string>] [[-Title] <string>] [[-TenantId] <string>] [[-TenantName] <string>] [-Open] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

Required permissions: none beyond what produced the findings. The report is rendered from the
objects you pass in. The tenant name is looked up through Graph when a session exists and the
organisation is readable; without it the header shows the tenant id alone.

The file is self-contained: no external scripts, styles or fonts, nothing is sent anywhere, and
the findings are embedded as JSON. It is safe to hand to someone outside your organisation only
if the findings themselves are, because it contains principal names, ids and scopes.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-InputObject` | Object[] | no | yes |  | Findings from Get-RiskyRoleAssignment. |
| `-Path` | String | no | no | (Join-Path (Get-Location) ('RiskyRolesAnalyzer-report-{0:yyyyMMdd-HHmmss}.html' -f (Get-Date))) | Where to write the report. Default: ./RiskyRolesAnalyzer-report-<timestamp>.html. |
| `-Title` | String | no | no | Privileged Role Audit | Heading of the report. Default: Privileged Role Audit. |
| `-TenantId` | String | no | no |  | Shown in the header. Default: the tenant of the current Graph session. |
| `-TenantName` | String | no | no |  | Shown next to the id. Default: the organisation display name from Graph, when readable. |
| `-Open` | SwitchParameter | no | no |  | Open the report in the default browser after writing it. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
$findings = Get-RiskyRoleAssignment
$findings | Export-RiskyRoleReport -Open
```

### Example 2

```powershell
Get-RiskyRoleAssignment -SkipAzure | Export-RiskyRoleReport -Path ./entra-roles.html -Title 'Contoso Entra roles'
```

## Output

- System.IO.FileInfo

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
