function ConvertTo-RiskyRoleSeverity {
    <#
    .SYNOPSIS
    Map a 0.0 to 10.0 score to the severity label used everywhere else.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Score
    )

    foreach ($band in $script:Catalog.Scoring.Severity) {
        if ($Score -ge $band.Minimum) { return [string]$band.Name }
    }
    return 'Info'
}
