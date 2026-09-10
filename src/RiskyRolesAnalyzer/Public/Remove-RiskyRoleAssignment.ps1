function Remove-RiskyRoleAssignment {
    <#
    .SYNOPSIS
    Remove privileged role assignments that Get-RiskyRoleAssignment found, one prompt at a time.

    .DESCRIPTION
    The write path, built so that nothing happens by accident:

      - accepts only the objects Get-RiskyRoleAssignment produced, never free-form names
      - asks before every assignment (ConfirmImpact High); -WhatIf shows the plan
      - writes every assignment to a JSON backup file before the call that removes it
      - refuses Protected findings and reports them instead: inherited through a group,
        PIM eligible, break-glass accounts, the identity running the audit

    Azure RBAC assignments are removed with Remove-AzRoleAssignment by principal, role
    definition id and scope. Entra permanent assignments are removed by their assignment id
    through Graph, which needs RoleManagement.ReadWrite.Directory
    (Connect-RiskyRolesAnalyzer -RequestWriteScopes). Nothing is removed for a group's
    members: remove the group's own assignment, or the membership, deliberately.

    .PARAMETER InputObject
    Findings from Get-RiskyRoleAssignment.

    .PARAMETER BackupPath
    JSON file that receives every assignment before it is removed.
    Default: ./RiskyRolesAnalyzer-backup-<timestamp>.json in the current directory.

    .EXAMPLE
    Get-RiskyRoleAssignment -MinimumSeverity High | Remove-RiskyRoleAssignment -WhatIf

    .EXAMPLE
    Get-RiskyRoleAssignment | Where-Object ActivityStatus -eq 'Disabled' | Show-RiskyRoleAssignment | Remove-RiskyRoleAssignment

    .OUTPUTS
    RiskyRolesAnalyzer.RiskyRoleAssignmentRemoval

    .NOTES
    RequiredPermissions: On Azure, Microsoft.Authorization/roleAssignments/delete on the scope
    (Owner or User Access Administrator). On Entra, RoleManagement.ReadWrite.Directory plus a role
    that may remove the assignment (Privileged Role Administrator).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignmentRemoval')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('RiskyRolesAnalyzer.RiskyRoleAssignment')]
        [object[]]$InputObject,

        [Parameter()]
        [string]$BackupPath = (Join-Path (Get-Location) ('RiskyRolesAnalyzer-backup-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date)))
    )

    begin {
        $backup = [System.Collections.Generic.List[object]]::new()

        $removal = {
            param($Item, [string]$Result, [string]$Reason)
            [pscustomobject]@{
                PSTypeName    = $script:TypeName.Removal
                Id            = $Item.Id
                Result        = $Result
                Reason        = $Reason
                RoleScope     = $Item.RoleScope
                RoleName      = $Item.RoleName
                PrincipalName = $Item.PrincipalName
                PrincipalId   = $Item.PrincipalId
                Scope         = $Item.Scope
            }
        }
    }

    process {
        foreach ($item in $InputObject) {
            $target = "$($item.PrincipalName) as $($item.RoleName) on $($item.ScopeDetail)"

            if ($item.Protected) {
                Write-Warning "${target}: protected ($($item.ProtectedReason)), not removed."
                & $removal -Item $item -Result 'Skipped' -Reason $item.ProtectedReason
                continue
            }
            if ($item.RoleScope -eq 'Entra' -and -not $item.AssignmentId) {
                Write-Warning "${target}: no assignment id, cannot remove through Graph."
                & $removal -Item $item -Result 'Skipped' -Reason 'No assignment id'
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($target, "Remove $($item.RoleScope) role assignment")) {
                & $removal -Item $item -Result 'Skipped' -Reason 'Declined or -WhatIf'
                continue
            }

            if ($item.RoleScope -eq 'Entra' -and -not (Test-RiskyRoleGraphScope -Scope $script:Catalog.GraphScopes.Write)) {
                throw "The Graph session lacks $($script:Catalog.GraphScopes.Write -join ', '). Run Connect-RiskyRolesAnalyzer -RequestWriteScopes and try again. Nothing was removed for $target."
            }

            # Backup first, always. The whole list is rewritten as a JSON array so the file is
            # complete even if the next call throws.
            $backup.Add(($item | Select-Object -Property * -ExcludeProperty Source))
            ConvertTo-Json -InputObject @($backup) -Depth 10 | Set-Content -Path $BackupPath -Encoding utf8

            try {
                if ($item.RoleScope -eq 'Azure') {
                    $null = Remove-AzRoleAssignment -ObjectId $item.PrincipalId -RoleDefinitionId $item.RoleDefinitionId -Scope $item.Scope -ErrorAction Stop
                }
                else {
                    $null = Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$($item.AssignmentId)" -ErrorAction Stop
                }
                & $removal -Item $item -Result 'Removed' -Reason "Backup: $BackupPath"
            }
            catch {
                Write-Error -Message "${target}: removal failed. $($_.Exception.Message)" -ErrorAction Continue
                & $removal -Item $item -Result 'Failed' -Reason $_.Exception.Message
            }
        }
    }

    end {
        if ($backup.Count) { Write-Verbose "Backup of $($backup.Count) assignment(s): $BackupPath" }
    }
}
