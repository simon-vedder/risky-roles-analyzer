function Get-EntraRoleFinding {
    <#
    .SYNOPSIS
    Privileged Entra ID directory role assignments, permanent and PIM eligible.
    .DESCRIPTION
    Reads every role definition with its permissions so custom directory roles that grant risky
    actions count as privileged next to the built-in list. Permanent assignments come from
    roleAssignments; eligible ones from roleEligibilitySchedules, which needs Entra ID P2 and is
    skipped with a warning when the tenant or the scopes do not allow it. Group principals are
    expanded like in Azure.
    #>
    [CmdletBinding()]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignment')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Audit,

        [Parameter()]
        [switch]$SkipPim
    )

    $definitions = Get-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions'
    $privileged = @{}   # role definition id -> @{ Name; IsCustom; Risky }
    foreach ($definition in $definitions) {
        $id = [string](Get-PropertyOrDefault -InputObject $definition -Name 'id' -Default '')
        $name = [string](Get-PropertyOrDefault -InputObject $definition -Name 'displayName' -Default '')
        $isBuiltIn = Get-PropertyOrDefault -InputObject $definition -Name 'isBuiltIn' -Default $true
        if ($null -eq $isBuiltIn) { $isBuiltIn = $true }
        if (-not $id) { continue }

        if ($isBuiltIn) {
            if ($name -in $Audit.PrivilegedEntraRoles) { $privileged[$id] = @{ Name = $name; IsCustom = $false; Risky = @() } }
            continue
        }

        $allowed = [System.Collections.Generic.List[string]]::new()
        foreach ($permission in @(Get-PropertyOrDefault -InputObject $definition -Name 'rolePermissions' -Default @())) {
            foreach ($action in @(Get-PropertyOrDefault -InputObject $permission -Name 'allowedResourceActions' -Default @())) { if ($action) { $allowed.Add([string]$action) } }
        }
        $risky = @(Get-RiskyRoleAction -Action $allowed.ToArray() -RiskyAction $Audit.RiskyEntraActions)
        if ($risky.Count -gt 0) { $privileged[$id] = @{ Name = $name; IsCustom = $true; Risky = $risky } }
    }
    Write-Verbose "$($privileged.Count) privileged Entra role definitions (built-in and custom)"

    $sources = @(@{ Uri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments'; Type = 'Permanent' })
    if (-not $SkipPim) { $sources += @{ Uri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules'; Type = 'Eligible' } }

    foreach ($source in $sources) {
        Write-Progress -Activity 'Entra ID roles' -Status $source.Type
        try {
            $assignments = @(Get-GraphCollection -Uri $source.Uri)
        }
        catch {
            if ($source.Type -eq 'Eligible') { Write-Warning "PIM eligible assignments skipped: $($_.Exception.Message). Entra ID P2 and RoleManagement.Read.Directory are required; use -SkipPim to silence this." }
            else { throw }
            continue
        }

        foreach ($assignment in $assignments) {
            $roleId = [string](Get-PropertyOrDefault -InputObject $assignment -Name 'roleDefinitionId' -Default '')
            if (-not $privileged.ContainsKey($roleId)) { continue }
            $principalId = [string](Get-PropertyOrDefault -InputObject $assignment -Name 'principalId' -Default '')
            if (-not $principalId) { continue }
            $role = $privileged[$roleId]
            $directoryScope = [string](Get-PropertyOrDefault -InputObject $assignment -Name 'directoryScopeId' -Default '/')

            $common = @{
                RoleScope        = 'Entra'
                RoleName         = $role.Name
                RoleDefinitionId = $roleId
                Scope            = $directoryScope
                ScopeName        = (Resolve-RoleScope -Scope $directoryScope -RoleScope Entra).Detail
                AssignmentType   = $source.Type
                AssignmentId     = [string](Get-PropertyOrDefault -InputObject $assignment -Name 'id' -Default '')
                IsCustomRole     = $role.IsCustom
                RiskyAction      = $role.Risky
                BreakGlassAccount = $Audit.BreakGlassAccount
                CurrentAccount   = $Audit.CurrentAccount
                Source           = $assignment
            }

            $principal = Resolve-DirectoryPrincipal -ObjectId $principalId -Audit $Audit
            Resolve-RiskyRoleAssignmentFinding @common -Principal $principal
            if ($principal.Type -eq 'Group') {
                foreach ($member in @(Get-GroupMemberRecursive -GroupId $principal.ObjectId -Audit $Audit)) {
                    Resolve-RiskyRoleAssignmentFinding @common -Principal $member -ViaGroup $principal.DisplayName -ViaGroupId $principal.ObjectId
                }
            }
        }
    }
    Write-Progress -Activity 'Entra ID roles' -Completed
}
