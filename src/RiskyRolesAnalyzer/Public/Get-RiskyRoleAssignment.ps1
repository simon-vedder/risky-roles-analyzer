function Get-RiskyRoleAssignment {
    <#
    .SYNOPSIS
    Every privileged Azure RBAC and Entra ID role assignment in the tenant, scored and explained.

    .DESCRIPTION
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
    Protected flag for the assignments nothing here offers for removal: inherited
    through a group, PIM eligible, break-glass accounts, and the identity running the audit.

    Needs an existing Microsoft Graph session with the read scopes and, unless -SkipAzure is
    set, an Az session in the same tenant. Connect-RiskyRolesAnalyzer sets both up.

    .PARAMETER SubscriptionId
    Audit only these subscriptions. Default: every enabled subscription in the tenant.

    .PARAMETER AdditionalAzureRole
    Built-in or custom Azure role names to treat as privileged on top of the catalog.

    .PARAMETER AdditionalEntraRole
    Entra directory role display names to treat as privileged on top of the catalog.

    .PARAMETER BreakGlassAccount
    User principal names or object ids of emergency access accounts. Their assignments are
    reported and marked Protected. It cannot know which accounts these are; it warns when
    an unprotected principal is named like one.

    .PARAMETER SkipAzure
    Entra ID only; no Az session needed.

    .PARAMETER SkipEntra
    Azure RBAC only.

    .PARAMETER SkipPim
    Do not query PIM eligible assignments (tenants without Entra ID P2).

    .PARAMETER MinimumSeverity
    Return findings of this severity and above. Default: Info, which is everything.

    .EXAMPLE
    Connect-RiskyRolesAnalyzer
    Get-RiskyRoleAssignment | Format-Table

    .EXAMPLE
    Get-RiskyRoleAssignment -MinimumSeverity High -BreakGlassAccount 'breakglass@contoso.com' | Export-Csv privileged.csv

    .EXAMPLE
    Get-RiskyRoleAssignment -SkipAzure -SkipPim | Where-Object ActivityStatus -ne 'Active'

    .OUTPUTS
    RiskyRolesAnalyzer.RiskyRoleAssignment

    .NOTES
    RequiredPermissions: Read only. On Graph, RoleManagement.Read.Directory, Directory.Read.All,
    Group.Read.All and Application.Read.All. On Azure, Reader on every subscription in scope (a
    management group assignment works).
    #>
    [CmdletBinding()]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignment')]
    param(
        [Parameter()]
        [string[]]$SubscriptionId,

        [Parameter()]
        [string[]]$AdditionalAzureRole,

        [Parameter()]
        [string[]]$AdditionalEntraRole,

        [Parameter()]
        [string[]]$BreakGlassAccount,

        [Parameter()]
        [switch]$SkipAzure,

        [Parameter()]
        [switch]$SkipEntra,

        [Parameter()]
        [switch]$SkipPim,

        [Parameter()]
        [ValidateSet('Info', 'Low', 'Medium', 'High', 'Critical')]
        [string]$MinimumSeverity = 'Info'
    )

    if ($SkipAzure -and $SkipEntra) { throw 'Nothing to audit: -SkipAzure and -SkipEntra together leave no source.' }

    $graph = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $graph) { throw 'Not connected to Microsoft Graph. Run Connect-RiskyRolesAnalyzer first (or Connect-MgGraph with the read scopes listed in Get-Help Get-RiskyRoleAssignment -Full).' }
    $tenantId = [string](Get-PropertyOrDefault -InputObject $graph -Name 'TenantId' -Default '')
    if (-not (Test-RiskyRoleGraphScope -Scope $script:Catalog.GraphScopes.Read)) {
        Write-Warning "The Graph session lacks one or more read scopes ($($script:Catalog.GraphScopes.Read -join ', ')). Parts of the audit may come back empty. Connect-RiskyRolesAnalyzer requests the full set."
    }

    if (-not $SkipAzure) {
        $azure = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $azure) { throw 'Not connected to Azure. Run Connect-RiskyRolesAnalyzer first, or use -SkipAzure for an Entra-only audit.' }
        $azureTenant = [string](Get-PropertyOrDefault -InputObject (Get-PropertyOrDefault -InputObject $azure -Name 'Tenant' -Default $null) -Name 'Id' -Default '')
        if ($tenantId -and $azureTenant -and $azureTenant -ne $tenantId) {
            throw "Graph is signed in to tenant $tenantId but Azure to $azureTenant. Reconnect with Connect-AzAccount -TenantId $tenantId, or run Connect-RiskyRolesAnalyzer -TenantId $tenantId."
        }
    }

    $audit = @{
        TenantId             = $tenantId
        CurrentAccount       = [string](Get-PropertyOrDefault -InputObject $graph -Name 'Account' -Default '')
        BreakGlassAccount    = @($BreakGlassAccount | Where-Object { $_ })
        PrivilegedAzureRoles = @(@($script:Catalog.PrivilegedAzureRoles) + @($AdditionalAzureRole) | Where-Object { $_ } | Sort-Object -Unique)
        PrivilegedEntraRoles = @(@($script:Catalog.PrivilegedEntraRoles) + @($AdditionalEntraRole) | Where-Object { $_ } | Sort-Object -Unique)
        RiskyAzureActions    = @($script:Catalog.RiskyAzureActions)
        RiskyEntraActions    = @($script:Catalog.RiskyEntraActions)
        Applications         = @{}
        Cache                = @{ Principals = @{}; Groups = @{} }
    }
    Write-Verbose "Tenant $tenantId, $($audit.PrivilegedAzureRoles.Count) Azure and $($audit.PrivilegedEntraRoles.Count) Entra roles tracked"

    Write-Progress -Activity 'RiskyRolesAnalyzer' -Status 'Loading app registrations'
    $audit.Applications = Get-ApplicationInventory

    $findings = [System.Collections.Generic.List[object]]::new()
    if (-not $SkipAzure) { foreach ($finding in @(Get-AzureRoleFinding -Audit $audit -TenantId $tenantId -SubscriptionId $SubscriptionId)) { $findings.Add($finding) } }
    if (-not $SkipEntra) { foreach ($finding in @(Get-EntraRoleFinding -Audit $audit -SkipPim:$SkipPim)) { $findings.Add($finding) } }
    Write-Progress -Activity 'RiskyRolesAnalyzer' -Completed

    $pattern = [string]$script:Catalog.BreakGlassNamePattern
    $suspects = @($findings | Where-Object { -not $_.Protected -and ($_.PrincipalName -match $pattern -or ($_.UPN -and $_.UPN -match $pattern)) } | ForEach-Object PrincipalName | Sort-Object -Unique)
    if ($suspects.Count) {
        Write-Warning "These look like emergency access accounts and are not protected: $($suspects -join ', '). Pass -BreakGlassAccount with their UPNs or object ids so they are reported as protected."
    }

    $rank = @{ Info = 0; Low = 1; Medium = 2; High = 3; Critical = 4 }
    $minimum = $rank[$MinimumSeverity]
    Write-Verbose "$($findings.Count) finding(s) before the severity filter"
    $findings | Where-Object { $rank[$_.Severity] -ge $minimum } | Sort-Object -Property @{ Expression = 'RiskScore'; Descending = $true }, RoleScope, RoleName, PrincipalName
}
