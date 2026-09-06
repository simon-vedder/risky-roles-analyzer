# Builds docs/sample/report.html from synthetic findings, without a tenant. Run after changing
# Resources/report.html, then re-render docs/images/report.png (recipe in docs/images/README.md).
Import-Module (Join-Path $PSScriptRoot ".." ".." "src" "RiskyRolesAnalyzer" "RiskyRolesAnalyzer.psd1") -Force
$m = Get-Module RiskyRolesAnalyzer
function P($id, $type, $name, $upn, $status, $reason, $enabled = $true, $appId = $null) {
    [pscustomobject]@{ ObjectId = $id; Type = $type; DisplayName = $name; UPN = $upn; AppId = $appId; IsEnabled = $enabled; ActivityStatus = $status; ActivityReason = $reason }
}
$sub = '/subscriptions/3f2c9a1e-7b4d-4e8f-9a21-6c5d8e7f0a12'
$mg = '/providers/Microsoft.Management/managementGroups/contoso-root'
$alice = P '8a1f…c3' 'User' 'Alice Admin' 'alice.admin@contoso.com' 'Active' $null
$bob = P '2b7e…91' 'User' 'Bob Leaver' 'bob.leaver@contoso.com' 'Disabled' 'Account disabled' $false
$carol = P '5c0d…4a' 'User' 'Carol Ops' 'carol.ops@contoso.com' 'Active' $null
$glass = P '9e4b…77' 'User' 'Emergency Access 01' 'breakglass01@contoso.com' 'Active' $null
$deploy = P 'd41a…08' 'AppRegistration' 'Legacy Deploy App' $null 'NoValidCredential' 'All 2 credentials expired' $true 'a7c1…e5'
$retired = P 'f0b2…3c' 'AppRegistration' 'Retired Sync App' $null 'Disabled' 'App registration deactivated' $true 'b8d2…f6'
$mi = P '6d3e…b2' 'ManagedIdentity' 'vm-web-01-identity' $null 'Active' $null $true 'c9e3…07'
$saas = P '7e5f…d9' 'EnterpriseApp' 'Third Party SaaS Connector' $null 'Active' $null $true 'd0f4…18'
$group = P '1a2b…c0' 'Group' 'Cloud Admins' $null 'Active' $null
$findings = & $m {
    param($sub, $mg, $alice, $bob, $carol, $glass, $deploy, $retired, $mi, $saas, $group)
    $bg = @('breakglass01@contoso.com')
    Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'Global Administrator' -RoleDefinitionId '62e90394-69f5-4237-9190-012177145e10' -Scope '/' -ScopeName 'Tenant-wide' -AssignmentType Permanent -AssignmentId 'lAPpYvVpN0KRkAEhd0RIS…' -Principal $alice -BreakGlassAccount $bg -CurrentAccount 'me@contoso.com'
    Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'Global Administrator' -RoleDefinitionId '62e90394-69f5-4237-9190-012177145e10' -Scope '/' -ScopeName 'Tenant-wide' -AssignmentType Permanent -AssignmentId 'lAPpYvVpN0KRkAEhd0RIT…' -Principal $glass -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'Global Administrator' -RoleDefinitionId '62e90394-69f5-4237-9190-012177145e10' -Scope '/' -ScopeName 'Tenant-wide' -AssignmentType Eligible -AssignmentId 're-1' -Principal $carol -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'Privileged Role Administrator' -RoleDefinitionId 'e8611ab8-c189-46e8-94e1-60213ab1f814' -Scope '/' -ScopeName 'Tenant-wide' -AssignmentType Activated -AssignmentId 'ra-act' -Principal $carol -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'User Administrator' -RoleDefinitionId 'fe930be7-5e62-47db-91af-98c3a49a38b1' -Scope '/' -ScopeName 'Tenant-wide' -AssignmentType Permanent -AssignmentId 'ra-bob' -Principal $bob -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'Cloud Application Administrator' -RoleDefinitionId '158c047a-c907-4556-b7ef-446551a6b5f7' -Scope '/' -ScopeName 'Tenant-wide' -AssignmentType Permanent -AssignmentId 'ra-ret' -Principal $retired -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'Password Helper' -RoleDefinitionId 'c1a2…' -Scope '/administrativeUnits/au-helpdesk' -ScopeName 'Administrative unit: au-helpdesk' -AssignmentType Permanent -AssignmentId 'ra-saas' -Principal $saas -IsCustomRole $true -RiskyAction @('microsoft.directory/users/password/update') -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Azure -RoleName 'Owner' -RoleDefinitionId '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -Scope $mg -ScopeName 'MG: contoso-root' -AssignmentType Permanent -AssignmentId "$mg/providers/Microsoft.Authorization/roleAssignments/1" -Principal $group -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Azure -RoleName 'Owner' -RoleDefinitionId '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -Scope $mg -ScopeName 'MG: contoso-root' -AssignmentType Permanent -AssignmentId "$mg/providers/Microsoft.Authorization/roleAssignments/1" -Principal $alice -ViaGroup 'Cloud Admins' -ViaGroupId '1a2b…c0' -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Azure -RoleName 'Owner' -RoleDefinitionId '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -Scope $mg -ScopeName 'MG: contoso-root' -AssignmentType Permanent -AssignmentId "$mg/providers/Microsoft.Authorization/roleAssignments/1" -Principal $bob -ViaGroup 'Cloud Admins' -ViaGroupId '1a2b…c0' -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Azure -RoleName 'Custom Automation Role' -RoleDefinitionId 'aaaaaaaa-1111-2222-3333-444444444444' -Scope $sub -ScopeName 'Production' -AssignmentType Permanent -AssignmentId "$sub/providers/Microsoft.Authorization/roleAssignments/2" -Principal $alice -IsCustomRole $true -RiskyAction @('Microsoft.Authorization/roleAssignments/write', 'Microsoft.Authorization/roleDefinitions/write', 'Microsoft.Authorization/elevateAccess/action', 'Microsoft.Authorization/policyAssignments/write', 'Microsoft.Authorization/policyDefinitions/write') -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Azure -RoleName 'Contributor' -RoleDefinitionId 'b24988ac-6180-42a0-ab88-20f7382dd24c' -Scope $sub -ScopeName 'Production' -AssignmentType Permanent -AssignmentId "$sub/providers/Microsoft.Authorization/roleAssignments/3" -Principal $deploy -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Azure -RoleName 'Owner' -RoleDefinitionId '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -Scope "$sub/resourceGroups/rg-web-prod" -ScopeName 'Production' -AssignmentType Permanent -AssignmentId "$sub/resourceGroups/rg-web-prod/providers/Microsoft.Authorization/roleAssignments/4" -Principal $mi -BreakGlassAccount $bg
    Resolve-RiskyRoleAssignmentFinding -RoleScope Azure -RoleName 'Key Vault Administrator' -RoleDefinitionId '00482a5a-887f-4fb3-b363-3b7fe8e74483' -Scope "$sub/resourceGroups/rg-web-prod/providers/Microsoft.KeyVault/vaults/kv-web-prod" -ScopeName 'Production' -AssignmentType Permanent -AssignmentId "$sub/resourceGroups/rg-web-prod/providers/Microsoft.KeyVault/vaults/kv-web-prod/providers/Microsoft.Authorization/roleAssignments/5" -Principal $saas -BreakGlassAccount $bg
} $sub $mg $alice $bob $carol $glass $deploy $retired $mi $saas $group
$findings = $findings | Sort-Object -Property @{ Expression = 'RiskScore'; Descending = $true }

$file = $findings | Export-RiskyRoleReport -Path (Join-Path $PSScriptRoot "report.html") -TenantId 'contoso.onmicrosoft.com' -TenantName 'Contoso' -Title 'Contoso privileged role audit'
"written $($file.FullName) $($file.Length) bytes"
