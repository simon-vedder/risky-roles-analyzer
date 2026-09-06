function Test-RiskyRoleActionMatch {
    <#
    .SYNOPSIS
    Wildcard-aware match of one role definition action pattern against one concrete action.
    .DESCRIPTION
    A pattern like 'Microsoft.Authorization/*' grants 'Microsoft.Authorization/roleAssignments/write'.
    '*' grants everything. Matching is case-insensitive, as ARM and Graph treat actions.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Action
    )

    if ([string]::IsNullOrEmpty($Pattern) -or [string]::IsNullOrEmpty($Action)) { return $false }
    if ($Pattern -eq '*') { return $true }
    if ($Pattern -eq $Action) { return $true }
    if ($Pattern.Contains('*')) {
        $regex = '^' + [regex]::Escape($Pattern).Replace('\*', '.*') + '$'
        return [bool]($Action -match $regex)
    }
    return $false
}
