#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $manifestPath = Join-Path $PSScriptRoot '..' 'src' 'RiskyRolesAnalyzer' 'RiskyRolesAnalyzer.psd1'
    Import-Module $manifestPath -Force -ErrorAction Stop
    $module = Get-Module RiskyRolesAnalyzer

    # Private functions are fetched from the module scope once. Invoking the FunctionInfo runs the
    # body inside the module, so $script: variables resolve as they do in production.
    $Private = & $module {
        @{
            Match     = Get-Command Test-RiskyRoleActionMatch
            Action    = Get-Command Get-RiskyRoleAction
            Scope     = Get-Command Resolve-RoleScope
            Score     = Get-Command Get-RiskyRoleScore
            Severity  = Get-Command ConvertTo-RiskyRoleSeverity
            Summary   = Get-Command Get-CredentialSummary
            Activity  = Get-Command Resolve-PrincipalActivity
            Cleanup   = Get-Command Get-RiskyRoleCleanupCommand
            FindingId = Get-Command Get-RiskyRoleFindingId
            Finding   = Get-Command Resolve-RiskyRoleAssignmentFinding
            Property  = Get-Command Get-PropertyOrDefault
            Members   = Get-Command Get-GroupMemberRecursive
            Principal = Get-Command Resolve-DirectoryPrincipal
            Inventory = Get-Command Get-ApplicationInventory
            Permission = Get-Command Get-RoleDefinitionPermission
            Literal    = Get-Command ConvertTo-PowerShellLiteral
        }
    }

    function New-Principal {
        param([hashtable]$Override = @{})
        $principal = @{
            ObjectId = 'p-1'; Type = 'User'; DisplayName = 'Alice'; UPN = 'alice@contoso.com'; AppId = $null
            IsEnabled = $true; ActivityStatus = 'Active'; ActivityReason = $null
        }
        foreach ($key in $Override.Keys) { $principal[$key] = $Override[$key] }
        [pscustomobject]$principal
    }

    function New-Finding {
        # A typed finding without Graph, for Remove- tests.
        param([hashtable]$Override = @{})
        $params = @{
            RoleScope = 'Azure'; RoleName = 'Owner'; RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
            Scope = '/subscriptions/00000000-0000-0000-0000-000000000001'; ScopeName = 'Prod'
            AssignmentType = 'Permanent'; AssignmentId = '/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleAssignments/ra-1'
            Principal = (New-Principal)
        }
        foreach ($key in $Override.Keys) { $params[$key] = $Override[$key] }
        & $Private.Finding @params
    }

    # ---- Synthetic tenant -----------------------------------------------------------------
    # Ids are readable on purpose; Azure role definition ids are real GUIDs because
    # Remove-AzRoleAssignment types that parameter as [Guid].
    $Fixture = @{
        TenantId = 'tenant-1'
        Me       = 'me@contoso.com'
        Roles    = @{
            Owner       = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
            Contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
            Reader      = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
            Custom      = 'aaaaaaaa-1111-2222-3333-444444444444'
        }
        Objects  = @{
            'u-alice'        = @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-alice'; displayName = 'Alice Admin'; userPrincipalName = 'alice@contoso.com'; accountEnabled = $true }
            'u-bob'          = @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-bob'; displayName = 'Bob Leaver'; userPrincipalName = 'bob@contoso.com'; accountEnabled = $false }
            'u-carol'        = @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-carol'; displayName = 'Carol PIM'; userPrincipalName = 'carol@contoso.com'; accountEnabled = $true }
            'u-glass'        = @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-glass'; displayName = 'Break Glass'; userPrincipalName = 'breakglass@contoso.com'; accountEnabled = $true }
            'u-me'           = @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-me'; displayName = 'Me'; userPrincipalName = 'me@contoso.com'; accountEnabled = $true }
            'u-dave'         = @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-dave'; displayName = 'Dave Activated'; userPrincipalName = 'dave@contoso.com'; accountEnabled = $true }
            'g-admins'       = @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-admins'; displayName = 'Cloud Admins' }
            'g-nested'       = @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'Nested Admins' }
            'sp-app-dormant' = @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-app-dormant'; displayName = 'Legacy Deploy App'; appId = 'app-dormant'; servicePrincipalType = 'Application'; accountEnabled = $true; disabledByMicrosoftStatus = $null }
            'sp-app-off'     = @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-app-off'; displayName = 'Retired App'; appId = 'app-off'; servicePrincipalType = 'Application'; accountEnabled = $true; disabledByMicrosoftStatus = $null }
            'sp-mi'          = @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-mi'; displayName = 'vm-web-identity'; appId = 'app-mi'; servicePrincipalType = 'ManagedIdentity'; accountEnabled = $true; disabledByMicrosoftStatus = $null }
            'sp-ent'         = @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-ent'; displayName = 'Third Party SaaS'; appId = 'app-ent'; servicePrincipalType = 'Application'; accountEnabled = $true; disabledByMicrosoftStatus = $null }
        }
        Members  = @{
            'g-admins' = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-alice' }, @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested' })
            'g-nested' = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-bob' }, @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-admins' })
        }
        Applications = @(
            @{ id = 'obj-dormant'; appId = 'app-dormant'; displayName = 'Legacy Deploy App'; passwordCredentials = @(@{ startDateTime = '2024-01-01T00:00:00Z'; endDateTime = '2025-01-01T00:00:00Z' }); keyCredentials = @() }
            @{ id = 'obj-off'; appId = 'app-off'; displayName = 'Retired App'; passwordCredentials = @(@{ startDateTime = '2026-01-01T00:00:00Z'; endDateTime = '2028-01-01T00:00:00Z' }); keyCredentials = @() }
        )
        ApplicationFlags = @(@{ appId = 'app-dormant'; isDisabled = $false }, @{ appId = 'app-off'; isDisabled = $true })
        Subscriptions = @(
            [pscustomobject]@{ Id = 'sub-1'; Name = 'Prod'; State = 'Enabled'; TenantId = 'tenant-1' }
            [pscustomobject]@{ Id = 'sub-2'; Name = 'Dev'; State = 'Enabled'; TenantId = 'tenant-1' }
            [pscustomobject]@{ Id = 'sub-3'; Name = 'Old'; State = 'Disabled'; TenantId = 'tenant-1' }
        )
        CustomRoles = @(
            # Az.Resources 10 shape: the actions live in Permissions[]; the Harmless Reader below keeps the older flattened shape.
            [pscustomobject]@{ Id = 'aaaaaaaa-1111-2222-3333-444444444444'; Name = 'Custom Automation Role'; Permissions = @([pscustomobject]@{ Actions = @('Microsoft.Authorization/*', 'Microsoft.Compute/*/read'); NotActions = @('Microsoft.Authorization/*/delete'); DataActions = @(); NotDataActions = @(); Condition = $null; ConditionVersion = $null }) }
            [pscustomobject]@{ Id = 'bbbbbbbb-1111-2222-3333-444444444444'; Name = 'Harmless Reader'; Actions = @('*/read'); NotActions = @(); DataActions = @(); NotDataActions = @() }
        )
        AzureAssignments = @{
            '/subscriptions/sub-1' = @(
                [pscustomobject]@{ RoleAssignmentId = '/providers/Microsoft.Management/managementGroups/mg-root/providers/Microsoft.Authorization/roleAssignments/ra-az-mg'; Scope = '/providers/Microsoft.Management/managementGroups/mg-root'; RoleDefinitionName = 'Owner'; RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; ObjectId = 'g-admins' }
                [pscustomobject]@{ RoleAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleAssignments/ra-az-custom'; Scope = '/subscriptions/sub-1'; RoleDefinitionName = 'Custom Automation Role'; RoleDefinitionId = 'aaaaaaaa-1111-2222-3333-444444444444'; ObjectId = 'u-alice' }
                [pscustomobject]@{ RoleAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleAssignments/ra-az-dormant'; Scope = '/subscriptions/sub-1'; RoleDefinitionName = 'Contributor'; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; ObjectId = 'sp-app-dormant' }
                [pscustomobject]@{ RoleAssignmentId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Authorization/roleAssignments/ra-az-mi'; Scope = '/subscriptions/sub-1/resourceGroups/rg-app'; RoleDefinitionName = 'Owner'; RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; ObjectId = 'sp-mi' }
                [pscustomobject]@{ RoleAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleAssignments/ra-az-reader'; Scope = '/subscriptions/sub-1'; RoleDefinitionName = 'Reader'; RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; ObjectId = 'u-alice' }
                [pscustomobject]@{ RoleAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleAssignments/ra-az-harmless'; Scope = '/subscriptions/sub-1'; RoleDefinitionName = 'Harmless Reader'; RoleDefinitionId = 'bbbbbbbb-1111-2222-3333-444444444444'; ObjectId = 'u-alice' }
            )
            '/subscriptions/sub-2' = @(
                [pscustomobject]@{ RoleAssignmentId = '/providers/Microsoft.Management/managementGroups/mg-root/providers/Microsoft.Authorization/roleAssignments/ra-az-mg'; Scope = '/providers/Microsoft.Management/managementGroups/mg-root'; RoleDefinitionName = 'Owner'; RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; ObjectId = 'g-admins' }
                [pscustomobject]@{ RoleAssignmentId = '/subscriptions/sub-2/providers/Microsoft.Authorization/roleAssignments/ra-az-owner'; Scope = '/subscriptions/sub-2'; RoleDefinitionName = 'Owner'; RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; ObjectId = 'u-alice' }
            )
        }
        RoleDefinitions = @(
            @{ id = 'rd-ga'; displayName = 'Global Administrator'; isBuiltIn = $true; rolePermissions = @() }
            @{ id = 'rd-ua'; displayName = 'User Administrator'; isBuiltIn = $true; rolePermissions = @() }
            @{ id = 'rd-aa'; displayName = 'Application Administrator'; isBuiltIn = $true; rolePermissions = @() }
            @{ id = 'rd-caa'; displayName = 'Cloud Application Administrator'; isBuiltIn = $true; rolePermissions = @() }
            @{ id = 'rd-dr'; displayName = 'Directory Readers'; isBuiltIn = $true; rolePermissions = @() }
            @{ id = 'rd-custom'; displayName = 'Password Helper'; isBuiltIn = $false; rolePermissions = @(@{ allowedResourceActions = @('microsoft.directory/users/basic/update', 'microsoft.directory/users/password/update') }) }
            @{ id = 'rd-custom-ok'; displayName = 'Ticket Reader'; isBuiltIn = $false; rolePermissions = @(@{ allowedResourceActions = @('microsoft.directory/users/basic/read') }) }
        )
        RoleAssignments = @(
            @{ id = 'ra-1'; principalId = 'u-alice'; roleDefinitionId = 'rd-ga'; directoryScopeId = '/' }
            @{ id = 'ra-2'; principalId = 'u-bob'; roleDefinitionId = 'rd-ua'; directoryScopeId = '/' }
            @{ id = 'ra-3'; principalId = 'sp-ent'; roleDefinitionId = 'rd-aa'; directoryScopeId = '/' }
            @{ id = 'ra-4'; principalId = 'u-glass'; roleDefinitionId = 'rd-ga'; directoryScopeId = '/' }
            @{ id = 'ra-5'; principalId = 'u-me'; roleDefinitionId = 'rd-ga'; directoryScopeId = '/' }
            @{ id = 'ra-6'; principalId = 'sp-ent'; roleDefinitionId = 'rd-custom'; directoryScopeId = '/administrativeUnits/au-1' }
            @{ id = 'ra-7'; principalId = 'u-alice'; roleDefinitionId = 'rd-dr'; directoryScopeId = '/' }
            @{ id = 'ra-8'; principalId = 'sp-app-off'; roleDefinitionId = 'rd-caa'; directoryScopeId = '/' }
            @{ id = 'ra-9'; principalId = 'u-alice'; roleDefinitionId = 'rd-custom-ok'; directoryScopeId = '/' }
            @{ id = 'ra-10'; principalId = 'u-dave'; roleDefinitionId = 'rd-ga'; directoryScopeId = '/' }
        )
        Schedules = @(
            @{ id = 'ras-1'; principalId = 'u-dave'; roleDefinitionId = 'rd-ga'; directoryScopeId = '/'; assignmentType = 'Activated' }
            @{ id = 'ras-2'; principalId = 'u-alice'; roleDefinitionId = 'rd-ga'; directoryScopeId = '/'; assignmentType = 'Assigned' }
        )
        Eligible = @(
            @{ id = 're-1'; principalId = 'u-carol'; roleDefinitionId = 'rd-ga'; directoryScopeId = '/' }
        )
    }

    function Select-FirstTwo {
        # Stand-in for Out-ConsoleGridView: same parameters, picks the first two rows.
        param([Parameter(ValueFromPipeline)]$InputObject, [string]$Title, [string]$OutputMode)
        begin { $rows = [System.Collections.Generic.List[object]]::new() }
        process { $rows.Add($InputObject) }
        end { $rows | Select-Object -First 2 }
    }

    function Select-NothingAndRecord {
        # Stand-in for Out-ConsoleGridView that records what it was handed and picks nothing.
        param([Parameter(ValueFromPipeline)]$InputObject, [string]$Title, [string]$OutputMode)
        begin { $rows = [System.Collections.Generic.List[object]]::new() }
        process { $rows.Add($InputObject) }
        end { $script:GridRows = $rows.ToArray(); $script:GridTitle = $Title; $script:GridMode = $OutputMode }
    }

    $script:GraphCalls = [System.Collections.Generic.List[object]]::new()
    $script:FailEligibility = $false

    function Invoke-FixtureGraph {
        param($Method, $Uri)
        $script:GraphCalls.Add(@{ Method = [string]$Method; Uri = [string]$Uri })
        if ([string]$Method -eq 'DELETE') { return $null }
        if ([string]$Method -eq 'POST') { return @{ id = 'ra-new' } }
        $u = [string]$Uri
        if ($u -match '/v1\.0/applications\?') { return @{ value = $Fixture.Applications } }
        if ($u -match '/beta/applications\?') { return @{ value = $Fixture.ApplicationFlags } }
        if ($u -match '/v1\.0/organization') { return @{ value = @(@{ displayName = 'Contoso' }) } }
        if ($u -match '/directoryObjects/([^/?]+)') {
            $id = $Matches[1]
            if (-not $Fixture.Objects.ContainsKey($id)) { throw "404 Not Found: $id" }
            $o = $Fixture.Objects[$id]
            return @{ '@odata.type' = $o.'@odata.type'; id = $o.id; displayName = $o.displayName; userPrincipalName = $o['userPrincipalName']; appId = $o['appId']; servicePrincipalType = $o['servicePrincipalType'] }
        }
        if ($u -match '/users/([^/?]+)') { $o = $Fixture.Objects[$Matches[1]]; return @{ accountEnabled = $o.accountEnabled; userPrincipalName = $o.userPrincipalName } }
        if ($u -match '/servicePrincipals/([^/?]+)') { $o = $Fixture.Objects[$Matches[1]]; return @{ accountEnabled = $o.accountEnabled; disabledByMicrosoftStatus = $o.disabledByMicrosoftStatus; appId = $o.appId; servicePrincipalType = $o.servicePrincipalType } }
        if ($u -match '/groups/([^/]+)/members') { return @{ value = $Fixture.Members[$Matches[1]] } }
        if ($u -match '/roleManagement/directory/roleDefinitions') { return @{ value = $Fixture.RoleDefinitions } }
        if ($u -match '/roleManagement/directory/roleAssignmentSchedules') {
            if ($script:FailEligibility) { throw '403 Forbidden: AadPremiumLicenseRequired' }
            return @{ value = $Fixture.Schedules }
        }
        if ($u -match '/roleManagement/directory/roleAssignments(\?|$)') { return @{ value = $Fixture.RoleAssignments } }
        if ($u -match '/roleManagement/directory/roleEligibilitySchedules') {
            if ($script:FailEligibility) { throw '403 Forbidden: AadPremiumLicenseRequired' }
            return @{ value = $Fixture.Eligible }
        }
        throw "Unexpected Graph call in fixture: $u"
    }
}

Describe 'Module' {
    BeforeDiscovery {
        $publicFolder = Join-Path $PSScriptRoot '..' 'src' 'RiskyRolesAnalyzer' 'Public'
        $publicFunctions = @(Get-ChildItem -Path $publicFolder -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        $stateChanging = @($publicFunctions | Where-Object { ($_ -split '-')[0] -in 'Remove', 'Set', 'New', 'Start', 'Stop', 'Restore', 'Update', 'Clear', 'Disable', 'Enable' })
    }

    It 'has a valid manifest' {
        Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions in Public/ and the manifest agrees' {
        $public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'src' 'RiskyRolesAnalyzer' 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        @($module.ExportedFunctions.Keys | Sort-Object) | Should -Be $public
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be $public
    }

    It 'documents <_> with synopsis, description and an example' -ForEach $publicFunctions {
        $help = Get-Help -Name $_ -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It '<_> changes state, so it supports ShouldProcess' -ForEach $stateChanging {
        $metadata = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name $_))
        $metadata.SupportsShouldProcess | Should -BeTrue
        if ($_ -like 'Remove-*') { $metadata.ConfirmImpact | Should -Be 'High' }
    }

    It 'keeps every source file free of control characters' {
        $files = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'src') -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.ps1xml'
        foreach ($file in $files) {
            (Get-Content -Path $file.FullName -Raw) | Should -Not -Match '[\x00-\x08\x0b\x0c\x0e-\x1f]' -Because "$($file.Name) must not carry stray control characters"
        }
    }

    It 'loads the catalog with every section the rules need' {
        $catalog = & $module { $script:Catalog }
        foreach ($key in 'PrivilegedAzureRoles', 'PrivilegedEntraRoles', 'RiskyAzureActions', 'RiskyEntraActions', 'Scoring', 'GraphScopes') {
            $catalog.ContainsKey($key) | Should -BeTrue -Because "catalog needs $key"
        }
        $catalog.Scoring.Severity[0].Name | Should -Be 'Critical'
    }
}

Describe 'Test-RiskyRoleActionMatch' {
    It 'matches exact actions' { (& $Private.Match -Pattern 'Microsoft.Authorization/roleAssignments/write' -Action 'Microsoft.Authorization/roleAssignments/write') | Should -BeTrue }
    It 'is case-insensitive' { (& $Private.Match -Pattern 'microsoft.authorization/roleassignments/WRITE' -Action 'Microsoft.Authorization/roleAssignments/write') | Should -BeTrue }
    It 'expands a trailing wildcard' { (& $Private.Match -Pattern 'Microsoft.Authorization/*' -Action 'Microsoft.Authorization/roleAssignments/write') | Should -BeTrue }
    It 'expands an inner wildcard' { (& $Private.Match -Pattern 'Microsoft.Authorization/*/delete' -Action 'Microsoft.Authorization/roleAssignments/delete') | Should -BeTrue }
    It 'treats * as everything' { (& $Private.Match -Pattern '*' -Action 'microsoft.directory/users/password/update') | Should -BeTrue }
    It 'does not match a different provider' { (& $Private.Match -Pattern 'Microsoft.Compute/*' -Action 'Microsoft.Authorization/roleAssignments/write') | Should -BeFalse }
    It 'does not match empty input' { (& $Private.Match -Pattern '' -Action 'x') | Should -BeFalse }
}

Describe 'Get-RiskyRoleAction' {
    BeforeAll { $risky = @('Microsoft.Authorization/roleAssignments/write', 'Microsoft.Authorization/roleAssignments/delete', 'Microsoft.Compute/virtualMachines/runCommand/action') }

    It 'returns the risky actions a wildcard grants' {
        $hits = @(& $Private.Action -Action @('Microsoft.Authorization/*') -RiskyAction $risky)
        $hits | Should -Be @('Microsoft.Authorization/roleAssignments/write', 'Microsoft.Authorization/roleAssignments/delete')
    }
    It 'removes what NotActions take away' {
        $hits = @(& $Private.Action -Action @('*') -NotAction @('Microsoft.Authorization/*/delete') -RiskyAction $risky)
        $hits | Should -Be @('Microsoft.Authorization/roleAssignments/write', 'Microsoft.Compute/virtualMachines/runCommand/action')
    }
    It 'counts DataActions and honours NotDataActions' {
        @(& $Private.Action -DataAction @('Microsoft.Compute/*') -RiskyAction $risky) | Should -Be @('Microsoft.Compute/virtualMachines/runCommand/action')
        @(& $Private.Action -DataAction @('Microsoft.Compute/*') -NotDataAction @('*/runCommand/action') -RiskyAction $risky).Count | Should -Be 0
    }
    It 'returns nothing for a read-only role' {
        @(& $Private.Action -Action @('*/read') -RiskyAction $risky).Count | Should -Be 0
    }
    It 'tolerates null lists' {
        @(& $Private.Action -Action $null -NotAction $null -RiskyAction $risky).Count | Should -Be 0
    }
}

Describe 'Get-RoleDefinitionPermission' {
    It 'reads the Permissions blocks of an Az.Resources 10 role definition' {
        $definition = [pscustomobject]@{
            Id = 'r1'; Name = 'Two blocks'
            Permissions = @(
                [pscustomobject]@{ Actions = @('Microsoft.Compute/*'); NotActions = @('Microsoft.Compute/*/delete'); DataActions = @(); NotDataActions = @(); Condition = $null; ConditionVersion = $null }
                [pscustomobject]@{ Actions = @(); NotActions = @(); DataActions = @('Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'); NotDataActions = @(); Condition = '@Resource[...]'; ConditionVersion = '2.0' }
            )
        }
        $blocks = @(& $Private.Permission -Definition $definition)
        $blocks.Count | Should -Be 2
        $blocks[0].Actions | Should -Be @('Microsoft.Compute/*')
        $blocks[0].NotActions | Should -Be @('Microsoft.Compute/*/delete')
        $blocks[1].DataActions | Should -Be @('Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read')
        @($blocks[1].Actions).Count | Should -Be 0
    }
    It 'falls back to the flattened properties of older Az.Resources versions' {
        $definition = [pscustomobject]@{ Id = 'r2'; Name = 'Flat'; Actions = @('*'); NotActions = @('Microsoft.Authorization/*/write'); DataActions = $null; NotDataActions = @() }
        $blocks = @(& $Private.Permission -Definition $definition)
        $blocks.Count | Should -Be 1
        $blocks[0].Actions | Should -Be @('*')
        $blocks[0].NotActions | Should -Be @('Microsoft.Authorization/*/write')
        @($blocks[0].DataActions).Count | Should -Be 0
    }
    It 'returns one empty block for a definition without any actions' {
        $blocks = @(& $Private.Permission -Definition ([pscustomobject]@{ Id = 'r3'; Name = 'Empty' }))
        $blocks.Count | Should -Be 1
        @($blocks[0].Actions).Count | Should -Be 0
    }
}

Describe 'Resolve-RoleScope' {
    It 'classifies <Scope> as <Level>' -ForEach @(
        @{ RoleScope = 'Azure'; Scope = '/'; Level = 'Root' }
        @{ RoleScope = 'Azure'; Scope = ''; Level = 'Root' }
        @{ RoleScope = 'Azure'; Scope = '/providers/Microsoft.Management/managementGroups/mg-root'; Level = 'ManagementGroup' }
        @{ RoleScope = 'Azure'; Scope = '/subscriptions/00000000-0000-0000-0000-000000000001'; Level = 'Subscription' }
        @{ RoleScope = 'Azure'; Scope = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-app'; Level = 'ResourceGroup' }
        @{ RoleScope = 'Azure'; Scope = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv1'; Level = 'Resource' }
        @{ RoleScope = 'Azure'; Scope = '/something/else'; Level = 'Other' }
        @{ RoleScope = 'Entra'; Scope = '/'; Level = 'Tenant' }
        @{ RoleScope = 'Entra'; Scope = '/administrativeUnits/au-1'; Level = 'AdminUnit' }
        @{ RoleScope = 'Entra'; Scope = '/app-object-id'; Level = 'Object' }
    ) {
        (& $Private.Scope -Scope $Scope -RoleScope $RoleScope).Level | Should -Be $Level
    }
    It 'names the resource group and the resource' {
        (& $Private.Scope -Scope '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-app' -RoleScope Azure).Detail | Should -Be 'RG: rg-app'
        (& $Private.Scope -Scope '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv1' -RoleScope Azure).Detail | Should -Be 'Resource: kv1'
    }
}

Describe 'Get-RiskyRoleScore' {
    It 'rates a Global Administrator tenant-wide as 9.0' {
        (& $Private.Score -RoleName 'Global Administrator' -ScopeLevel Tenant -PrincipalType User -AssignmentType Permanent) | Should -Be 9.0
    }
    It 'rates Owner at the root as 9.0 and at a resource group lower' {
        (& $Private.Score -RoleName 'Owner' -ScopeLevel Root -PrincipalType User -AssignmentType Permanent) | Should -Be 9.0
        (& $Private.Score -RoleName 'Owner' -ScopeLevel ResourceGroup -PrincipalType User -AssignmentType Permanent) | Should -BeLessThan 6.0
    }
    It 'lowers PIM eligible by 1.5' {
        (& $Private.Score -RoleName 'Global Administrator' -ScopeLevel Tenant -PrincipalType User -AssignmentType Eligible) | Should -Be 7.5
    }
    It 'adds 0.5 for applications and managed identities' {
        (& $Private.Score -RoleName 'Contributor' -ScopeLevel Root -PrincipalType ManagedIdentity -AssignmentType Permanent) | Should -Be 7.5
    }
    It 'lowers the live risk for principals that cannot sign in' {
        (& $Private.Score -RoleName 'User Administrator' -ScopeLevel Tenant -PrincipalType User -AssignmentType Permanent -ActivityStatus Disabled) | Should -Be 5.0
        (& $Private.Score -RoleName 'User Administrator' -ScopeLevel Tenant -PrincipalType EnterpriseApp -AssignmentType Permanent -ActivityStatus BlockedByMicrosoft) | Should -Be 5.0
    }
    It 'rates a custom role by what it grants' {
        (& $Private.Score -RoleName 'Custom' -ScopeLevel Root -PrincipalType User -AssignmentType Permanent -IsCustomRole $true -RiskyAction @('Microsoft.Compute/virtualMachines/runCommand/action')) | Should -Be 6.0
        (& $Private.Score -RoleName 'Custom' -ScopeLevel Root -PrincipalType User -AssignmentType Permanent -IsCustomRole $true -RiskyAction @('Microsoft.Authorization/roleAssignments/write')) | Should -Be 9.0
        (& $Private.Score -RoleName 'Custom' -ScopeLevel Root -PrincipalType User -AssignmentType Permanent -IsCustomRole $true -RiskyAction @('a', 'b', 'c')) | Should -Be 6.5
    }
    It 'stays inside 0 and 10' {
        (& $Private.Score -RoleName 'Nobody' -ScopeLevel Resource -PrincipalType User -AssignmentType Eligible -ActivityStatus BlockedByMicrosoft) | Should -Be 0
        (& $Private.Score -RoleName 'Custom' -ScopeLevel Root -PrincipalType ManagedIdentity -AssignmentType Permanent -IsCustomRole $true -RiskyAction @('Microsoft.Authorization/roleAssignments/write', 'b', 'c')) | Should -Be 10
    }
}

Describe 'ConvertTo-RiskyRoleSeverity' {
    It 'maps <Score> to <Severity>' -ForEach @(
        @{ Score = 10; Severity = 'Critical' }, @{ Score = 9.0; Severity = 'Critical' }, @{ Score = 8.9; Severity = 'High' }
        @{ Score = 7.0; Severity = 'High' }, @{ Score = 6.9; Severity = 'Medium' }, @{ Score = 5.0; Severity = 'Medium' }
        @{ Score = 4.9; Severity = 'Low' }, @{ Score = 3.0; Severity = 'Low' }, @{ Score = 2.9; Severity = 'Info' }, @{ Score = 0; Severity = 'Info' }
    ) {
        (& $Private.Severity -Score $Score) | Should -Be $Severity
    }
}

Describe 'Get-CredentialSummary' {
    BeforeAll { $now = [datetime]'2026-06-01T00:00:00Z' }

    It 'counts an app without credentials as none' {
        $summary = & $Private.Summary -Application @{ passwordCredentials = @(); keyCredentials = @() } -Now $now
        $summary.CredentialCount | Should -Be 0
        $summary.HasValidCredential | Should -BeFalse
    }
    It 'sees an expired secret' {
        $summary = & $Private.Summary -Application @{ passwordCredentials = @(@{ startDateTime = '2024-01-01T00:00:00Z'; endDateTime = '2025-01-01T00:00:00Z' }) } -Now $now
        $summary.CredentialCount | Should -Be 1
        $summary.ExpiredCount | Should -Be 1
        $summary.HasValidCredential | Should -BeFalse
    }
    It 'sees a valid certificate next to an expired secret' {
        $summary = & $Private.Summary -Application @{
            passwordCredentials = @(@{ startDateTime = '2024-01-01T00:00:00Z'; endDateTime = '2025-01-01T00:00:00Z' })
            keyCredentials      = @(@{ startDateTime = '2026-01-01T00:00:00Z'; endDateTime = '2027-01-01T00:00:00Z' })
        } -Now $now
        $summary.CredentialCount | Should -Be 2
        $summary.ExpiredCount | Should -Be 1
        $summary.HasValidCredential | Should -BeTrue
    }
    It 'treats a not-yet-valid credential as unusable' {
        $summary = & $Private.Summary -Application @{ passwordCredentials = @(@{ startDateTime = '2027-01-01T00:00:00Z'; endDateTime = '2028-01-01T00:00:00Z' }) } -Now $now
        $summary.HasValidCredential | Should -BeFalse
        $summary.ExpiredCount | Should -Be 0
    }
}

Describe 'Resolve-PrincipalActivity' {
    It 'user: disabled, enabled, unknown' {
        (& $Private.Activity -Type User -AccountEnabled $false).ActivityStatus | Should -Be 'Disabled'
        (& $Private.Activity -Type User -AccountEnabled $true).ActivityStatus | Should -Be 'Active'
        (& $Private.Activity -Type User -AccountEnabled $null).ActivityStatus | Should -Be 'Unknown'
    }
    It 'group: always active' { (& $Private.Activity -Type Group).ActivityStatus | Should -Be 'Active' }
    It 'service principal: sign-in disabled beats blocked by Microsoft' {
        $r = & $Private.Activity -Type EnterpriseApp -AccountEnabled $false -DisabledByMicrosoftStatus 'DisabledDueToViolationOfServicesAgreement'
        $r.ActivityStatus | Should -Be 'Disabled'
        $r.ActivityReason | Should -Be 'Service principal sign-in disabled'
    }
    It 'service principal: blocked by Microsoft' {
        $r = & $Private.Activity -Type EnterpriseApp -AccountEnabled $true -DisabledByMicrosoftStatus 'DisabledDueToViolationOfServicesAgreement'
        $r.ActivityStatus | Should -Be 'BlockedByMicrosoft'
        $r.ActivityReason | Should -Match 'ViolationOfServicesAgreement'
    }
    It 'managed identity: active without credentials' { (& $Private.Activity -Type ManagedIdentity -AccountEnabled $true).ActivityStatus | Should -Be 'Active' }
    It 'enterprise app: active' { (& $Private.Activity -Type EnterpriseApp -AccountEnabled $true).ActivityStatus | Should -Be 'Active' }
    It 'app registration: deactivated' {
        (& $Private.Activity -Type AppRegistration -AccountEnabled $true -ApplicationInfo @{ IsDisabled = $true; CredentialCount = 2; HasValidCredential = $true }).ActivityReason | Should -Be 'App registration deactivated'
    }
    It 'app registration: no credentials, all expired, valid' {
        (& $Private.Activity -Type AppRegistration -AccountEnabled $true -ApplicationInfo @{ IsDisabled = $false; CredentialCount = 0; HasValidCredential = $false }).ActivityReason | Should -Be 'No password or certificate credentials'
        (& $Private.Activity -Type AppRegistration -AccountEnabled $true -ApplicationInfo @{ IsDisabled = $false; CredentialCount = 3; HasValidCredential = $false }).ActivityReason | Should -Be 'All 3 credentials expired'
        (& $Private.Activity -Type AppRegistration -AccountEnabled $true -ApplicationInfo @{ IsDisabled = $false; CredentialCount = 1; HasValidCredential = $true }).ActivityStatus | Should -Be 'Active'
    }
    It 'app registration: unknown without inventory' {
        (& $Private.Activity -Type AppRegistration -AccountEnabled $true -ApplicationInfo $null).ActivityStatus | Should -Be 'Unknown'
    }
}

Describe 'ConvertTo-PowerShellLiteral' {
    It 'doubles apostrophes so a name cannot end the quoted string' {
        (& $Private.Literal -Value "Simon's Admin Role") | Should -Be "Simon''s Admin Role"
    }
    It 'neutralises a name crafted to break out of the command' {
        $evil = "x'; Remove-AzResourceGroup -Name prod -Force #"
        $safe = & $Private.Literal -Value $evil
        $safe | Should -Be "x''; Remove-AzResourceGroup -Name prod -Force #"
        # Pasted back into a single-quoted string, the whole thing is one value again.
        $rebuilt = [scriptblock]::Create("'$safe'").Invoke()[0]
        $rebuilt | Should -Be $evil
    }
    It 'collapses line breaks and tabs so a name cannot start a statement of its own' {
        (& $Private.Literal -Value "Role`r`nRemove-Item /") | Should -Be 'Role Remove-Item /'
        (& $Private.Literal -Value "a`tb") | Should -Be 'a b'
    }
    It 'passes an ordinary value through and turns null into an empty string' {
        (& $Private.Literal -Value 'Owner') | Should -Be 'Owner'
        (& $Private.Literal -Value $null) | Should -Be ''
    }
}

Describe 'Get-RiskyRoleCleanupCommand' {
    It 'azure direct assignment' {
        (& $Private.Cleanup -RoleScope Azure -RoleName Owner -Scope '/subscriptions/s' -PrincipalId 'p' -AssignmentType Permanent).Primary | Should -Be "Remove-AzRoleAssignment -ObjectId 'p' -RoleDefinitionName 'Owner' -Scope '/subscriptions/s'"
    }
    It 'via group: membership first, group assignment as alternative' {
        $c = & $Private.Cleanup -RoleScope Azure -RoleName Owner -Scope '/subscriptions/s' -PrincipalId 'p' -AssignmentType Permanent -ViaGroupId 'g'
        $c.Primary | Should -Be "Remove-AzADGroupMember -GroupObjectId 'g' -MemberObjectId 'p'"
        $c.Alt | Should -Match "ObjectId 'g'"
    }
    It 'entra permanent by assignment id' {
        (& $Private.Cleanup -RoleScope Entra -RoleName 'Global Administrator' -Scope '/' -PrincipalId 'p' -AssignmentType Permanent -AssignmentId 'ra-1').Primary | Should -Match 'DELETE .*roleAssignments/ra-1'
    }
    It 'entra eligible is a PIM task' {
        (& $Private.Cleanup -RoleScope Entra -RoleName 'Global Administrator' -Scope '/' -PrincipalId 'p' -AssignmentType Eligible).Primary | Should -Match '^# .*PIM'
    }
}

Describe 'Get-RiskyRoleCleanupCommand escaping' {
    It 'quotes a role name with an apostrophe so the command still parses' {
        $c = & $Private.Cleanup -RoleScope Azure -RoleName "Simon's Admin Role" -Scope '/subscriptions/s1' -PrincipalId 'p1' -AssignmentType Permanent
        $c.Primary | Should -BeLike "*-RoleDefinitionName 'Simon''s Admin Role'*"
        { [scriptblock]::Create($c.Primary) } | Should -Not -Throw -Because 'the report offers this string with a copy button'
    }
    It 'keeps a hostile role name inside its quotes in every command it builds' {
        $evil = "x'; Remove-AzResourceGroup -Name prod -Force #"
        foreach ($params in @(
                @{ RoleScope = 'Azure'; AssignmentType = 'Permanent' },
                @{ RoleScope = 'Azure'; AssignmentType = 'Permanent'; ViaGroupId = 'g1' },
                @{ RoleScope = 'Entra'; AssignmentType = 'Permanent'; AssignmentId = 'ra-1' },
                @{ RoleScope = 'Entra'; AssignmentType = 'Eligible' },
                @{ RoleScope = 'Entra'; AssignmentType = 'Activated' },
                @{ RoleScope = 'Entra'; AssignmentType = 'Permanent' }
            )) {
            $c = & $Private.Cleanup -RoleName $evil -Scope '/' -PrincipalId 'p1' @params
            foreach ($command in @($c.Primary, $c.Alt | Where-Object { $_ })) {
                $command | Should -Not -Match "[^']'; Remove-AzResourceGroup" -Because 'the apostrophe must stay escaped'
                if (-not $command.StartsWith('#')) { { [scriptblock]::Create($command) } | Should -Not -Throw }
            }
        }
    }
}

Describe 'Get-RiskyRoleFindingId' {
    It 'is stable and short' {
        $a = & $Private.FindingId -RoleScope Azure -RoleName Owner -Scope '/subscriptions/s' -PrincipalId 'p' -AssignmentType Permanent
        $b = & $Private.FindingId -RoleScope azure -RoleName owner -Scope '/SUBSCRIPTIONS/S' -PrincipalId 'P' -AssignmentType permanent
        $a | Should -Be $b
        $a | Should -Match '^[0-9a-f]{12}$'
    }
    It 'changes with the group path' {
        $direct = & $Private.FindingId -RoleScope Azure -RoleName Owner -Scope '/subscriptions/s' -PrincipalId 'p' -AssignmentType Permanent
        $via = & $Private.FindingId -RoleScope Azure -RoleName Owner -Scope '/subscriptions/s' -PrincipalId 'p' -ViaGroupId 'g' -AssignmentType Permanent
        $direct | Should -Not -Be $via
    }
}

Describe 'Resolve-RiskyRoleAssignmentFinding' {
    It 'produces a typed finding with score, severity and cleanup' {
        $f = New-Finding
        $f.PSObject.TypeNames[0] | Should -Be 'RiskyRolesAnalyzer.RiskyRoleAssignment'
        $f.Severity | Should -Be 'High'
        $f.RiskScore | Should -Be 7.7
        $f.ScopeLevel | Should -Be 'Subscription'
        $f.CleanupPrimary | Should -Match 'Remove-AzRoleAssignment'
        $f.Protected | Should -BeFalse
        $f.Id | Should -Match '^[0-9a-f]{12}$'
    }
    It 'protects findings inherited through a group' {
        $f = New-Finding @{ ViaGroup = 'Cloud Admins'; ViaGroupId = 'g-admins' }
        $f.Protected | Should -BeTrue
        $f.ProtectedReason | Should -Match 'Cloud Admins'
    }
    It 'protects PIM eligibility' {
        (New-Finding @{ RoleScope = 'Entra'; RoleName = 'Global Administrator'; Scope = '/'; AssignmentType = 'Eligible'; AssignmentId = 're-1' }).ProtectedReason | Should -Match 'PIM'
    }
    It 'protects break-glass accounts by UPN and by object id' {
        (New-Finding @{ BreakGlassAccount = @('ALICE@contoso.com') }).ProtectedReason | Should -Be 'Break-glass account'
        (New-Finding @{ BreakGlassAccount = @('p-1') }).ProtectedReason | Should -Be 'Break-glass account'
        (New-Finding @{ BreakGlassAccount = @('someone@contoso.com') }).Protected | Should -BeFalse
    }
    It 'protects the identity running the audit' {
        (New-Finding @{ CurrentAccount = 'alice@contoso.com' }).ProtectedReason | Should -Be 'Identity running this audit'
        (New-Finding @{ CurrentAccount = 'other@contoso.com' }).Protected | Should -BeFalse
    }
    It 'carries the principal facts through' {
        $f = New-Finding @{ Principal = (New-Principal @{ Type = 'AppRegistration'; ActivityStatus = 'NoValidCredential'; ActivityReason = 'All 1 credentials expired'; AppId = 'app-1'; UPN = $null }) }
        $f.PrincipalType | Should -Be 'AppRegistration'
        $f.ActivityStatus | Should -Be 'NoValidCredential'
        $f.AppId | Should -Be 'app-1'
        $f.Severity | Should -Be 'High'   # 7.65 + 0.5 - 1.0
    }
}

Describe 'Collectors against the synthetic tenant' {
    BeforeAll {
        Mock -ModuleName RiskyRolesAnalyzer Invoke-MgGraphRequest { Invoke-FixtureGraph -Method $Method -Uri $Uri }
        Mock -ModuleName RiskyRolesAnalyzer Get-MgContext { [pscustomobject]@{ TenantId = $Fixture.TenantId; Account = $Fixture.Me; Scopes = @('RoleManagement.Read.Directory', 'Directory.Read.All', 'Group.Read.All', 'Application.Read.All') } }
        Mock -ModuleName RiskyRolesAnalyzer Get-AzContext { [pscustomobject]@{ Account = @{ Id = $Fixture.Me }; Tenant = @{ Id = $Fixture.TenantId }; Subscription = @{ Id = 'sub-1' } } }
        Mock -ModuleName RiskyRolesAnalyzer Get-AzSubscription { $Fixture.Subscriptions }
        Mock -ModuleName RiskyRolesAnalyzer Set-AzContext { $null }
        Mock -ModuleName RiskyRolesAnalyzer Get-AzRoleDefinition { $Fixture.CustomRoles }
        Mock -ModuleName RiskyRolesAnalyzer Get-AzRoleAssignment { $Fixture.AzureAssignments[[string]$Scope] }

        function New-Audit {
            & $module {
                @{
                    TenantId = 'tenant-1'; CurrentAccount = 'me@contoso.com'; BreakGlassAccount = @('breakglass@contoso.com')
                    PrivilegedAzureRoles = @($script:Catalog.PrivilegedAzureRoles); PrivilegedEntraRoles = @($script:Catalog.PrivilegedEntraRoles)
                    RiskyAzureActions = @($script:Catalog.RiskyAzureActions); RiskyEntraActions = @($script:Catalog.RiskyEntraActions)
                    Applications = @{}; Cache = @{ Principals = @{}; Groups = @{} }
                }
            }
        }
    }

    BeforeEach {
        $script:GraphCalls.Clear()
        $script:FailEligibility = $false
    }

    Context 'Get-ApplicationInventory' {
        It 'summarises credentials and picks up the beta deactivated flag' {
            $inventory = & $Private.Inventory
            $inventory.Count | Should -Be 2
            $inventory['app-dormant'].HasValidCredential | Should -BeFalse
            $inventory['app-dormant'].IsDisabled | Should -BeFalse
            $inventory['app-off'].HasValidCredential | Should -BeTrue
            $inventory['app-off'].IsDisabled | Should -BeTrue
        }
    }

    Context 'Resolve-DirectoryPrincipal' {
        It 'resolves and caches a user' {
            $audit = New-Audit
            $first = & $Private.Principal -ObjectId 'u-bob' -Audit $audit
            $calls = $script:GraphCalls.Count
            $second = & $Private.Principal -ObjectId 'u-bob' -Audit $audit
            $first.Type | Should -Be 'User'
            $first.ActivityStatus | Should -Be 'Disabled'
            $first.UPN | Should -Be 'bob@contoso.com'
            $second.ObjectId | Should -Be 'u-bob'
            $script:GraphCalls.Count | Should -Be $calls -Because 'the second lookup comes from the cache'
        }
        It 'classifies service principals' {
            $audit = New-Audit
            $audit.Applications = & $Private.Inventory
            (& $Private.Principal -ObjectId 'sp-mi' -Audit $audit).Type | Should -Be 'ManagedIdentity'
            (& $Private.Principal -ObjectId 'sp-ent' -Audit $audit).Type | Should -Be 'EnterpriseApp'
            $dormant = & $Private.Principal -ObjectId 'sp-app-dormant' -Audit $audit
            $dormant.Type | Should -Be 'AppRegistration'
            $dormant.ActivityStatus | Should -Be 'NoValidCredential'
            $dormant.ActivityReason | Should -Be 'All 1 credentials expired'
            (& $Private.Principal -ObjectId 'sp-app-off' -Audit $audit).ActivityReason | Should -Be 'App registration deactivated'
        }
        It 'returns an unresolved placeholder for an unknown id instead of failing' {
            $p = & $Private.Principal -ObjectId 'ghost' -Audit (New-Audit)
            $p.Type | Should -Be 'Unknown'
            $p.DisplayName | Should -Be '(unresolved)'
        }
    }

    Context 'Get-GroupMemberRecursive' {
        It 'flattens nested groups and survives a cycle' {
            $leaves = @(& $Private.Members -GroupId 'g-admins' -Audit (New-Audit))
            @($leaves | ForEach-Object ObjectId | Sort-Object) | Should -Be @('u-alice', 'u-bob')
        }
    }

    Context 'Get-RiskyRoleAssignment' {
        BeforeAll { $all = @(Get-RiskyRoleAssignment -BreakGlassAccount 'breakglass@contoso.com' -WarningAction SilentlyContinue) }

        It 'finds every privileged assignment once' {
            $all.Count | Should -Be 16
            @($all | Where-Object RoleScope -eq 'Azure').Count | Should -Be 7
            @($all | Where-Object RoleScope -eq 'Entra').Count | Should -Be 9
        }
        It 'returns typed, sorted findings' {
            $all[0].PSObject.TypeNames[0] | Should -Be 'RiskyRolesAnalyzer.RiskyRoleAssignment'
            $all[0].RiskScore | Should -Be ($all | Measure-Object RiskScore -Maximum).Maximum
        }
        It 'reports a management group assignment once although two subscriptions inherit it' {
            $mg = @($all | Where-Object { $_.AssignmentId -like '*ra-az-mg' })
            $mg.Count | Should -Be 3
            @($mg | Where-Object { -not $_.ViaGroupId }).Count | Should -Be 1
            @($mg | Where-Object ViaGroupId -eq 'g-admins' | ForEach-Object PrincipalName | Sort-Object) | Should -Be @('Alice Admin', 'Bob Leaver')
            @($mg | Where-Object ViaGroupId).Protected | Should -Not -Contain $false
            ($mg | Where-Object { -not $_.ViaGroupId }).ScopeLevel | Should -Be 'ManagementGroup'
        }
        It 'skips Reader and harmless custom roles' {
            @($all | Where-Object RoleName -in 'Reader', 'Harmless Reader', 'Directory Readers', 'Ticket Reader').Count | Should -Be 0
        }
        It 'rates a custom Azure role by its effective risky actions' {
            $custom = $all | Where-Object RoleName -eq 'Custom Automation Role'
            $custom.IsCustomRole | Should -BeTrue
            $custom.RiskyActions | Should -Contain 'Microsoft.Authorization/roleAssignments/write'
            $custom.RiskyActions | Should -Not -Contain 'Microsoft.Authorization/roleAssignments/delete'
            $custom.RiskyActions.Count | Should -Be 5
            $custom.Severity | Should -Be 'High'
        }
        It 'rates a custom Entra role scoped to an administrative unit' {
            $helper = $all | Where-Object RoleName -eq 'Password Helper'
            $helper.IsCustomRole | Should -BeTrue
            $helper.ScopeLevel | Should -Be 'AdminUnit'
            $helper.RiskyActions | Should -Be @('microsoft.directory/users/password/update')
            $helper.PrincipalType | Should -Be 'EnterpriseApp'
        }
        It 'flags the dormant app registration and the deactivated one' {
            ($all | Where-Object PrincipalId -eq 'sp-app-dormant').ActivityStatus | Should -Be 'NoValidCredential'
            ($all | Where-Object PrincipalId -eq 'sp-app-off').ActivityReason | Should -Be 'App registration deactivated'
            ($all | Where-Object PrincipalId -eq 'sp-mi').PrincipalType | Should -Be 'ManagedIdentity'
        }
        It 'keeps the disabled user with a lower score than the enabled one' {
            $bob = $all | Where-Object { $_.PrincipalId -eq 'u-bob' -and $_.RoleScope -eq 'Entra' }
            $bob.ActivityStatus | Should -Be 'Disabled'
            $bob.Severity | Should -Be 'Medium'
            ($all | Where-Object { $_.PrincipalId -eq 'u-alice' -and $_.RoleName -eq 'Global Administrator' }).Severity | Should -Be 'Critical'
        }
        It 'protects PIM eligibility, break-glass and the auditing identity' {
            ($all | Where-Object PrincipalId -eq 'u-carol').AssignmentType | Should -Be 'Eligible'
            ($all | Where-Object PrincipalId -eq 'u-carol').ProtectedReason | Should -Match 'PIM'
            ($all | Where-Object PrincipalId -eq 'u-glass').ProtectedReason | Should -Be 'Break-glass account'
            ($all | Where-Object PrincipalId -eq 'u-me').ProtectedReason | Should -Be 'Identity running this audit'
            @($all | Where-Object Protected).Count | Should -Be 6
        }
        It 'types a PIM activation as Activated and protects it' {
            $dave = $all | Where-Object PrincipalId -eq 'u-dave'
            $dave.AssignmentType | Should -Be 'Activated'
            $dave.Severity | Should -Be 'Critical'
            $dave.ProtectedReason | Should -Match 'PIM activation'
            $dave.CleanupPrimary | Should -Match 'Deactivate'
            ($all | Where-Object { $_.PrincipalId -eq 'u-alice' -and $_.RoleName -eq 'Global Administrator' }).AssignmentType | Should -Be 'Permanent'
        }
        It 'carries the assignment id Remove- needs' {
            ($all | Where-Object { $_.PrincipalId -eq 'u-alice' -and $_.RoleName -eq 'Global Administrator' }).AssignmentId | Should -Be 'ra-1'
            ($all | Where-Object { $_.PrincipalId -eq 'u-alice' -and $_.RoleName -eq 'Owner' -and -not $_.ViaGroupId }).AssignmentId | Should -Match 'ra-az-owner$'
        }
        It 'restores the original Az subscription context' {
            Should -Invoke -ModuleName RiskyRolesAnalyzer Set-AzContext -ParameterFilter { $SubscriptionId -eq 'sub-1' } -Times 2 -Exactly -Scope Context
        }
        It 'filters on MinimumSeverity' {
            $high = @(Get-RiskyRoleAssignment -MinimumSeverity High -WarningAction SilentlyContinue)
            $high.Count | Should -BeGreaterThan 0
            $high.RiskScore | ForEach-Object { $_ | Should -BeGreaterOrEqual 7.0 }
        }
        It 'honours -SkipAzure without touching Az' {
            $entra = @(Get-RiskyRoleAssignment -SkipAzure -WarningAction SilentlyContinue)
            @($entra | Where-Object RoleScope -eq 'Azure').Count | Should -Be 0
            $entra.Count | Should -Be 9
            Should -Invoke -ModuleName RiskyRolesAnalyzer Get-AzSubscription -Times 0 -Exactly -Scope It
        }
        It 'honours -SkipEntra and -SkipPim' {
            @(Get-RiskyRoleAssignment -SkipEntra -WarningAction SilentlyContinue).Count | Should -Be 7
            @(Get-RiskyRoleAssignment -SkipAzure -SkipPim | Where-Object AssignmentType -in 'Eligible', 'Activated').Count | Should -Be 0
        }
        It 'limits Azure to the named subscription' {
            $prod = @(Get-RiskyRoleAssignment -SkipEntra -SubscriptionId 'SUB-1' -WarningAction SilentlyContinue)
            @($prod | Where-Object { $_.AssignmentId -like '*ra-az-owner' }).Count | Should -Be 0
            $prod.Count | Should -Be 6
        }
        It 'treats additional roles as privileged' {
            @(Get-RiskyRoleAssignment -SkipEntra -AdditionalAzureRole 'Reader' -WarningAction SilentlyContinue | Where-Object RoleName -eq 'Reader').Count | Should -Be 1
            @(Get-RiskyRoleAssignment -SkipAzure -AdditionalEntraRole 'Directory Readers' | Where-Object RoleName -eq 'Directory Readers').Count | Should -Be 1
        }
        It 'warns and continues when PIM is not available' {
            $script:FailEligibility = $true
            $result = @(Get-RiskyRoleAssignment -SkipAzure -WarningVariable warnings -WarningAction SilentlyContinue)
            @($result | Where-Object AssignmentType -in 'Eligible', 'Activated').Count | Should -Be 0
            $result.Count | Should -Be 8
            @($warnings | Where-Object { $_ -match 'PIM eligible assignments skipped' }).Count | Should -Be 1
        }
        It 'warns about accounts that look like break-glass and are not protected' {
            $null = Get-RiskyRoleAssignment -SkipAzure -WarningVariable warnings -WarningAction SilentlyContinue
            @($warnings | Where-Object { $_ -match 'emergency access accounts.*Break Glass' }).Count | Should -Be 1
            $null = Get-RiskyRoleAssignment -SkipAzure -BreakGlassAccount 'breakglass@contoso.com' -WarningVariable quiet -WarningAction SilentlyContinue
            @($quiet | Where-Object { $_ -match 'emergency access' }).Count | Should -Be 0
        }
        It 'refuses to run with both sources skipped' {
            { Get-RiskyRoleAssignment -SkipAzure -SkipEntra } | Should -Throw '*Nothing to audit*'
        }
    }

    Context 'Get-RiskyRoleAssignment session checks' {
        It 'demands a Graph session' {
            Mock -ModuleName RiskyRolesAnalyzer Get-MgContext { $null }
            { Get-RiskyRoleAssignment } | Should -Throw '*Connect-RiskyRolesAnalyzer*'
        }
        It 'demands an Az session unless Azure is skipped' {
            Mock -ModuleName RiskyRolesAnalyzer Get-AzContext { $null }
            { Get-RiskyRoleAssignment } | Should -Throw '*-SkipAzure*'
        }
        It 'refuses mismatched tenants' {
            Mock -ModuleName RiskyRolesAnalyzer Get-AzContext { [pscustomobject]@{ Account = @{ Id = 'x' }; Tenant = @{ Id = 'tenant-2' }; Subscription = @{ Id = 'sub-9' } } }
            { Get-RiskyRoleAssignment } | Should -Throw '*tenant-2*'
        }
    }

    Context 'Connect-RiskyRolesAnalyzer' {
        BeforeAll {
            Mock -ModuleName RiskyRolesAnalyzer Connect-MgGraph { $null }
            Mock -ModuleName RiskyRolesAnalyzer Connect-AzAccount { $null }
        }
        It 'reuses sessions that already fit' {
            $result = Connect-RiskyRolesAnalyzer
            $result.TenantId | Should -Be 'tenant-1'
            $result.WriteScope | Should -BeFalse
            Should -Invoke -ModuleName RiskyRolesAnalyzer Connect-MgGraph -Times 0 -Exactly -Scope It
            Should -Invoke -ModuleName RiskyRolesAnalyzer Connect-AzAccount -Times 0 -Exactly -Scope It
        }
        It 'requests the write scope only when asked' {
            $null = Connect-RiskyRolesAnalyzer -RequestWriteScopes
            Should -Invoke -ModuleName RiskyRolesAnalyzer Connect-MgGraph -Times 1 -Exactly -Scope It -ParameterFilter { 'RoleManagement.ReadWrite.Directory' -in $Scopes -and 'Directory.Read.All' -in $Scopes }
        }
        It 'reconnects Azure when the tenant differs and skips it on request' {
            Mock -ModuleName RiskyRolesAnalyzer Get-AzContext { [pscustomobject]@{ Account = @{ Id = 'x' }; Tenant = @{ Id = 'tenant-2' }; Subscription = @{ Id = 'sub-9' } } }
            $null = Connect-RiskyRolesAnalyzer
            Should -Invoke -ModuleName RiskyRolesAnalyzer Connect-AzAccount -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'tenant-1' }
            $null = Connect-RiskyRolesAnalyzer -SkipAzure
            Should -Invoke -ModuleName RiskyRolesAnalyzer Connect-AzAccount -Times 1 -Exactly -Scope It
        }
    }
}

Describe 'ConvertTo-RiskyRoleReportHtml' {
    BeforeAll {
        $Render = & $module { Get-Command ConvertTo-RiskyRoleReportHtml }
        $sample = @(
            (New-Finding @{ Source = @{ marker = 'RAW-SOURCE-MUST-NOT-LEAK' } }),
            (New-Finding @{ RoleScope = 'Entra'; RoleName = 'Global Administrator'; RoleDefinitionId = 'rd-ga'; Scope = '/'; AssignmentType = 'Eligible'; AssignmentId = 're-1'; Principal = (New-Principal @{ ObjectId = 'p-2'; DisplayName = 'Carol </script><b>x' }) })
        )
    }

    It 'is one self-contained page with the findings embedded as JSON' {
        $html = & $Render -InputObject $sample -TenantId 'tenant-1' -Title 'Contoso audit' -GeneratedAt ([datetime]'2026-09-06T10:00:00')
        $html | Should -Match '^<!DOCTYPE html>'
        $html | Should -Match '<title>Contoso audit</title>'
        $html | Should -Match '"tenantId":"tenant-1"'
        $html | Should -Match '"generated":"2026-09-06 10:00:00"'
        $html | Should -Match '"count":2'
        $html | Should -Match ('"Id":"{0}"' -f $sample[0].Id)
        $html | Should -Not -Match '__DATA__|__META__|__TITLE__'
        $html | Should -Not -Match 'https?://(?!simonvedder\.com)'   # no external resources
    }
    It 'leaves the raw Source objects out and escapes closing tags inside the data' {
        $html = & $Render -InputObject $sample -TenantId 't'
        $html | Should -Not -Match 'RAW-SOURCE-MUST-NOT-LEAK'
        $html | Should -Not -Match 'Carol </script>'
        $html | Should -Match 'Carol <\\/script>'
    }
    It 'renders an empty report for no findings' {
        $html = & $Render -InputObject @() -TenantId ''
        $html | Should -Match 'const DATA = \[\];'
        $html | Should -Match '"count":0'
    }
    It 'keeps risky actions as an array and the protected flag as a boolean' {
        $custom = New-Finding @{ IsCustomRole = $true; RiskyAction = @('Microsoft.Authorization/roleAssignments/write', 'Microsoft.Authorization/elevateAccess/action') }
        $html = & $Render -InputObject @($custom) -TenantId 't'
        $html | Should -Match '"RiskyActions":\["Microsoft.Authorization/roleAssignments/write","Microsoft.Authorization/elevateAccess/action"\]'
        $html | Should -Match '"Protected":false'
    }
}

Describe 'Export-RiskyRoleReport' {
    BeforeAll {
        Mock -ModuleName RiskyRolesAnalyzer Get-MgContext { [pscustomobject]@{ TenantId = 'tenant-1'; Account = 'me@contoso.com'; Scopes = @() } }
        Mock -ModuleName RiskyRolesAnalyzer Invoke-MgGraphRequest { Invoke-FixtureGraph -Method $Method -Uri $Uri }
    }
    BeforeEach {
        $reportPath = Join-Path $TestDrive 'report.html'
        Remove-Item -Path $reportPath -Force -ErrorAction SilentlyContinue
    }

    It 'writes the file and returns it' {
        $file = New-Finding | Export-RiskyRoleReport -Path $reportPath
        $file | Should -BeOfType System.IO.FileInfo
        $file.Length | Should -BeGreaterThan 10000
        $content = Get-Content $reportPath -Raw
        $content | Should -Match '"tenantId":"tenant-1"'
        $content | Should -Match '"tenantName":"Contoso"'
    }
    It 'survives a tenant whose organisation is not readable' {
        Mock -ModuleName RiskyRolesAnalyzer Invoke-MgGraphRequest { throw '403 Forbidden' }
        $null = New-Finding | Export-RiskyRoleReport -Path $reportPath
        Get-Content $reportPath -Raw | Should -Match '"tenantName":""'
    }
    It 'writes nothing under -WhatIf' {
        $result = New-Finding | Export-RiskyRoleReport -Path $reportPath -WhatIf
        $result | Should -BeNullOrEmpty
        Test-Path $reportPath | Should -BeFalse
    }
    It 'takes an explicit tenant and title' {
        $null = @((New-Finding), (New-Finding @{ Principal = (New-Principal @{ ObjectId = 'p-9'; DisplayName = 'Nine' }) })) | Export-RiskyRoleReport -Path $reportPath -TenantId 'custom-tenant' -TenantName 'Custom' -Title 'My & audit'
        $content = Get-Content $reportPath -Raw
        $content | Should -Match '"tenantId":"custom-tenant"'
        $content | Should -Match '"tenantName":"Custom"'
        $content | Should -Match '<title>My &amp; audit</title>'
        $content | Should -Match '"count":2'
    }
    It 'rejects objects that did not come from Get-RiskyRoleAssignment' {
        { [pscustomobject]@{ Name = 'raw' } | Export-RiskyRoleReport -Path $reportPath -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Show-RiskyRoleAssignment' {
    It 'returns the original findings for the rows picked in the grid' {
        Mock -ModuleName RiskyRolesAnalyzer Get-RiskyRoleGridCommand { Get-Command Select-FirstTwo }
        $findings = @(
            (New-Finding),
            (New-Finding @{ Principal = (New-Principal @{ ObjectId = 'p-2'; DisplayName = 'Two' }) }),
            (New-Finding @{ Principal = (New-Principal @{ ObjectId = 'p-3'; DisplayName = 'Three' }) })
        )
        $picked = @($findings | Show-RiskyRoleAssignment)
        $picked.Count | Should -Be 2
        $picked[0].PSObject.TypeNames[0] | Should -Be 'RiskyRolesAnalyzer.RiskyRoleAssignment'
        $picked[1].PrincipalName | Should -Be 'Two'
        $picked[0].CleanupPrimary | Should -Not -BeNullOrEmpty -Because 'the original object comes back, not the projection'
    }
    It 'explains what to install when no grid exists' {
        Mock -ModuleName RiskyRolesAnalyzer Get-RiskyRoleGridCommand { $null }
        { New-Finding | Show-RiskyRoleAssignment } | Should -Throw '*ConsoleGuiTools*'
    }
    It 'returns nothing for no input' {
        @($null | Show-RiskyRoleAssignment -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
    It 'hands the grid the decision columns, not the whole finding' {
        Mock -ModuleName RiskyRolesAnalyzer Get-RiskyRoleGridCommand { Get-Command Select-NothingAndRecord }
        $null = @((New-Finding), (New-Finding @{ Principal = (New-Principal @{ ObjectId = 'p-2' }) })) | Show-RiskyRoleAssignment
        $script:GridRows.Count | Should -Be 2 -Because 'every finding reaches the grid, protected ones included'
        $columns = @($script:GridRows[0].PSObject.Properties.Name)
        $columns | Should -Contain 'RiskScore'
        $columns | Should -Contain 'Protected'
        $columns | Should -Contain 'ScopeDetail'
        $columns | Should -Not -Contain 'Source' -Because 'the raw API object has no place in a picker'
        $columns | Should -Not -Contain 'CleanupPrimary'
    }
    It 'passes the title through and asks the grid for a multiple selection' {
        Mock -ModuleName RiskyRolesAnalyzer Get-RiskyRoleGridCommand { Get-Command Select-NothingAndRecord }
        $null = New-Finding | Show-RiskyRoleAssignment -Title 'Contoso: pick the ones to remove'
        $script:GridTitle | Should -Be 'Contoso: pick the ones to remove'
        $script:GridMode | Should -Be 'Multiple'
    }
    It 'returns nothing when the grid is closed without a selection' {
        Mock -ModuleName RiskyRolesAnalyzer Get-RiskyRoleGridCommand { Get-Command Select-NothingAndRecord }
        $picked = @(@((New-Finding), (New-Finding @{ Principal = (New-Principal @{ ObjectId = 'p-2' }) })) | Show-RiskyRoleAssignment)
        $picked.Count | Should -Be 0 -Because 'an empty selection must not fall back to everything'
    }
}

Describe 'Restore-RiskyRoleAssignment' {
    BeforeAll {
        Mock -ModuleName RiskyRolesAnalyzer Invoke-MgGraphRequest { Invoke-FixtureGraph -Method $Method -Uri $Uri }
        Mock -ModuleName RiskyRolesAnalyzer Remove-AzRoleAssignment { $null }
        Mock -ModuleName RiskyRolesAnalyzer New-AzRoleAssignment { $null }
        $script:WriteScope = $false
        Mock -ModuleName RiskyRolesAnalyzer Get-MgContext {
            $scopes = @('RoleManagement.Read.Directory', 'Directory.Read.All', 'Group.Read.All', 'Application.Read.All')
            if ($script:WriteScope) { $scopes += 'RoleManagement.ReadWrite.Directory' }
            [pscustomobject]@{ TenantId = 'tenant-1'; Account = 'me@contoso.com'; Scopes = $scopes }
        }
    }
    BeforeEach {
        $backupPath = Join-Path $TestDrive 'restore-backup.json'
        Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
        $script:GraphCalls.Clear()
        $script:WriteScope = $true
    }

    It 'restores what Remove- backed up, from the file' {
        $azure = New-Finding
        $entra = New-Finding @{ RoleScope = 'Entra'; RoleName = 'Global Administrator'; RoleDefinitionId = 'rd-ga'; Scope = '/'; AssignmentId = 'ra-1'; Principal = (New-Principal @{ ObjectId = 'p-2'; DisplayName = 'Two' }) }
        $null = @($azure, $entra) | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false
        $result = @(Restore-RiskyRoleAssignment -Path $backupPath -Confirm:$false)
        $result.Count | Should -Be 2
        $result.Result | Should -Be @('Restored', 'Restored')
        $result[0].PSObject.TypeNames[0] | Should -Be 'RiskyRolesAnalyzer.RiskyRoleAssignmentRestore'
        Should -Invoke -ModuleName RiskyRolesAnalyzer New-AzRoleAssignment -Times 1 -Exactly -Scope It -ParameterFilter {
            $ObjectId -eq 'p-1' -and $RoleDefinitionId -eq '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -and $Scope -eq '/subscriptions/00000000-0000-0000-0000-000000000001'
        }
        $post = @($script:GraphCalls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/roleManagement/directory/roleAssignments' })
        $post.Count | Should -Be 1
    }
    It 'does nothing under -WhatIf' {
        New-Finding | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false | Out-Null
        $result = Restore-RiskyRoleAssignment -Path $backupPath -WhatIf
        $result.Result | Should -Be 'Skipped'
        Should -Invoke -ModuleName RiskyRolesAnalyzer New-AzRoleAssignment -Times 0 -Exactly -Scope It
    }
    It 'skips PIM, group-inherited and incomplete entries' {
        $entries = @(
            [pscustomobject]@{ Id = 'a'; RoleScope = 'Entra'; RoleName = 'GA'; RoleDefinitionId = 'rd-ga'; Scope = '/'; PrincipalId = 'p'; PrincipalName = 'P'; AssignmentType = 'Eligible'; ViaGroupId = $null; ScopeDetail = 'Tenant-wide' }
            [pscustomobject]@{ Id = 'b'; RoleScope = 'Azure'; RoleName = 'Owner'; RoleDefinitionId = 'x'; Scope = '/subscriptions/s'; PrincipalId = 'p'; PrincipalName = 'P'; AssignmentType = 'Permanent'; ViaGroupId = 'g'; ScopeDetail = 'Subscription' }
            [pscustomobject]@{ Id = 'c'; RoleScope = 'Azure'; RoleName = 'Owner'; RoleDefinitionId = ''; Scope = '/subscriptions/s'; PrincipalId = 'p'; PrincipalName = 'P'; AssignmentType = 'Permanent'; ViaGroupId = $null; ScopeDetail = 'Subscription' }
            [pscustomobject]@{ Id = 'd'; RoleScope = 'Entra'; RoleName = 'GA'; RoleDefinitionId = 'rd-ga'; Scope = '/'; PrincipalId = 'p'; PrincipalName = 'P'; AssignmentType = 'Activated'; ViaGroupId = $null; ScopeDetail = 'Tenant-wide' }
        )
        $result = @($entries | Restore-RiskyRoleAssignment -Confirm:$false)
        $result.Result | Should -Be @('Skipped', 'Skipped', 'Skipped', 'Skipped')
        $result[0].Reason | Should -Match 'PIM'
        $result[1].Reason | Should -Match 'group'
        $result[2].Reason | Should -Match 'lacks'
        Should -Invoke -ModuleName RiskyRolesAnalyzer New-AzRoleAssignment -Times 0 -Exactly -Scope It
    }
    It 'refuses an Entra restore without the write scope' {
        $script:WriteScope = $false
        $entry = [pscustomobject]@{ Id = 'a'; RoleScope = 'Entra'; RoleName = 'GA'; RoleDefinitionId = 'rd-ga'; Scope = '/'; PrincipalId = 'p'; PrincipalName = 'P'; AssignmentType = 'Permanent'; ViaGroupId = $null; ScopeDetail = 'Tenant-wide' }
        { $entry | Restore-RiskyRoleAssignment -Confirm:$false } | Should -Throw '*RequestWriteScopes*'
        @($script:GraphCalls | Where-Object Method -eq 'POST').Count | Should -Be 0
    }
    It 'reports a failed call' {
        Mock -ModuleName RiskyRolesAnalyzer New-AzRoleAssignment { throw 'RoleAssignmentExists' }
        $result = New-Finding | Select-Object -Property * -ExcludeProperty Source | Restore-RiskyRoleAssignment -Confirm:$false -ErrorAction SilentlyContinue
        $result.Result | Should -Be 'Failed'
        $result.Reason | Should -Match 'RoleAssignmentExists'
    }
}

Describe 'Remove-RiskyRoleAssignment' {
    BeforeAll {
        Mock -ModuleName RiskyRolesAnalyzer Invoke-MgGraphRequest { Invoke-FixtureGraph -Method $Method -Uri $Uri }
        Mock -ModuleName RiskyRolesAnalyzer Remove-AzRoleAssignment { $null }
        $script:WriteScope = $false
        Mock -ModuleName RiskyRolesAnalyzer Get-MgContext {
            $scopes = @('RoleManagement.Read.Directory', 'Directory.Read.All', 'Group.Read.All', 'Application.Read.All')
            if ($script:WriteScope) { $scopes += 'RoleManagement.ReadWrite.Directory' }
            [pscustomobject]@{ TenantId = 'tenant-1'; Account = 'me@contoso.com'; Scopes = $scopes }
        }
    }

    BeforeEach {
        $backupPath = Join-Path $TestDrive 'backup.json'
        Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
        $script:GraphCalls.Clear()
        $script:WriteScope = $false
    }

    It 'does nothing under -WhatIf and writes no backup' {
        $result = New-Finding | Remove-RiskyRoleAssignment -BackupPath $backupPath -WhatIf
        $result.Result | Should -Be 'Skipped'
        Test-Path $backupPath | Should -BeFalse
        Should -Invoke -ModuleName RiskyRolesAnalyzer Remove-AzRoleAssignment -Times 0 -Exactly -Scope It
    }

    It 'removes an Azure assignment by principal, role definition and scope, after the backup' {
        $finding = New-Finding
        $result = $finding | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false
        $result.Result | Should -Be 'Removed'
        $result.PSObject.TypeNames[0] | Should -Be 'RiskyRolesAnalyzer.RiskyRoleAssignmentRemoval'
        Should -Invoke -ModuleName RiskyRolesAnalyzer Remove-AzRoleAssignment -Times 1 -Exactly -Scope It -ParameterFilter {
            $ObjectId -eq 'p-1' -and $RoleDefinitionId -eq '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -and $Scope -eq '/subscriptions/00000000-0000-0000-0000-000000000001'
        }
        $backup = @(Get-Content $backupPath -Raw | ConvertFrom-Json)
        $backup[0].Id | Should -Be $finding.Id
        $backup[0].AssignmentId | Should -Be $finding.AssignmentId
    }

    It 'removes an Entra assignment through Graph when the write scope is present' {
        $script:WriteScope = $true
        $finding = New-Finding @{ RoleScope = 'Entra'; RoleName = 'Global Administrator'; RoleDefinitionId = 'rd-ga'; Scope = '/'; AssignmentId = 'ra-1' }
        $result = $finding | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false
        $result.Result | Should -Be 'Removed'
        @($script:GraphCalls | Where-Object { $_.Method -eq 'DELETE' -and $_.Uri -like '*/roleAssignments/ra-1' }).Count | Should -Be 1
    }

    It 'refuses an Entra removal without the write scope and removes nothing' {
        $finding = New-Finding @{ RoleScope = 'Entra'; RoleName = 'Global Administrator'; RoleDefinitionId = 'rd-ga'; Scope = '/'; AssignmentId = 'ra-1' }
        { $finding | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false } | Should -Throw '*RequestWriteScopes*'
        @($script:GraphCalls | Where-Object Method -eq 'DELETE').Count | Should -Be 0
        Test-Path $backupPath | Should -BeFalse
    }

    It 'never touches protected objects' {
        $result = New-Finding @{ ViaGroup = 'Cloud Admins'; ViaGroupId = 'g-admins' } | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false -WarningAction SilentlyContinue
        $result.Result | Should -Be 'Skipped'
        $result.Reason | Should -Match 'Cloud Admins'
        Test-Path $backupPath | Should -BeFalse
        Should -Invoke -ModuleName RiskyRolesAnalyzer Remove-AzRoleAssignment -Times 0 -Exactly -Scope It
    }

    It 'reports a failed call instead of stopping the pipeline' {
        Mock -ModuleName RiskyRolesAnalyzer Remove-AzRoleAssignment { throw 'AuthorizationFailed' }
        $result = @((New-Finding), (New-Finding @{ Principal = (New-Principal @{ ObjectId = 'p-2'; DisplayName = 'Second' }) }) | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false -ErrorAction SilentlyContinue)
        $result.Count | Should -Be 2
        $result.Result | Should -Be @('Failed', 'Failed')
        $result[0].Reason | Should -Match 'AuthorizationFailed'
        @(Get-Content $backupPath -Raw | ConvertFrom-Json).Count | Should -Be 2
    }

    It 'rejects objects that did not come from Get-RiskyRoleAssignment' {
        { [pscustomobject]@{ Name = 'raw' } | Remove-RiskyRoleAssignment -WhatIf -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Standalone audit script' {
    BeforeAll {
        $script:StandalonePath = Join-Path $PSScriptRoot '..' 'dist' 'Invoke-RiskyRolesAudit.ps1'
        $script:StandaloneText = if (Test-Path $script:StandalonePath) { Get-Content -Path $script:StandalonePath -Raw } else { '' }

        # Everything above the Main banner is definitions. Dot-sourcing that half proves the bundle
        # is complete and self-contained without a sign-in and without running the audit.
        if ($script:StandaloneText) {
            $marker = '#  Main'
            $cut = $script:StandaloneText.IndexOf($marker)
            $definitions = $script:StandaloneText.Substring(0, $cut)
            # Drop the param block; a dot-sourced file with [CmdletBinding()] would bind arguments.
            $definitions = $definitions -replace '(?s)^.*?Set-StrictMode -Version Latest', 'Set-StrictMode -Version Latest'
            $script:DefinitionsPath = Join-Path $TestDrive 'standalone-definitions.ps1'
            Set-Content -Path $script:DefinitionsPath -Value $definitions -Encoding utf8
        }
    }

    It 'is committed and current with the module sources' {
        Test-Path -Path $script:StandalonePath | Should -BeTrue -Because 'the script is what most people run'
        { & (Join-Path $PSScriptRoot '..' 'tools' 'Build-StandaloneScript.ps1') -Check } | Should -Not -Throw
    }

    It 'parses' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:StandalonePath, [ref]$null, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'carries the catalog and the report template inline, and reads nothing from disk' {
        $script:StandaloneText | Should -Match 'PrivilegedAzureRoles'
        $script:StandaloneText | Should -Match '__DATA__'
        $script:StandaloneText | Should -Not -Match "Join-Path \`$script:ModuleRoot" -Because 'there is no module folder to read from'
    }

    It 'defines every function the read path needs and none of the write path' {
        $definitions = [scriptblock]::Create((Get-Content -Path $script:DefinitionsPath -Raw))
        $sandbox = [powershell]::Create()
        try {
            $null = $sandbox.AddScript((Get-Content -Path $script:DefinitionsPath -Raw)).Invoke()
            $sandbox.Streams.Error.Count | Should -Be 0 -Because 'the definitions must load on their own'
            $names = @($sandbox.AddScript('Get-Command -CommandType Function | ForEach-Object Name').Invoke())
            foreach ($needed in 'Connect-RiskyRolesAnalyzer', 'Get-RiskyRoleAssignment', 'Export-RiskyRoleReport', 'Get-RiskyRoleScore', 'Resolve-RiskyRoleAssignmentFinding', 'Get-RiskyRoleReportTemplate') {
                $names | Should -Contain $needed
            }
            foreach ($excluded in 'Remove-RiskyRoleAssignment', 'Restore-RiskyRoleAssignment', 'Show-RiskyRoleAssignment') {
                $names | Should -Not -Contain $excluded -Because 'the write path belongs in the module, where input is typed and backed up'
            }
        }
        finally { $sandbox.Dispose() }
        $definitions | Should -Not -BeNullOrEmpty
    }

    It 'renders a report from the inlined template' {
        $sandbox = [powershell]::Create()
        try {
            $out = Join-Path $TestDrive 'standalone-report.html'
            $null = $sandbox.AddScript((Get-Content -Path $script:DefinitionsPath -Raw)).Invoke()
            $sandbox.Commands.Clear()
            $script = @"
`$p = [pscustomobject]@{ ObjectId = 'p1'; Type = 'User'; DisplayName = 'Alice Admin'; UPN = 'alice@contoso.com'; AppId = `$null; IsEnabled = `$true; ActivityStatus = 'Active'; ActivityReason = `$null }
`$f = Resolve-RiskyRoleAssignmentFinding -RoleScope Entra -RoleName 'Global Administrator' -RoleDefinitionId 'r1' -Scope '/' -ScopeName 'Tenant-wide' -AssignmentType Permanent -AssignmentId 'a1' -Principal `$p
ConvertTo-RiskyRoleReportHtml -InputObject @(`$f) -TenantId 't1' -TenantName 'Contoso' | Set-Content -Path '$out' -Encoding utf8 -NoNewline
"@
            $null = $sandbox.AddScript($script).Invoke()
            $sandbox.Streams.Error | ForEach-Object { $_.ToString() } | Should -Be @()
            $html = Get-Content -Path $out -Raw
            $html | Should -Match 'Alice Admin'
            $html | Should -Match 'const DATA = \['
            $html | Should -Not -Match '__(DATA|META|TITLE)__' -Because 'every placeholder must be filled'
        }
        finally { $sandbox.Dispose() }
    }
}
