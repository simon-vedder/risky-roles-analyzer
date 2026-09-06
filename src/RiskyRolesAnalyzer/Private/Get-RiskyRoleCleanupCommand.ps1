function Get-RiskyRoleCleanupCommand {
    <#
    .SYNOPSIS
    Native Az or Graph commands that would remove one finding, for people who want to see the call.
    .DESCRIPTION
    Pure rule. Returns Primary and Alt. Findings inherited through a group get the membership
    removal as Primary and the group's own assignment as Alt; PIM eligibility is a portal task.
    Remove-RiskyRoleAssignment does not run these strings, it makes the equivalent call itself.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Azure', 'Entra')]
        [string]$RoleScope,

        [Parameter(Mandatory)]
        [string]$RoleName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$PrincipalId,

        [Parameter(Mandatory)]
        [ValidateSet('Permanent', 'Eligible', 'Activated')]
        [string]$AssignmentType,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$AssignmentId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ViaGroupId
    )

    $primary = $null
    $alt = $null

    if ($ViaGroupId) {
        $primary = "Remove-AzADGroupMember -GroupObjectId '$ViaGroupId' -MemberObjectId '$PrincipalId'"
        $alt = if ($RoleScope -eq 'Azure') {
            "Remove-AzRoleAssignment -ObjectId '$ViaGroupId' -RoleDefinitionName '$RoleName' -Scope '$Scope'  # removes the role for the ENTIRE group"
        }
        elseif ($AssignmentId) {
            "Invoke-MgGraphRequest -Method DELETE -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$AssignmentId'  # removes the role for the ENTIRE group"
        }
        else {
            "# Remove the group's assignment in the Entra portal: Roles and administrators > $RoleName"
        }
    }
    elseif ($RoleScope -eq 'Azure') {
        $primary = "Remove-AzRoleAssignment -ObjectId '$PrincipalId' -RoleDefinitionName '$RoleName' -Scope '$Scope'"
    }
    elseif ($AssignmentType -eq 'Eligible') {
        $primary = "# Remove the PIM eligibility of '$PrincipalId' for '$RoleName' in the Entra portal: PIM > Entra roles > Eligible assignments"
    }
    elseif ($AssignmentType -eq 'Activated') {
        $primary = "# '$PrincipalId' has activated '$RoleName' through PIM. Deactivate it or remove the eligibility in PIM; deleting the assignment only ends this activation."
    }
    elseif ($AssignmentId) {
        $primary = "Invoke-MgGraphRequest -Method DELETE -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$AssignmentId'"
    }
    else {
        $primary = "# Remove the assignment of '$PrincipalId' for '$RoleName' in the Entra portal: Roles and administrators > $RoleName"
    }

    [pscustomobject]@{ Primary = $primary; Alt = $alt }
}
