function Get-RiskyRoleAction {
    <#
    .SYNOPSIS
    The risky actions a role definition really grants, after NotActions are applied.
    .DESCRIPTION
    Pure rule: takes the four permission lists of an Azure RBAC role (Entra roles only have
    allowed actions) and the list of actions considered risky, returns the risky actions that are
    granted by Actions or DataActions and not taken away by NotActions or NotDataActions.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [string[]]$Action,

        [Parameter()]
        [AllowNull()]
        [string[]]$NotAction,

        [Parameter()]
        [AllowNull()]
        [string[]]$DataAction,

        [Parameter()]
        [AllowNull()]
        [string[]]$NotDataAction,

        [Parameter(Mandatory)]
        [string[]]$RiskyAction
    )

    $granting = @(@($Action) + @($DataAction) | Where-Object { $_ })
    $blocking = @(@($NotAction) + @($NotDataAction) | Where-Object { $_ })

    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($risky in $RiskyAction) {
        $granted = $false
        foreach ($pattern in $granting) {
            if (Test-RiskyRoleActionMatch -Pattern $pattern -Action $risky) { $granted = $true; break }
        }
        if (-not $granted) { continue }

        $blocked = $false
        foreach ($pattern in $blocking) {
            if (Test-RiskyRoleActionMatch -Pattern $pattern -Action $risky) { $blocked = $true; break }
        }
        if (-not $blocked) { $hits.Add($risky) }
    }

    return [string[]]$hits
}
