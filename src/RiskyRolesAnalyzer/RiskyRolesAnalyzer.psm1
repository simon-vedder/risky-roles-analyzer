Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot

# Everything a user can see or depend on (type names, tag names, state values) is declared here,
# once. Changing one is a breaking change and goes through the CHANGELOG.
$script:TypeName = @{
    Finding = 'RiskyRolesAnalyzer.RiskyRoleAssignment'
    Removal = 'RiskyRolesAnalyzer.RiskyRoleAssignmentRemoval'
}

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName
)
