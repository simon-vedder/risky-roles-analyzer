function Resolve-__Noun__Finding {
    <#
    .SYNOPSIS
    Pure decision function: raw facts in, one typed finding out.
    .DESCRIPTION
    Skeleton rule set. Every rule the tool applies lives in functions like this one, with no
    Azure or Graph call inside, so Pester can prove each rule on fixtures. Replace the rules,
    keep the shape: input object, output object with PSTypeName, Severity and Reason.
    #>
    [CmdletBinding()]
    [OutputType('__ModuleName__.__Noun__')]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    $name = [string](Get-PropertyOrDefault -InputObject $InputObject -Name 'Name' -Default '(unnamed)')
    $isPrivileged = [bool](Get-PropertyOrDefault -InputObject $InputObject -Name 'IsPrivileged' -Default $false)
    $isActive = [bool](Get-PropertyOrDefault -InputObject $InputObject -Name 'IsActive' -Default $true)
    $protected = [bool](Get-PropertyOrDefault -InputObject $InputObject -Name 'Protected' -Default $false)

    $severity, $reason = switch ($true) {
        ($isPrivileged -and -not $isActive) { 'High', 'Privileged and unused'; break }
        ($isPrivileged) { 'Medium', 'Privileged and in use'; break }
        default { 'Info', 'Not privileged' }
    }

    [pscustomobject]@{
        PSTypeName = $script:TypeName.Finding
        Name       = $name
        Severity   = $severity
        Reason     = $reason
        Protected  = $protected
        Source     = $InputObject
    }
}
