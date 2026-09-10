function Connect-RiskyRolesAnalyzer {
    <#
    .SYNOPSIS
    Sign in to Microsoft Graph and Azure with exactly the scopes the audit needs.

    .DESCRIPTION
    Connects Microsoft Graph with the read-only scopes Get-RiskyRoleAssignment uses
    (RoleManagement.Read.Directory, Directory.Read.All, Group.Read.All, Application.Read.All)
    and Azure with Connect-AzAccount for the same tenant. Sessions that already carry the scopes
    are reused. The write scope RoleManagement.ReadWrite.Directory is requested only with
    -RequestWriteScopes; Remove-RiskyRoleAssignment needs it for Entra findings, nothing else does.

    .PARAMETER TenantId
    Tenant to sign in to. Without it, the Graph sign-in picks the account's home tenant and
    Azure follows the tenant Graph ended up in.

    .PARAMETER RequestWriteScopes
    Also request RoleManagement.ReadWrite.Directory. Off by default: the audit is read-only.

    .PARAMETER SkipAzure
    Graph only. Use with Get-RiskyRoleAssignment -SkipAzure when Azure RBAC is out of scope.

    .PARAMETER UseDeviceCode
    Device code sign-in for both services, for hosts without a browser.

    .EXAMPLE
    Connect-RiskyRolesAnalyzer

    .EXAMPLE
    Connect-RiskyRolesAnalyzer -TenantId 00000000-0000-0000-0000-000000000000 -RequestWriteScopes

    .OUTPUTS
    System.Management.Automation.PSCustomObject with TenantId, GraphAccount, GraphScopes and AzureAccount.

    .NOTES
    RequiredPermissions: On the read path, the Graph delegated scopes
    RoleManagement.Read.Directory, Directory.Read.All, Group.Read.All and Application.Read.All,
    which a user consents to at sign-in, plus Azure Reader on every subscription you want to audit,
    or at a management group above them. Entra ID P2 for the PIM parts; without it
    Get-RiskyRoleAssignment warns once and continues.

    The write path adds RoleManagement.ReadWrite.Directory (-RequestWriteScopes) and, on the Azure
    side, Microsoft.Authorization/roleAssignments/delete on the scope.

    Session: The Graph session lives in this PowerShell process. A new pwsh starts without it,
    while the Azure session is read back from disk, so run Connect- and Get- in the same session.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [switch]$RequestWriteScopes,

        [Parameter()]
        [switch]$SkipAzure,

        [Parameter()]
        [switch]$UseDeviceCode
    )

    $scopes = @($script:Catalog.GraphScopes.Read)
    if ($RequestWriteScopes) { $scopes += $script:Catalog.GraphScopes.Write }

    $graph = Get-MgContext -ErrorAction SilentlyContinue
    $graphTenant = if ($graph) { [string](Get-PropertyOrDefault -InputObject $graph -Name 'TenantId' -Default '') } else { '' }
    $needsGraph = (-not $graph) -or (-not (Test-RiskyRoleGraphScope -Scope $scopes)) -or ($TenantId -and $graphTenant -ne $TenantId)
    if ($needsGraph) {
        $graphArgs = @{ Scopes = $scopes; NoWelcome = $true; ErrorAction = 'Stop' }
        if ($TenantId) { $graphArgs.TenantId = $TenantId }
        if ($UseDeviceCode) { $graphArgs.UseDeviceCode = $true }
        Write-Verbose "Connecting Microsoft Graph with scopes: $($scopes -join ', ')"
        $null = Connect-MgGraph @graphArgs
        $graph = Get-MgContext -ErrorAction Stop
    }
    $tenant = [string](Get-PropertyOrDefault -InputObject $graph -Name 'TenantId' -Default '')

    $azureAccount = $null
    if (-not $SkipAzure) {
        $azure = Get-AzContext -ErrorAction SilentlyContinue
        $azureTenant = if ($azure) { [string](Get-PropertyOrDefault -InputObject (Get-PropertyOrDefault -InputObject $azure -Name 'Tenant' -Default $null) -Name 'Id' -Default '') } else { '' }
        if (-not $azure -or ($tenant -and $azureTenant -ne $tenant)) {
            $azureArgs = @{ ErrorAction = 'Stop' }
            if ($tenant) { $azureArgs.TenantId = $tenant }
            if ($UseDeviceCode) { $azureArgs.UseDeviceCode = $true }
            Write-Verbose "Connecting Azure for tenant $tenant"
            $null = Connect-AzAccount @azureArgs
            $azure = Get-AzContext -ErrorAction Stop
        }
        $azureAccount = [string](Get-PropertyOrDefault -InputObject (Get-PropertyOrDefault -InputObject $azure -Name 'Account' -Default $null) -Name 'Id' -Default '')
    }

    [pscustomobject]@{
        TenantId     = $tenant
        GraphAccount = Get-PropertyOrDefault -InputObject $graph -Name 'Account' -Default $null
        GraphScopes  = @(Get-PropertyOrDefault -InputObject $graph -Name 'Scopes' -Default @())
        AzureAccount = $azureAccount
        WriteScope   = (Test-RiskyRoleGraphScope -Scope $script:Catalog.GraphScopes.Write)
    }
}
