function Resolve-RoleScope {
    <#
    .SYNOPSIS
    Classify an assignment scope into a hierarchy level with a short display name.
    .DESCRIPTION
    Azure RBAC scopes:
      /                                                        Root
      /providers/Microsoft.Management/managementGroups/{id}    ManagementGroup
      /subscriptions/{id}                                      Subscription
      /subscriptions/{id}/resourceGroups/{name}                ResourceGroup
      /subscriptions/{id}/resourceGroups/{name}/providers/...  Resource
    Entra directory scopes:
      /                                                        Tenant
      /administrativeUnits/{id}                                AdminUnit
      /{objectId}                                              Object (application-scoped role)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateSet('Azure', 'Entra')]
        [string]$RoleScope
    )

    $level, $detail = if ($RoleScope -eq 'Entra') {
        if ([string]::IsNullOrWhiteSpace($Scope) -or $Scope -eq '/') { 'Tenant', 'Tenant-wide' }
        elseif ($Scope -match '^/administrativeUnits/(.+)$') { 'AdminUnit', "Administrative unit: $($Matches[1])" }
        else { 'Object', "Object: $($Scope.TrimStart('/'))" }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Scope) -or $Scope -eq '/') { 'Root', 'Tenant root' }
        elseif ($Scope -match '^/providers/Microsoft\.Management/managementGroups/(.+)$') { 'ManagementGroup', "MG: $($Matches[1])" }
        elseif ($Scope -match '^/subscriptions/[0-9a-fA-F\-]+/resourceGroups/[^/]+/providers/.+$') { 'Resource', "Resource: $(($Scope -split '/')[-1])" }
        elseif ($Scope -match '^/subscriptions/[0-9a-fA-F\-]+/resourceGroups/([^/]+)$') { 'ResourceGroup', "RG: $($Matches[1])" }
        elseif ($Scope -match '^/subscriptions/[0-9a-fA-F\-]+$') { 'Subscription', 'Subscription' }
        else { 'Other', $Scope }
    }

    [pscustomobject]@{ Level = $level; Detail = $detail }
}
