function Test-RiskyRoleGraphScope {
    <#
    .SYNOPSIS
    Does the current Graph session carry every scope in the list?
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Scope
    )

    $context = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $context) { return $false }
    $granted = @(Get-PropertyOrDefault -InputObject $context -Name 'Scopes' -Default @())
    foreach ($required in $Scope) {
        if ($required -notin $granted) { return $false }
    }
    return $true
}
