function Get-RiskyRoleScore {
    <#
    .SYNOPSIS
    Score one finding from 0.0 to 10.0.
    .DESCRIPTION
    Pure rule driven by the Scoring section of RiskyRoleCatalog.psd1: a base score per role
    (critical, high, medium, custom-with-risky-actions or default), multiplied by scope breadth,
    then modified for PIM eligibility, application principals and principals that cannot sign in.
    The score expresses live exploitability; a disabled Global Administrator scores lower than an
    enabled one even though both should go.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [string]$RoleName,

        [Parameter(Mandatory)]
        [string]$ScopeLevel,

        [Parameter(Mandatory)]
        [string]$PrincipalType,

        [Parameter(Mandatory)]
        [ValidateSet('Permanent', 'Eligible', 'Activated')]
        [string]$AssignmentType,

        [Parameter()]
        [bool]$IsCustomRole = $false,

        [Parameter()]
        [AllowNull()]
        [string[]]$RiskyAction,

        [Parameter()]
        [string]$ActivityStatus = 'Active'
    )

    $rules = $script:Catalog.Scoring
    $risky = @($RiskyAction | Where-Object { $_ })

    $base = $rules.DefaultBase
    if ($RoleName -in $rules.CriticalRoles) { $base = $rules.CriticalRoleBase }
    elseif ($RoleName -in $rules.HighRoles) { $base = $rules.HighRoleBase }
    elseif ($RoleName -in $rules.MediumRoles) { $base = $rules.MediumRoleBase }

    if ($IsCustomRole) {
        $base = $rules.CustomRoleBase
        foreach ($action in $risky) {
            if ($action -in $rules.CriticalActions) { $base = [Math]::Max($base, $rules.CriticalRoleBase) }
        }
        if ($risky.Count -ge 3) { $base += $rules.StackedActionBonus }
    }

    $multiplier = if ($rules.ScopeMultiplier.ContainsKey($ScopeLevel)) { $rules.ScopeMultiplier[$ScopeLevel] } else { $rules.ScopeMultiplier['Other'] }
    $score = $base * $multiplier

    if ($AssignmentType -eq 'Eligible') { $score += $rules.EligibleModifier }
    if ($PrincipalType -in 'EnterpriseApp', 'AppRegistration', 'ManagedIdentity') { $score += $rules.ApplicationModifier }
    if ($rules.ActivityModifier.ContainsKey($ActivityStatus)) { $score += $rules.ActivityModifier[$ActivityStatus] }

    # Away from zero, so 7.65 reads 7.7 the way a person would round it.
    return [Math]::Round([Math]::Min(10.0, [Math]::Max(0.0, $score)), 1, [System.MidpointRounding]::AwayFromZero)
}
