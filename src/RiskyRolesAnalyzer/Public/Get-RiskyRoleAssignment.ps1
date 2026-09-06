function Get-RiskyRoleAssignment {
    <#
    .SYNOPSIS
    Read-only discovery of RiskyRoleAssignment findings.

    .DESCRIPTION
    Skeleton example of the read path. Replace the source (here the -InputObject parameter) with
    the Az or Graph calls the tool needs and keep the shape: collect raw facts, hand each one to a
    pure decision function in Private/, emit typed objects. Nothing in this function changes state.

    .PARAMETER InputObject
    Raw records to evaluate. In a real tool this is what Get-AzRoleAssignment, Get-MgApplication
    and friends return.

    .PARAMETER MinimumSeverity
    Return only findings at or above this severity.

    .EXAMPLE
    Get-RiskyRoleAssignment | Format-Table Name, Severity, Reason

    .EXAMPLE
    Get-RiskyRoleAssignment -MinimumSeverity High | Remove-RiskyRoleAssignment -WhatIf

    .OUTPUTS
    RiskyRolesAnalyzer.RiskyRoleAssignment

    .NOTES
    Required permissions: read-only. List the exact Graph scopes or RBAC actions here, and in the
    README's Permissions section.
    #>
    [CmdletBinding()]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignment')]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,

        [Parameter()]
        [ValidateSet('Info', 'Low', 'Medium', 'High')]
        [string]$MinimumSeverity = 'Info'
    )

    begin {
        $rank = @{ Info = 0; Low = 1; Medium = 2; High = 3 }
    }

    process {
        foreach ($raw in @($InputObject)) {
            if ($null -eq $raw) { continue }
            $finding = Resolve-RiskyRoleAssignmentFinding -InputObject $raw
            if ($rank[$finding.Severity] -lt $rank[$MinimumSeverity]) { continue }
            $finding
        }
    }
}
