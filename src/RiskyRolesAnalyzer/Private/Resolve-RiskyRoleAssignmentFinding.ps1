function Resolve-RiskyRoleAssignmentFinding {
    <#
    .SYNOPSIS
    Turn one privileged assignment plus its resolved principal into a typed finding.
    .DESCRIPTION
    Pure assembly: scope classification, score, severity, cleanup commands, a stable Id and the
    Protected flag. Nothing here calls Azure or Graph, so every rule is provable on a fixture.

    Protected means Remove-RiskyRoleAssignment will report the finding and not touch it:
      - inherited through a group (the fix is a membership or the group's assignment, both yours to decide)
      - PIM eligible (managed in PIM, not by deleting an assignment)
      - a break-glass account named with -BreakGlassAccount
      - the identity running the audit
    #>
    [CmdletBinding()]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignment')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Azure', 'Entra')]
        [string]$RoleScope,

        [Parameter(Mandatory)]
        [string]$RoleName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$RoleDefinitionId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Scope,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ScopeName,

        [Parameter(Mandatory)]
        [ValidateSet('Permanent', 'Eligible')]
        [string]$AssignmentType,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$AssignmentId,

        # Output of Resolve-DirectoryPrincipal (ObjectId, Type, DisplayName, UPN, AppId,
        # IsEnabled, ActivityStatus, ActivityReason).
        [Parameter(Mandatory)]
        $Principal,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ViaGroup,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ViaGroupId,

        [Parameter()]
        [bool]$IsCustomRole = $false,

        [Parameter()]
        [AllowNull()]
        [string[]]$RiskyAction,

        # UPNs or object ids that must never be removed.
        [Parameter()]
        [AllowNull()]
        [string[]]$BreakGlassAccount,

        # UPN of the identity running the audit.
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CurrentAccount,

        [Parameter()]
        [AllowNull()]
        $Source
    )

    $principalId = [string](Get-PropertyOrDefault -InputObject $Principal -Name 'ObjectId' -Default '')
    $principalType = [string](Get-PropertyOrDefault -InputObject $Principal -Name 'Type' -Default 'Unknown')
    $upn = Get-PropertyOrDefault -InputObject $Principal -Name 'UPN' -Default $null
    $activity = [string](Get-PropertyOrDefault -InputObject $Principal -Name 'ActivityStatus' -Default 'Unknown')
    $risky = @($RiskyAction | Where-Object { $_ })

    $scopeInfo = Resolve-RoleScope -Scope $Scope -RoleScope $RoleScope
    $score = Get-RiskyRoleScore -RoleName $RoleName -ScopeLevel $scopeInfo.Level -PrincipalType $principalType `
        -AssignmentType $AssignmentType -IsCustomRole $IsCustomRole -RiskyAction $risky -ActivityStatus $activity
    $cleanup = Get-RiskyRoleCleanupCommand -RoleScope $RoleScope -RoleName $RoleName -Scope $Scope -PrincipalId $principalId `
        -AssignmentType $AssignmentType -AssignmentId $AssignmentId -ViaGroupId $ViaGroupId

    $protectedReason = $null
    $breakGlass = @($BreakGlassAccount | Where-Object { $_ })
    if ($ViaGroupId) { $protectedReason = "Inherited through group '$ViaGroup'" }
    elseif ($AssignmentType -eq 'Eligible') { $protectedReason = 'PIM eligibility, manage it in PIM' }
    elseif ($breakGlass -and (($principalId -and $principalId -in $breakGlass) -or ($upn -and $upn -in $breakGlass))) { $protectedReason = 'Break-glass account' }
    elseif ($CurrentAccount -and $upn -and $upn -eq $CurrentAccount) { $protectedReason = 'Identity running this audit' }

    [pscustomobject]@{
        PSTypeName       = $script:TypeName.Finding
        Id               = Get-RiskyRoleFindingId -RoleScope $RoleScope -RoleName $RoleName -Scope $Scope -PrincipalId $principalId -ViaGroupId $ViaGroupId -AssignmentType $AssignmentType
        Severity         = ConvertTo-RiskyRoleSeverity -Score $score
        RiskScore        = $score
        RoleScope        = $RoleScope
        RoleName         = $RoleName
        RoleDefinitionId = $RoleDefinitionId
        IsCustomRole     = $IsCustomRole
        RiskyActions     = [string[]]$risky
        Scope            = $Scope
        ScopeName        = $ScopeName
        ScopeLevel       = $scopeInfo.Level
        ScopeDetail      = $scopeInfo.Detail
        AssignmentType   = $AssignmentType
        AssignmentId     = $AssignmentId
        PrincipalType    = $principalType
        PrincipalName    = [string](Get-PropertyOrDefault -InputObject $Principal -Name 'DisplayName' -Default '(unresolved)')
        PrincipalId      = $principalId
        UPN              = $upn
        AppId            = Get-PropertyOrDefault -InputObject $Principal -Name 'AppId' -Default $null
        AccountEnabled   = Get-PropertyOrDefault -InputObject $Principal -Name 'IsEnabled' -Default $null
        ActivityStatus   = $activity
        ActivityReason   = Get-PropertyOrDefault -InputObject $Principal -Name 'ActivityReason' -Default $null
        ViaGroup         = $ViaGroup
        ViaGroupId       = $ViaGroupId
        Protected        = [bool]$protectedReason
        ProtectedReason  = $protectedReason
        CleanupPrimary   = $cleanup.Primary
        CleanupAlt       = $cleanup.Alt
        Source           = $Source
    }
}
