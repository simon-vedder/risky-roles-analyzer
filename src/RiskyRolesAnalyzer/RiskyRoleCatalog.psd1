@{
    # Built-in Azure RBAC roles that are treated as privileged. Extend at run time with
    # Get-RiskyRoleAssignment -AdditionalAzureRole.
    PrivilegedAzureRoles = @(
        'Owner'
        'Contributor'
        'User Access Administrator'
        'Role Based Access Control Administrator'
        'Access Review Operator Service Role'
        'Reservation Purchaser'
        'Key Vault Administrator'
        'Storage Account Key Operator Service Role'
        # BloodHound "Dangerous Managed Roles"
        'Security Admin'
        'Resource Policy Contributor'
        # BloodHound "Transitive Managed Identity Access"
        'Virtual Machine Contributor'
        'Website Contributor'
        'Managed Identity Operator'
    )

    # Built-in Entra directory roles that are treated as privileged. Extend with -AdditionalEntraRole.
    PrivilegedEntraRoles = @(
        'Global Administrator'
        'Privileged Role Administrator'
        'Privileged Authentication Administrator'
        'User Administrator'
        'Application Administrator'
        'Cloud Application Administrator'
        'Authentication Administrator'
        'Conditional Access Administrator'
        'Security Administrator'
        'Exchange Administrator'
        'SharePoint Administrator'
        'Intune Administrator'
        'Helpdesk Administrator'
        'Hybrid Identity Administrator'
        'Domain Name Administrator'
        'External Identity Provider Administrator'
        'Partner Tier1 Support'
        'Partner Tier2 Support'
        'Directory Writers'
        'Groups Administrator'
    )

    # Actions that make a custom Azure RBAC role privileged. Matched against the role's Actions and
    # DataActions with wildcard support ("Microsoft.Authorization/*" grants roleAssignments/write),
    # then reduced by NotActions and NotDataActions.
    RiskyAzureActions = @(
        'Microsoft.Authorization/roleAssignments/write'
        'Microsoft.Authorization/roleAssignments/delete'
        'Microsoft.Authorization/denyAssignments/delete'
        'Microsoft.Authorization/roleDefinitions/write'
        'Microsoft.Authorization/roleDefinitions/delete'
        'Microsoft.Authorization/elevateAccess/action'
        'Microsoft.Authorization/policyAssignments/write'
        'Microsoft.Authorization/policyDefinitions/write'
        'Microsoft.ManagedIdentity/userAssignedIdentities/assign/action'
        'Microsoft.Compute/virtualMachines/runCommand/action'
        'Microsoft.Compute/virtualMachines/extensions/write'
        'Microsoft.KeyVault/vaults/accessPolicies/write'
        'Microsoft.Web/sites/publish/Action'
        'Microsoft.Web/sites/config/list/action'
    )

    # Resource actions that make a custom Entra directory role privileged.
    RiskyEntraActions = @(
        'microsoft.directory/users/create'
        'microsoft.directory/users/inviteGuest'
        'microsoft.directory/users/password/update'
        'microsoft.directory/users/authenticationMethods/update'
        'microsoft.directory/servicePrincipals/create'
        'microsoft.directory/servicePrincipals/credentials/update'
        'microsoft.directory/applications/create'
        'microsoft.directory/applications/credentials/update'
        'microsoft.directory/applications/owners/update'
        'microsoft.directory/groups/members/update'
        'microsoft.directory/roleAssignments/allProperties/allTasks'
        'microsoft.directory/roleDefinitions/allProperties/allTasks'
    )

    # Scoring. A 0.0 to 10.0 score: base per role, multiplied by scope breadth, then modified by
    # assignment type, principal type and whether the principal can sign in at all.
    Scoring              = @{
        DefaultBase       = 3.0
        CustomRoleBase    = 6.0
        CriticalRoleBase  = 9.0
        HighRoleBase      = 7.0
        MediumRoleBase    = 5.5
        CriticalRoles     = @(
            'Owner', 'User Access Administrator', 'Role Based Access Control Administrator'
            'Global Administrator', 'Privileged Role Administrator', 'Privileged Authentication Administrator'
        )
        HighRoles         = @(
            'Contributor', 'Security Admin', 'Security Administrator'
            'Application Administrator', 'Cloud Application Administrator'
            'Authentication Administrator', 'User Administrator'
            'Key Vault Administrator', 'Resource Policy Contributor'
        )
        MediumRoles       = @(
            'Virtual Machine Contributor', 'Website Contributor', 'Managed Identity Operator'
            'Conditional Access Administrator', 'Exchange Administrator'
            'SharePoint Administrator', 'Intune Administrator'
            'Helpdesk Administrator', 'Hybrid Identity Administrator'
            'Domain Name Administrator', 'External Identity Provider Administrator'
            'Groups Administrator', 'Directory Writers'
            'Partner Tier1 Support', 'Partner Tier2 Support'
            'Storage Account Key Operator Service Role'
            'Access Review Operator Service Role', 'Reservation Purchaser'
        )
        # A custom role that grants one of these is rated like a critical built-in role.
        CriticalActions   = @(
            'Microsoft.Authorization/roleAssignments/write'
            'Microsoft.Authorization/roleDefinitions/write'
            'Microsoft.Authorization/elevateAccess/action'
            'Microsoft.Authorization/denyAssignments/delete'
            'microsoft.directory/roleAssignments/allProperties/allTasks'
            'microsoft.directory/roleDefinitions/allProperties/allTasks'
            'microsoft.directory/users/password/update'
            'microsoft.directory/applications/credentials/update'
            'microsoft.directory/servicePrincipals/credentials/update'
        )
        StackedActionBonus = 0.5   # three or more risky actions in one custom role
        ScopeMultiplier   = @{
            Root            = 1.0
            Tenant          = 1.0
            ManagementGroup = 0.95
            Subscription    = 0.85
            ResourceGroup   = 0.65
            AdminUnit       = 0.65
            Resource        = 0.45
            Object          = 0.45
            Other           = 0.85
        }
        EligibleModifier  = -1.5   # PIM eligible: has to be activated first
        ApplicationModifier = 0.5  # apps and managed identities are quieter persistence vectors
        ActivityModifier  = @{
            Disabled           = -2.0
            NoValidCredential  = -1.0
            BlockedByMicrosoft = -2.5
        }
        # Severity labels by score, checked from the top.
        Severity          = @(
            @{ Name = 'Critical'; Minimum = 9.0 }
            @{ Name = 'High'; Minimum = 7.0 }
            @{ Name = 'Medium'; Minimum = 5.0 }
            @{ Name = 'Low'; Minimum = 3.0 }
            @{ Name = 'Info'; Minimum = 0.0 }
        )
    }

    # Names that usually mean an emergency access account. Only a hint: the module protects what
    # -BreakGlassAccount names, and warns when an unprotected principal matches this pattern.
    BreakGlassNamePattern = '(?i)break.?glass|emergency.?access|^bg[-_ ]?\d|^emergency'

    # Graph scopes. The read set is what Get-RiskyRoleAssignment needs; the write scope is only
    # requested with Connect-RiskyRolesAnalyzer -RequestWriteScopes and only used by Remove-.
    GraphScopes          = @{
        Read  = @('RoleManagement.Read.Directory', 'Directory.Read.All', 'Group.Read.All', 'Application.Read.All')
        Write = @('RoleManagement.ReadWrite.Directory')
    }
}
