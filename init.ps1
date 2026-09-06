<#
.SYNOPSIS
Turn this skeleton into a named tool repository.

.DESCRIPTION
Replaces every placeholder, renames the placeholder files and folders, removes the parts the
chosen construct does not need, swaps in the tool README and deletes itself. Run it once, right
after "Use this template" or a clone, from the repository root.

Constructs:
  Audit       runs on an administrator's machine with delegated sign-in; Get -> report -> optional
              Remove. No deploy/ folder, no runbook, no Bicep job in CI.
  Automation  runs inside the customer's tenant: Bicep deploys an Automation Account, identity,
              custom role and a thin runbook that imports the module from the PowerShell Gallery.

.PARAMETER ModuleName
PascalCase module name, also the Gallery package name. Convention: PascalCase of the repo name.

.PARAMETER RepoName
GitHub repository name under simon-vedder, kebab-case.

.PARAMETER Noun
Singular PascalCase noun for the cmdlets (Get-<Noun>, Remove-<Noun>).

.PARAMETER Description
One sentence for the manifest and the README.

.PARAMETER Tagline
Short bold line under the hero. Defaults to the description.

.PARAMETER Slug
Path on the central tools page, https://simonvedder.com/tools/<slug>. Defaults to the repo name.

.PARAMETER Construct
Audit or Automation.

.EXAMPLE
./init.ps1 -ModuleName RiskyRolesAnalyzer -RepoName risky-roles-analyzer -Noun RiskyRoleAssignment `
    -Description 'Finds privileged Azure RBAC and Entra role assignments that posture tools miss.' -Construct Audit
#>
[CmdletBinding(SupportsShouldProcess)]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive one-shot script; the summary is for the person running it.')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Z][A-Za-z0-9]+$')]
    [string]$ModuleName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$RepoName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Z][A-Za-z0-9]+$')]
    [string]$Noun,

    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter()]
    [string]$Tagline,

    [Parameter()]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Slug,

    [Parameter()]
    [ValidateSet('Audit', 'Automation')]
    [string]$Construct = 'Audit'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not (Test-Path (Join-Path $root '.skeleton'))) { throw 'Run init.ps1 from the skeleton root; .skeleton/ is missing.' }
if (-not $Tagline) { $Tagline = $Description }
if (-not $Slug) { $Slug = $RepoName }

if (-not $PSCmdlet.ShouldProcess($root, "Instantiate $ModuleName ($Construct) from the skeleton")) { return }

$placeholders = [ordered]@{
    '__ModuleName__'  = $ModuleName
    '__RepoName__'    = $RepoName
    '__Noun__'        = $Noun
    '__Description__' = $Description
    '__Tagline__'     = $Tagline
    '__Slug__'        = $Slug
    '__Year__'        = (Get-Date).Year.ToString()
    '00000000-0000-4000-8000-000000000000' = [guid]::NewGuid().ToString()
}

$binary = '.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip'
$skip = @('.git', 'init.ps1')

function Get-TextFile {
    Get-ChildItem -Path $root -Recurse -File -Force |
        Where-Object { $_.Extension -notin $binary -and $_.Name -notin $skip -and $_.FullName -notmatch '[\\/]\.git[\\/]' }
}

# 1. Construct: drop what Audit does not need, then resolve the automation-only markers.
if ($Construct -eq 'Audit') {
    foreach ($path in 'deploy', (Join-Path 'src' 'runbooks')) {
        $full = Join-Path $root $path
        if (Test-Path $full) { Remove-Item -Path $full -Recurse -Force; Write-Verbose "Removed $path" }
    }
}

foreach ($file in Get-TextFile) {
    $lines = Get-Content -Path $file.FullName
    if (-not ($lines -match 'automation-only')) { continue }
    $out = [System.Collections.Generic.List[string]]::new()
    $inBlock = $false
    foreach ($line in $lines) {
        $isStart = $line -match '^\s*(#>>>|<!--)\s*automation-only'
        $isEnd = $line -match '^\s*(#<<<|<!--\s*/)\s*automation-only'
        if ($isStart) { $inBlock = $true; continue }
        if ($isEnd) { $inBlock = $false; continue }
        if ($inBlock -and $Construct -eq 'Audit') { continue }
        $out.Add($line)
    }
    Set-Content -Path $file.FullName -Value $out -Encoding utf8
}

# 2. Placeholders in file contents.
foreach ($file in Get-TextFile) {
    $content = Get-Content -Path $file.FullName -Raw
    $updated = $content
    foreach ($key in $placeholders.Keys) { $updated = $updated.Replace($key, $placeholders[$key]) }
    if ($updated -ne $content) { Set-Content -Path $file.FullName -Value $updated -Encoding utf8 -NoNewline }
}

# 3. Placeholders in file and folder names, deepest first so parents rename after children.
$renameKeys = @('__ModuleName__', '__Noun__')
Get-ChildItem -Path $root -Recurse -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    Where-Object { $name = $_.Name; @($renameKeys | Where-Object { $name.Contains($_) }).Count -gt 0 } |
    Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object {
        $newName = $_.Name
        foreach ($key in $renameKeys) { $newName = $newName.Replace($key, $placeholders[$key]) }
        if ($newName -ne $_.Name) { Rename-Item -Path $_.FullName -NewName $newName }
    }

# 4. The tool README replaces the skeleton README; the skeleton folder goes.
Move-Item -Path (Join-Path $root '.skeleton' 'README.tool.md') -Destination (Join-Path $root 'README.md') -Force
Remove-Item -Path (Join-Path $root '.skeleton') -Recurse -Force

# 5. This script has done its job.
Remove-Item -Path (Join-Path $root 'init.ps1') -Force

Write-Host ''
Write-Host "$ModuleName ($Construct) is ready." -ForegroundColor Green
Write-Host @"

Next:
  1. git checkout -b feat/module-skeleton && git add -A && git commit -m "Instantiate $ModuleName from the skeleton"
  2. Replace the example functions in src/$ModuleName/Public and Private with the real ones.
  3. Fill RequiredModules in src/$ModuleName/$ModuleName.psd1 and the Permissions section of README.md.
  4. Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 ; Invoke-Pester ./tests
  5. Render docs/images/hero.png and social-preview.png (recipe in docs/images/README.md).
$(if ($Construct -eq 'Automation') { "  6. Adjust deploy/main.bicep (role actions, schedule) and rebuild deploy/azuredeploy.json with Bicep 0.46.1." })
  Repository secret PSGALLERY_API_KEY (scoped to $ModuleName, one year), then tag v0.1.0 to publish.
"@
