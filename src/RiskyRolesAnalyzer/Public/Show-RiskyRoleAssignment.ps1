function Show-RiskyRoleAssignment {
    <#
    .SYNOPSIS
    Pick findings in a grid and pass the picked ones down the pipeline.

    .DESCRIPTION
    Opens the findings in Out-ConsoleGridView (any platform, from the
    Microsoft.PowerShell.ConsoleGuiTools module) or Out-GridView (Windows) with the columns that
    matter for a decision, and returns the original finding objects for the rows you selected.
    Protected findings are shown too; Remove-RiskyRoleAssignment refuses them later anyway.

    .PARAMETER InputObject
    Findings from Get-RiskyRoleAssignment.

    .PARAMETER Title
    Window title.

    .EXAMPLE
    Get-RiskyRoleAssignment | Show-RiskyRoleAssignment | Remove-RiskyRoleAssignment -WhatIf

    .EXAMPLE
    $picked = $findings | Show-RiskyRoleAssignment -Title 'Contoso: assignments to remove'

    .OUTPUTS
    RiskyRolesAnalyzer.RiskyRoleAssignment

    .NOTES
    Required permissions: none. It filters objects you already have.

    Needs a grid view and an interactive terminal: Out-ConsoleGridView from
    Microsoft.PowerShell.ConsoleGuiTools on any platform, or Out-GridView on Windows. Without one it
    throws and says what to install. Selecting nothing returns nothing rather than everything.
    #>
    [CmdletBinding()]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignment')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('RiskyRolesAnalyzer.RiskyRoleAssignment')]
        [object[]]$InputObject,

        [Parameter()]
        [string]$Title = 'RiskyRolesAnalyzer: select assignments, then confirm'
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $InputObject) { if ($null -ne $item) { $items.Add($item) } }
    }

    end {
        if ($items.Count -eq 0) { return }
        $grid = Get-RiskyRoleGridCommand
        if (-not $grid) {
            throw 'No grid view is available. Install-Module Microsoft.PowerShell.ConsoleGuiTools (macOS, Linux, Windows), or use Out-GridView on Windows.'
        }

        $view = $items | Select-Object -Property Id, Severity, RiskScore, RoleScope, RoleName, PrincipalName, PrincipalType, ScopeLevel, ScopeDetail, AssignmentType, ActivityStatus, ViaGroup, Protected
        $picked = @($view | & $grid -Title $Title -OutputMode Multiple)
        $ids = @($picked | ForEach-Object Id)
        Write-Verbose "$($ids.Count) of $($items.Count) finding(s) selected"
        $items | Where-Object { $_.Id -in $ids }
    }
}
