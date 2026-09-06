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
    # Audit tools: Microsoft.Graph.Authentication and/or Az.Accounts + Az.Resources.
    # Automation tools: keep the minimums at the Az bundle the Azure Automation PowerShell 7.2
    # runtime ships (Az 11.2.0: Az.Accounts 2.15.0, Az.Compute 7.1.1, Az.Resources 6.13.0) and
    # import no Az modules into the Automation Account. A newer Az.Accounts next to the runtime's
    # bundle breaks assembly loading in the sandbox (observed 2026-09-05).
    RequiredModules      = @()
    FunctionsToExport    = @(
        'Get-RiskyRoleAssignment'
        'Remove-RiskyRoleAssignment'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/simon-vedder/risky-roles-analyzer/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/simon-vedder/risky-roles-analyzer'
            ReleaseNotes = 'https://github.com/simon-vedder/risky-roles-analyzer/blob/main/CHANGELOG.md'
            Prerelease   = 'preview'
        }
    }
}
