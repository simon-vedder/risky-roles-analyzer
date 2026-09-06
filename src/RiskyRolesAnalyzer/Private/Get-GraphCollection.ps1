function Get-GraphCollection {
    <#
    .SYNOPSIS
    GET a Graph collection and follow @odata.nextLink until the end.
    .DESCRIPTION
    The one place the module pages through Graph. Returns the items of every page's "value"
    array. Errors propagate; callers decide whether a failed endpoint is fatal (role
    definitions) or a warning (PIM on a tenant without P2).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next -ErrorAction Stop
        foreach ($item in @(Get-PropertyOrDefault -InputObject $response -Name 'value' -Default @())) {
            if ($null -ne $item) { $items.Add($item) }
        }
        $next = Get-PropertyOrDefault -InputObject $response -Name '@odata.nextLink' -Default $null
    }
    return $items.ToArray()
}
