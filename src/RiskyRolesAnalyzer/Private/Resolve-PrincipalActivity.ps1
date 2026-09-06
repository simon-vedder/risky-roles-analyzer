function Resolve-PrincipalActivity {
    <#
    .SYNOPSIS
    Decide whether a principal can sign in at all, and why not.
    .DESCRIPTION
    Pure rule. Returns ActivityStatus (Active, Disabled, NoValidCredential, BlockedByMicrosoft,
    Unknown) and a reason. Precedence for service principals: sign-in disabled, then blocked by
    Microsoft, then (app registrations only) deactivated or without a usable credential.
    Groups never sign in and count as Active; managed identities have no credentials to check.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Group', 'ManagedIdentity', 'AppRegistration', 'EnterpriseApp', 'Other', 'Unknown')]
        [string]$Type,

        [Parameter()]
        [AllowNull()]
        [nullable[bool]]$AccountEnabled,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DisabledByMicrosoftStatus,

        # For app registrations: the entry from Get-ApplicationInventory (IsDisabled,
        # CredentialCount, HasValidCredential). Null when the inventory has no entry.
        [Parameter()]
        [AllowNull()]
        $ApplicationInfo
    )

    $status = 'Unknown'
    $reason = $null

    switch ($Type) {
        'User' {
            if ($AccountEnabled -eq $false) { $status = 'Disabled'; $reason = 'Account disabled' }
            elseif ($AccountEnabled -eq $true) { $status = 'Active' }
        }
        'Group' { $status = 'Active' }
        'Unknown' { }
        'Other' { $status = 'Active' }
        default {
            if ($AccountEnabled -eq $false) {
                $status = 'Disabled'; $reason = 'Service principal sign-in disabled'
            }
            elseif ($DisabledByMicrosoftStatus) {
                $status = 'BlockedByMicrosoft'; $reason = "Blocked by Microsoft: $DisabledByMicrosoftStatus"
            }
            elseif ($Type -eq 'AppRegistration') {
                if ($null -eq $ApplicationInfo) {
                    $status = 'Unknown'; $reason = 'Could not load credential info'
                }
                elseif ([bool](Get-PropertyOrDefault -InputObject $ApplicationInfo -Name 'IsDisabled' -Default $false)) {
                    $status = 'Disabled'; $reason = 'App registration deactivated'
                }
                else {
                    $count = [int](Get-PropertyOrDefault -InputObject $ApplicationInfo -Name 'CredentialCount' -Default 0)
                    $hasValid = [bool](Get-PropertyOrDefault -InputObject $ApplicationInfo -Name 'HasValidCredential' -Default $false)
                    if ($count -eq 0) { $status = 'NoValidCredential'; $reason = 'No password or certificate credentials' }
                    elseif (-not $hasValid) { $status = 'NoValidCredential'; $reason = "All $count credentials expired" }
                    else { $status = 'Active' }
                }
            }
            else {
                $status = 'Active'
            }
        }
    }

    [pscustomobject]@{ ActivityStatus = $status; ActivityReason = $reason }
}
