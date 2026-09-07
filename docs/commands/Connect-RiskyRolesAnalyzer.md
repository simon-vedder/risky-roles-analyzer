# Connect-RiskyRolesAnalyzer

> Sign in to Microsoft Graph and Azure with exactly the scopes the audit needs.

Connects Microsoft Graph with the read-only scopes Get-RiskyRoleAssignment uses
(RoleManagement.Read.Directory, Directory.Read.All, Group.Read.All, Application.Read.All)
and Azure with Connect-AzAccount for the same tenant. Sessions that already carry the scopes
are reused. The write scope RoleManagement.ReadWrite.Directory is requested only with
-RequestWriteScopes; Remove-RiskyRoleAssignment needs it for Entra findings, nothing else does.

## Syntax

```powershell
Connect-RiskyRolesAnalyzer [[-TenantId] <string>] [-RequestWriteScopes] [-SkipAzure] [-UseDeviceCode] [<CommonParameters>]
```

## Requirements and notes

Required permissions, read path: Graph delegated scopes RoleManagement.Read.Directory,
Directory.Read.All, Group.Read.All and Application.Read.All, which a user consents to at sign-in;
Azure Reader on every subscription you want to audit, or at a management group above them.
Entra ID P2 for the PIM parts; without it Get-RiskyRoleAssignment warns once and continues.

The write path adds RoleManagement.ReadWrite.Directory (-RequestWriteScopes) and, on the Azure
side, Microsoft.Authorization/roleAssignments/delete on the scope.

The Graph session lives in this PowerShell process. A new pwsh starts without it, while the Azure
session is read back from disk, so run Connect- and Get- in the same session.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-TenantId` | String | no | no |  | Tenant to sign in to. Without it, the Graph sign-in picks the account's home tenant and Azure follows the tenant Graph ended up in. |
| `-RequestWriteScopes` | SwitchParameter | no | no |  | Also request RoleManagement.ReadWrite.Directory. Off by default: the audit is read-only. |
| `-SkipAzure` | SwitchParameter | no | no |  | Graph only. Use with Get-RiskyRoleAssignment -SkipAzure when Azure RBAC is out of scope. |
| `-UseDeviceCode` | SwitchParameter | no | no |  | Device code sign-in for both services, for hosts without a browser. |

## Examples

### Example 1

```powershell
Connect-RiskyRolesAnalyzer
```

### Example 2

```powershell
Connect-RiskyRolesAnalyzer -TenantId 00000000-0000-0000-0000-000000000000 -RequestWriteScopes
```

## Output

- System.Management.Automation.PSCustomObject with TenantId, GraphAccount, GraphScopes and AzureAccount.

---

[All commands](README.md) · [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
