function Get-CredentialSummary {
    <#
    .SYNOPSIS
    Count an application's secrets and certificates and say whether any of them is usable now.
    .DESCRIPTION
    Pure rule over the passwordCredentials and keyCredentials arrays of a Graph application
    object. A credential is valid when its start date is not in the future and its end date is
    not in the past. -Now exists so tests can pin the clock.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        $Application,

        [Parameter()]
        [datetime]$Now = (Get-Date)
    )

    $all = @()
    foreach ($name in 'passwordCredentials', 'keyCredentials') {
        $list = Get-PropertyOrDefault -InputObject $Application -Name $name -Default @()
        if ($list) { $all += @($list) }
    }

    $count = 0
    $expired = 0
    $hasValid = $false
    foreach ($credential in $all) {
        if (-not $credential) { continue }
        $count++
        $start = Get-PropertyOrDefault -InputObject $credential -Name 'startDateTime' -Default $null
        $end = Get-PropertyOrDefault -InputObject $credential -Name 'endDateTime' -Default $null
        $valid = $true
        if ($start) { try { if ([datetime]$start -gt $Now) { $valid = $false } } catch { Write-Verbose "Unreadable startDateTime '$start'" } }
        if ($end) { try { if ([datetime]$end -lt $Now) { $valid = $false; $expired++ } } catch { Write-Verbose "Unreadable endDateTime '$end'" } }
        if ($valid) { $hasValid = $true }
    }

    [pscustomobject]@{
        CredentialCount    = $count
        ExpiredCount       = $expired
        HasValidCredential = $hasValid
    }
}
