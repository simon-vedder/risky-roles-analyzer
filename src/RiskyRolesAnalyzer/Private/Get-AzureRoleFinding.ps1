function Get-AzureRoleFinding {
    <#
    .SYNOPSIS
    Privileged Azure RBAC assignments across the enabled subscriptions of one tenant.
    .DESCRIPTION
    Per subscription: custom role definitions are checked for risky actions, then every
    assignment visible at subscription scope (including the ones inherited from management
    groups and the root) is kept when its role is a privileged built-in or a risky custom role.
    Assignments inherited from above appear in every subscription; each is reported once.
    Group principals are expanded so every member is listed with the group it inherits through.
    The Az context is switched per subscription and restored afterwards.
    #>
    [CmdletBinding()]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignment')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Audit,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter()]
        [AllowNull()]
        [string[]]$SubscriptionId
    )

    $subscriptions = @(Get-AzSubscription -TenantId $TenantId -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' })
    if ($SubscriptionId) {
        $wanted = @($SubscriptionId | ForEach-Object { $_.ToLowerInvariant() })
        $subscriptions = @($subscriptions | Where-Object { $_.Id.ToLowerInvariant() -in $wanted })
        foreach ($id in $wanted) {
            if ($id -notin @($subscriptions | ForEach-Object { $_.Id.ToLowerInvariant() })) { Write-Warning "Subscription $id is not enabled in tenant $TenantId or not visible to this account." }
        }
    }
    Write-Verbose "$($subscriptions.Count) enabled subscription(s) in tenant $TenantId"
    if ($subscriptions.Count -eq 0) {
        Write-Warning "No enabled subscriptions found in tenant $TenantId. Check Get-AzSubscription and Connect-AzAccount -TenantId $TenantId."
        return
    }

    $roleCache = @{}   # role definition id -> @{ Name; Risky }
    $seenAssignments = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $originalContext = Get-AzContext -ErrorAction SilentlyContinue

    try {
        $index = 0
        foreach ($subscription in $subscriptions) {
            $index++
            Write-Progress -Activity 'Azure RBAC' -Status "$($subscription.Name) ($index/$($subscriptions.Count))" -PercentComplete (100 * ($index - 1) / $subscriptions.Count)
            Write-Verbose "[$index/$($subscriptions.Count)] $($subscription.Name)"
            $null = Set-AzContext -SubscriptionId $subscription.Id -TenantId $TenantId -ErrorAction Stop

            try {
                foreach ($definition in @(Get-AzRoleDefinition -Custom -ErrorAction Stop)) {
                    if ($roleCache.ContainsKey($definition.Id)) { continue }
                    # Az.Resources 10 nests the actions in Permissions[]; older versions flatten them. Rate the union.
                    $risky = [System.Collections.Generic.List[string]]::new()
                    foreach ($permission in @(Get-RoleDefinitionPermission -Definition $definition)) {
                        foreach ($action in @(Get-RiskyRoleAction -Action $permission.Actions -NotAction $permission.NotActions -DataAction $permission.DataActions -NotDataAction $permission.NotDataActions -RiskyAction $Audit.RiskyAzureActions)) {
                            if ($action -notin $risky) { $risky.Add($action) }
                        }
                    }
                    $roleCache[$definition.Id] = @{ Name = $definition.Name; Risky = $risky.ToArray() }
                }
            }
            catch { Write-Warning "Could not list role definitions in $($subscription.Name): $($_.Exception.Message)" }

            try {
                $assignments = @(Get-AzRoleAssignment -Scope "/subscriptions/$($subscription.Id)" -ErrorAction Stop)
            }
            catch {
                Write-Warning "Could not list role assignments in $($subscription.Name): $($_.Exception.Message)"
                continue
            }

            foreach ($assignment in $assignments) {
                $isCustom = $roleCache.ContainsKey($assignment.RoleDefinitionId)
                $risky = @()
                if ($isCustom) { $risky = @($roleCache[$assignment.RoleDefinitionId].Risky) }
                $privileged = ($assignment.RoleDefinitionName -in $Audit.PrivilegedAzureRoles) -or ($isCustom -and $risky.Count -gt 0)
                if (-not $privileged) { continue }
                if ($assignment.RoleAssignmentId -and -not $seenAssignments.Add($assignment.RoleAssignmentId)) { continue }

                $scopeName = if ($assignment.Scope -like "/subscriptions/$($subscription.Id)*") { $subscription.Name } else { (Resolve-RoleScope -Scope $assignment.Scope -RoleScope Azure).Detail }
                $common = @{
                    RoleScope        = 'Azure'
                    RoleName         = $assignment.RoleDefinitionName
                    RoleDefinitionId = $assignment.RoleDefinitionId
                    Scope            = $assignment.Scope
                    ScopeName        = $scopeName
                    AssignmentType   = 'Permanent'
                    AssignmentId     = $assignment.RoleAssignmentId
                    IsCustomRole     = $isCustom
                    RiskyAction      = $risky
                    BreakGlassAccount = $Audit.BreakGlassAccount
                    CurrentAccount   = $Audit.CurrentAccount
                    Source           = $assignment
                }

                $principal = Resolve-DirectoryPrincipal -ObjectId $assignment.ObjectId -Audit $Audit
                Resolve-RiskyRoleAssignmentFinding @common -Principal $principal
                if ($principal.Type -eq 'Group') {
                    foreach ($member in @(Get-GroupMemberRecursive -GroupId $principal.ObjectId -Audit $Audit)) {
                        Resolve-RiskyRoleAssignmentFinding @common -Principal $member -ViaGroup $principal.DisplayName -ViaGroupId $principal.ObjectId
                    }
                }
            }
        }
    }
    finally {
        Write-Progress -Activity 'Azure RBAC' -Completed
        $originalSubscription = Get-PropertyOrDefault -InputObject (Get-PropertyOrDefault -InputObject $originalContext -Name 'Subscription' -Default $null) -Name 'Id' -Default $null
        if ($originalSubscription) { $null = Set-AzContext -SubscriptionId $originalSubscription -TenantId $TenantId -ErrorAction SilentlyContinue }
    }
}
