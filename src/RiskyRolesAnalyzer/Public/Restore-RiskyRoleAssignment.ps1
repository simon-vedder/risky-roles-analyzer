function Restore-RiskyRoleAssignment {
    <#
    .SYNOPSIS
    Put back assignments from a backup file that Remove-RiskyRoleAssignment wrote.

    .DESCRIPTION
    Reads the JSON backup (or takes the same objects from the pipeline) and recreates each
    permanent assignment: Azure with New-AzRoleAssignment by principal, role definition id and
    scope; Entra by posting a new role assignment for the principal, role and directory scope.
    Restoring privilege is as serious as removing it, so every assignment is confirmed
    (ConfirmImpact High) and -WhatIf shows the plan.

    Entries the module cannot restore are reported and skipped: PIM eligibility and activations
    (manage them in PIM), assignments inherited through a group (the group's assignment was
    never removed), entries without the ids needed.

    .PARAMETER Path
    A backup file written by Remove-RiskyRoleAssignment.

    .PARAMETER InputObject
    Backup entries, for example from Get-Content backup.json | ConvertFrom-Json.

    .EXAMPLE
    Restore-RiskyRoleAssignment -Path ./RiskyRolesAnalyzer-backup-20260906-142200.json -WhatIf

    .EXAMPLE
    Get-Content ./backup.json | ConvertFrom-Json | Where-Object PrincipalName -eq 'Deploy App' | Restore-RiskyRoleAssignment

    .OUTPUTS
    RiskyRolesAnalyzer.RiskyRoleAssignmentRestore

    .NOTES
    RequiredPermissions: On Azure, Microsoft.Authorization/roleAssignments/write on the scope.
    On Entra, RoleManagement.ReadWrite.Directory (Connect-RiskyRolesAnalyzer -RequestWriteScopes).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Path')]
    [OutputType('RiskyRolesAnalyzer.RiskyRoleAssignmentRestore')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Object', ValueFromPipeline)]
        [object[]]$InputObject
    )

    begin {
        $entries = [System.Collections.Generic.List[object]]::new()
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($entry in @(Get-Content -Path $Path -Raw -Encoding utf8 | ConvertFrom-Json)) { if ($null -ne $entry) { $entries.Add($entry) } }
        }

        $result = {
            param($Item, [string]$Result, [string]$Reason)
            [pscustomobject]@{
                PSTypeName    = $script:TypeName.Restore
                Id            = Get-PropertyOrDefault -InputObject $Item -Name 'Id' -Default $null
                Result        = $Result
                Reason        = $Reason
                RoleScope     = Get-PropertyOrDefault -InputObject $Item -Name 'RoleScope' -Default $null
                RoleName      = Get-PropertyOrDefault -InputObject $Item -Name 'RoleName' -Default $null
                PrincipalName = Get-PropertyOrDefault -InputObject $Item -Name 'PrincipalName' -Default $null
                PrincipalId   = Get-PropertyOrDefault -InputObject $Item -Name 'PrincipalId' -Default $null
                Scope         = Get-PropertyOrDefault -InputObject $Item -Name 'Scope' -Default $null
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Object') {
            foreach ($entry in @($InputObject)) { if ($null -ne $entry) { $entries.Add($entry) } }
        }
    }

    end {
        foreach ($item in $entries) {
            $roleScope = [string](Get-PropertyOrDefault -InputObject $item -Name 'RoleScope' -Default '')
            $roleName = [string](Get-PropertyOrDefault -InputObject $item -Name 'RoleName' -Default '(unknown role)')
            $roleDefinitionId = [string](Get-PropertyOrDefault -InputObject $item -Name 'RoleDefinitionId' -Default '')
            $scope = [string](Get-PropertyOrDefault -InputObject $item -Name 'Scope' -Default '')
            $principalId = [string](Get-PropertyOrDefault -InputObject $item -Name 'PrincipalId' -Default '')
            $principalName = [string](Get-PropertyOrDefault -InputObject $item -Name 'PrincipalName' -Default $principalId)
            $assignmentType = [string](Get-PropertyOrDefault -InputObject $item -Name 'AssignmentType' -Default 'Permanent')
            $viaGroupId = [string](Get-PropertyOrDefault -InputObject $item -Name 'ViaGroupId' -Default '')
            $target = "$principalName as $roleName on $(Get-PropertyOrDefault -InputObject $item -Name 'ScopeDetail' -Default $scope)"

            if ($roleScope -notin 'Azure', 'Entra' -or -not $roleDefinitionId -or -not $principalId) {
                & $result -Item $item -Result 'Skipped' -Reason 'Entry lacks RoleScope, RoleDefinitionId or PrincipalId'
                continue
            }
            if ($assignmentType -ne 'Permanent') {
                & $result -Item $item -Result 'Skipped' -Reason "$assignmentType assignments are managed in PIM"
                continue
            }
            if ($viaGroupId) {
                & $result -Item $item -Result 'Skipped' -Reason 'Inherited through a group; the group assignment was never removed'
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($target, "Restore $roleScope role assignment")) {
                & $result -Item $item -Result 'Skipped' -Reason 'Declined or -WhatIf'
                continue
            }
            if ($roleScope -eq 'Entra' -and -not (Test-RiskyRoleGraphScope -Scope $script:Catalog.GraphScopes.Write)) {
                throw "The Graph session lacks $($script:Catalog.GraphScopes.Write -join ', '). Run Connect-RiskyRolesAnalyzer -RequestWriteScopes and try again. Nothing was restored for $target."
            }

            try {
                if ($roleScope -eq 'Azure') {
                    $null = New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionId $roleDefinitionId -Scope $scope -ErrorAction Stop
                }
                else {
                    $body = @{
                        '@odata.type'    = '#microsoft.graph.unifiedRoleAssignment'
                        principalId      = $principalId
                        roleDefinitionId = $roleDefinitionId
                        directoryScopeId = if ($scope) { $scope } else { '/' }
                    }
                    $null = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' -Body $body -ContentType 'application/json' -ErrorAction Stop
                }
                & $result -Item $item -Result 'Restored' -Reason $null
            }
            catch {
                Write-Error -Message "${target}: restore failed. $($_.Exception.Message)" -ErrorAction Continue
                & $result -Item $item -Result 'Failed' -Reason $_.Exception.Message
            }
        }
    }
}
