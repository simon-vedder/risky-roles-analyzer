function Get-ApplicationInventory {
    <#
    .SYNOPSIS
    Load every app registration once, with its credential state and the portal's "deactivated" flag.
    .DESCRIPTION
    Two passes: v1.0 for credentials (start and end dates decide whether any is usable now) and
    /beta for isDisabled, the App Registration "Deactivated" toggle, which v1.0 does not expose.
    The beta pass is best effort; without it deactivated app registrations look active.
    Returns a hashtable keyed by appId.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [datetime]$Now = (Get-Date)
    )

    $inventory = @{}

    $apps = Get-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/applications?$select=id,appId,displayName,passwordCredentials,keyCredentials&$top=999'
    foreach ($app in $apps) {
        $appId = [string](Get-PropertyOrDefault -InputObject $app -Name 'appId' -Default '')
        if (-not $appId) { continue }
        $summary = Get-CredentialSummary -Application $app -Now $Now
        $inventory[$appId] = [pscustomobject]@{
            Id                 = Get-PropertyOrDefault -InputObject $app -Name 'id' -Default $null
            AppId              = $appId
            DisplayName        = Get-PropertyOrDefault -InputObject $app -Name 'displayName' -Default $null
            CredentialCount    = $summary.CredentialCount
            ExpiredCount       = $summary.ExpiredCount
            HasValidCredential = $summary.HasValidCredential
            IsDisabled         = $false
        }
    }

    try {
        $flags = Get-GraphCollection -Uri 'https://graph.microsoft.com/beta/applications?$select=appId,isDisabled&$top=999'
        foreach ($flag in $flags) {
            $appId = [string](Get-PropertyOrDefault -InputObject $flag -Name 'appId' -Default '')
            if ($appId -and $inventory.ContainsKey($appId) -and (Get-PropertyOrDefault -InputObject $flag -Name 'isDisabled' -Default $false) -eq $true) {
                $inventory[$appId].IsDisabled = $true
            }
        }
    }
    catch {
        Write-Warning "Could not read isDisabled from the Graph beta endpoint; deactivated app registrations will show as active. $($_.Exception.Message)"
    }

    Write-Verbose "$($inventory.Count) app registrations loaded"
    return $inventory
}
