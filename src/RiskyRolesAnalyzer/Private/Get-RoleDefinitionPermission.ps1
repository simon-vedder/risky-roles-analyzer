function Get-RoleDefinitionPermission {
    <#
    .SYNOPSIS
    The permission blocks of an Azure role definition, whichever Az.Resources shape it has.
    .DESCRIPTION
    Az.Resources 10 moved Actions, NotActions, DataActions and NotDataActions off the role
    definition into a Permissions array (one block per permission set, each with an optional
    ABAC condition). Older versions flatten the single block onto the definition itself.
    This returns the blocks as uniform objects with the four string arrays so the collector
    rates a custom role the same way on either version. A pure rule; nothing here calls Azure.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Definition
    )

    $toArray = { param($Value) @($Value | Where-Object { $null -ne $_ -and "$_" -ne '' } | ForEach-Object { [string]$_ }) }

    $blocks = @(Get-PropertyOrDefault -InputObject $Definition -Name 'Permissions' -Default $null | Where-Object { $null -ne $_ })
    if ($blocks.Count -eq 0) { $blocks = @($Definition) }   # Az.Resources < 10: the definition is the block

    foreach ($block in $blocks) {
        [pscustomobject]@{
            Actions        = & $toArray (Get-PropertyOrDefault -InputObject $block -Name 'Actions' -Default @())
            NotActions     = & $toArray (Get-PropertyOrDefault -InputObject $block -Name 'NotActions' -Default @())
            DataActions    = & $toArray (Get-PropertyOrDefault -InputObject $block -Name 'DataActions' -Default @())
            NotDataActions = & $toArray (Get-PropertyOrDefault -InputObject $block -Name 'NotDataActions' -Default @())
        }
    }
}
