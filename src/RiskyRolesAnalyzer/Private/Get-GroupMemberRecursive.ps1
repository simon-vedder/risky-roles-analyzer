function Get-GroupMemberRecursive {
    <#
    .SYNOPSIS
    Every non-group member of a group, through any depth of nesting.
    .DESCRIPTION
    Walks group members recursively, resolves each leaf with Resolve-DirectoryPrincipal and
    caches the flat list per group in $Audit.Cache.Groups. A group that contains itself through
    a cycle is visited once.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [hashtable]$Audit,

        [Parameter()]
        [System.Collections.Generic.HashSet[string]]$Seen
    )

    if (-not $Seen) { $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
    if ($Audit.Cache.Groups.ContainsKey($GroupId)) { return $Audit.Cache.Groups[$GroupId] }
    if (-not $Seen.Add($GroupId)) { return @() }

    $leaves = [System.Collections.Generic.List[object]]::new()
    try {
        $members = Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/members?`$select=id&`$top=999"
        foreach ($member in $members) {
            $memberId = [string](Get-PropertyOrDefault -InputObject $member -Name 'id' -Default '')
            if (-not $memberId) { continue }
            $type = [string](Get-PropertyOrDefault -InputObject $member -Name '@odata.type' -Default '')
            if ($type -like '*.group') {
                foreach ($nested in @(Get-GroupMemberRecursive -GroupId $memberId -Audit $Audit -Seen $Seen)) { $leaves.Add($nested) }
            }
            else {
                $resolved = Resolve-DirectoryPrincipal -ObjectId $memberId -Audit $Audit
                if ($resolved) { $leaves.Add($resolved) }
            }
        }
    }
    catch {
        Write-Warning "Could not list members of group $GroupId : $($_.Exception.Message)"
    }

    $Audit.Cache.Groups[$GroupId] = $leaves.ToArray()
    return $Audit.Cache.Groups[$GroupId]
}
