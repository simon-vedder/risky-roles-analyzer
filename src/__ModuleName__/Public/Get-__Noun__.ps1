function Get-__Noun__ {
    <#
    .SYNOPSIS
    Read-only discovery of __Noun__ findings.

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
    Get-__Noun__ | Format-Table Name, Severity, Reason

    .EXAMPLE
    Get-__Noun__ -MinimumSeverity High | Remove-__Noun__ -WhatIf

    .OUTPUTS
    __ModuleName__.__Noun__

    .NOTES
    Required permissions: read-only. List the exact Graph scopes or RBAC actions here, and in the
    README's Permissions section.
    #>
    [CmdletBinding()]
    [OutputType('__ModuleName__.__Noun__')]
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
            $finding = Resolve-__Noun__Finding -InputObject $raw
            if ($rank[$finding.Severity] -lt $rank[$MinimumSeverity]) { continue }
            $finding
        }
    }
}
