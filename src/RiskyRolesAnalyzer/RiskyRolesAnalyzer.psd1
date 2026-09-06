@{
    RootModule           = 'RiskyRolesAnalyzer.psm1'
    ModuleVersion        = '0.1.0'
    CompatiblePSEditions = @('Core')
    GUID                 = '51df0d0b-f26b-48db-a71b-758737e71dab'
    Author               = 'Simon Vedder'
    CompanyName          = 'Simon Vedder'
    Copyright            = '(c) 2026 Simon Vedder. MIT License.'
    Description          = 'Finds privileged Azure RBAC and Entra ID role assignments that posture tools miss, and lets you remove them safely.'
    PowerShellVersion    = '7.2'
    RequiredModules      = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }
        @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.15.0' }
    )
    FormatsToProcess     = @('RiskyRolesAnalyzer.Format.ps1xml')
    FunctionsToExport    = @(
        'Connect-RiskyRolesAnalyzer'
        'Export-RiskyRoleReport'
        'Get-RiskyRoleAssignment'
        'Remove-RiskyRoleAssignment'
        'Restore-RiskyRoleAssignment'
        'Show-RiskyRoleAssignment'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'Entra', 'EntraID', 'RBAC', 'PIM', 'Security', 'Audit', 'PrivilegedAccess', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/simon-vedder/risky-roles-analyzer/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/simon-vedder/risky-roles-analyzer'
            ReleaseNotes = 'https://github.com/simon-vedder/risky-roles-analyzer/blob/main/CHANGELOG.md'
            Prerelease   = 'preview'
        }
    }
}
