function Get-RiskyRoleFindingId {
    <#
    .SYNOPSIS
    A short, stable identifier for one finding.
    .DESCRIPTION
    The first twelve hex characters of a SHA-256 over the finding's key facts, so the same
    assignment gets the same Id on every run and reports can refer to it. The Id says nothing
    about the tenant on its own.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RoleScope,

        [Parameter(Mandatory)]
        [string]$RoleName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$PrincipalId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ViaGroupId,

        [Parameter(Mandatory)]
        [string]$AssignmentType
    )

    $key = (@($RoleScope, $RoleName, $Scope, $PrincipalId, $ViaGroupId, $AssignmentType) -join '|').ToLowerInvariant()
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($key))
    return [System.Convert]::ToHexString($hash).Substring(0, 12).ToLowerInvariant()
}
