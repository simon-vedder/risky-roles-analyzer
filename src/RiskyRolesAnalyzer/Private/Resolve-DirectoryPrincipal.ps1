function Resolve-DirectoryPrincipal {
    <#
    .SYNOPSIS
    Look up one directory object and say what it is and whether it can sign in.
    .DESCRIPTION
    Resolves users, groups and service principals through Graph, once per object id; results
    are cached in $Audit.Cache.Principals. Service principals are classified as ManagedIdentity,
    AppRegistration (an application object exists in this tenant) or EnterpriseApp. The
    activity decision itself is the pure rule Resolve-PrincipalActivity.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ObjectId,

        # The audit state built by Get-RiskyRoleAssignment: Cache.Principals, Cache.Groups, Applications.
        [Parameter(Mandatory)]
        [hashtable]$Audit
    )

    if ($Audit.Cache.Principals.ContainsKey($ObjectId)) { return $Audit.Cache.Principals[$ObjectId] }

    $principal = [pscustomobject]@{
        ObjectId       = $ObjectId
        Type           = 'Unknown'
        DisplayName    = '(unresolved)'
        UPN            = $null
        AppId          = $null
        SpType         = $null
        IsEnabled      = $null
        ActivityStatus = 'Unknown'
        ActivityReason = $null
    }

    try {
        $object = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$ObjectId" -ErrorAction Stop
        $odataType = [string](Get-PropertyOrDefault -InputObject $object -Name '@odata.type' -Default '')
        $principal.DisplayName = Get-PropertyOrDefault -InputObject $object -Name 'displayName' -Default '(unnamed)'

        switch -Wildcard ($odataType) {
            '*.user' {
                $principal.Type = 'User'
                $principal.UPN = Get-PropertyOrDefault -InputObject $object -Name 'userPrincipalName' -Default $null
                # /directoryObjects does not reliably return accountEnabled; ask /users.
                try {
                    $detail = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$ObjectId`?`$select=accountEnabled,userPrincipalName" -ErrorAction Stop
                    $principal.IsEnabled = Get-PropertyOrDefault -InputObject $detail -Name 'accountEnabled' -Default $null
                    $upn = Get-PropertyOrDefault -InputObject $detail -Name 'userPrincipalName' -Default $null
                    if ($upn) { $principal.UPN = $upn }
                }
                catch { Write-Verbose "Could not read user $ObjectId : $($_.Exception.Message)" }
                $activity = Resolve-PrincipalActivity -Type 'User' -AccountEnabled $principal.IsEnabled
            }
            '*.group' {
                $principal.Type = 'Group'
                $activity = Resolve-PrincipalActivity -Type 'Group'
            }
            '*.servicePrincipal' {
                $principal.AppId = Get-PropertyOrDefault -InputObject $object -Name 'appId' -Default $null
                $principal.SpType = Get-PropertyOrDefault -InputObject $object -Name 'servicePrincipalType' -Default $null
                $blocked = $null
                try {
                    $detail = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ObjectId`?`$select=disabledByMicrosoftStatus,accountEnabled,appId,servicePrincipalType" -ErrorAction Stop
                    $principal.IsEnabled = Get-PropertyOrDefault -InputObject $detail -Name 'accountEnabled' -Default $null
                    $blocked = Get-PropertyOrDefault -InputObject $detail -Name 'disabledByMicrosoftStatus' -Default $null
                    if (-not $principal.AppId) { $principal.AppId = Get-PropertyOrDefault -InputObject $detail -Name 'appId' -Default $null }
                    if (-not $principal.SpType) { $principal.SpType = Get-PropertyOrDefault -InputObject $detail -Name 'servicePrincipalType' -Default $null }
                }
                catch { Write-Verbose "Could not read service principal $ObjectId : $($_.Exception.Message)" }

                $appInfo = $null
                if ($principal.SpType -eq 'ManagedIdentity') { $principal.Type = 'ManagedIdentity' }
                elseif ($principal.AppId -and $Audit.Applications.ContainsKey($principal.AppId)) {
                    $principal.Type = 'AppRegistration'
                    $appInfo = $Audit.Applications[$principal.AppId]
                }
                else { $principal.Type = 'EnterpriseApp' }

                $activity = Resolve-PrincipalActivity -Type $principal.Type -AccountEnabled $principal.IsEnabled -DisabledByMicrosoftStatus $blocked -ApplicationInfo $appInfo
            }
            default {
                $principal.Type = 'Other'
                $activity = Resolve-PrincipalActivity -Type 'Other'
            }
        }
        $principal.ActivityStatus = $activity.ActivityStatus
        $principal.ActivityReason = $activity.ActivityReason
    }
    catch {
        Write-Verbose "Could not resolve $ObjectId : $($_.Exception.Message)"
    }

    $Audit.Cache.Principals[$ObjectId] = $principal
    return $principal
}
