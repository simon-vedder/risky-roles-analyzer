@{
    RootModule           = '__ModuleName__.psm1'
    ModuleVersion        = '0.1.0'
    CompatiblePSEditions = @('Core')
    GUID                 = '00000000-0000-4000-8000-000000000000'
    Author               = 'Simon Vedder'
    CompanyName          = 'Simon Vedder'
    Copyright            = '(c) __Year__ Simon Vedder. MIT License.'
    Description          = '__Description__'
    PowerShellVersion    = '7.2'
    # Audit tools: Microsoft.Graph.Authentication and/or Az.Accounts + Az.Resources.
    # Automation tools: keep the minimums at the Az bundle the Azure Automation PowerShell 7.2
    # runtime ships (Az 11.2.0: Az.Accounts 2.15.0, Az.Compute 7.1.1, Az.Resources 6.13.0) and
    # import no Az modules into the Automation Account. A newer Az.Accounts next to the runtime's
    # bundle breaks assembly loading in the sandbox (observed 2026-09-05).
    RequiredModules      = @()
    FunctionsToExport    = @(
        'Get-__Noun__'
        'Remove-__Noun__'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/simon-vedder/__RepoName__/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/simon-vedder/__RepoName__'
            ReleaseNotes = 'https://github.com/simon-vedder/__RepoName__/blob/main/CHANGELOG.md'
            Prerelease   = 'preview'
        }
    }
}
