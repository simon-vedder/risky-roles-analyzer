#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $manifestPath = Join-Path $PSScriptRoot '..' 'src' 'RiskyRolesAnalyzer' 'RiskyRolesAnalyzer.psd1'
    Import-Module $manifestPath -Force -ErrorAction Stop
    $module = Get-Module RiskyRolesAnalyzer

    # Private functions are fetched from the module scope once. Invoking the FunctionInfo runs the
    # body inside the module, so $script: variables resolve as they do in production.
    $Private = & $module {
        @{
            Resolve  = Get-Command Resolve-RiskyRoleAssignmentFinding
            Property = Get-Command Get-PropertyOrDefault
        }
    }

    function New-Raw {
        param([hashtable]$Override = @{})
        $raw = @{ Name = 'item-01'; IsPrivileged = $false; IsActive = $true; Protected = $false }
        foreach ($key in $Override.Keys) { $raw[$key] = $Override[$key] }
        [pscustomobject]$raw
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
        $files = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'src') -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'
        foreach ($file in $files) {
            (Get-Content -Path $file.FullName -Raw) | Should -Not -Match '[\x00-\x08\x0b\x0c\x0e-\x1f]' -Because "$($file.Name) must not carry stray control characters"
        }
    }
}

Describe 'Get-PropertyOrDefault' {
    It 'reads from a hashtable' { (& $Private.Property @{ A = 1 } 'A') | Should -Be 1 }
    It 'reads from an object' { (& $Private.Property ([pscustomobject]@{ A = 2 }) 'A') | Should -Be 2 }
    It 'falls back when the key is missing' { (& $Private.Property @{} 'A' -Default 'x') | Should -Be 'x' }
    It 'falls back on null input' { (& $Private.Property $null 'A' -Default 'x') | Should -Be 'x' }
}

Describe 'Resolve-RiskyRoleAssignmentFinding' {
    It 'rates privileged and unused as High' {
        $finding = & $Private.Resolve (New-Raw @{ IsPrivileged = $true; IsActive = $false })
        $finding.Severity | Should -Be 'High'
        $finding.PSObject.TypeNames[0] | Should -Be 'RiskyRolesAnalyzer.RiskyRoleAssignment'
    }
    It 'rates privileged and active as Medium' { (& $Private.Resolve (New-Raw @{ IsPrivileged = $true })).Severity | Should -Be 'Medium' }
    It 'rates everything else as Info' { (& $Private.Resolve (New-Raw)).Severity | Should -Be 'Info' }
    It 'accepts hashtables' { (& $Private.Resolve @{ Name = 'h'; IsPrivileged = $true }).Name | Should -Be 'h' }
    It 'carries the Protected flag through' { (& $Private.Resolve (New-Raw @{ Protected = $true })).Protected | Should -BeTrue }
}

Describe 'Get-RiskyRoleAssignment' {
    It 'takes pipeline input and returns typed findings' {
        $result = @((New-Raw), (New-Raw @{ Name = 'item-02'; IsPrivileged = $true }) | Get-RiskyRoleAssignment)
        $result.Count | Should -Be 2
        $result[1].Severity | Should -Be 'Medium'
    }
    It 'filters on MinimumSeverity' {
        $result = @((New-Raw), (New-Raw @{ IsPrivileged = $true; IsActive = $false }) | Get-RiskyRoleAssignment -MinimumSeverity High)
        $result.Count | Should -Be 1
        $result[0].Severity | Should -Be 'High'
    }
    It 'ignores null input' { @($null | Get-RiskyRoleAssignment).Count | Should -Be 0 }
}

Describe 'Remove-RiskyRoleAssignment' {
    BeforeEach {
        $backupPath = Join-Path $TestDrive 'backup.json'
        Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
    }

    It 'does nothing under -WhatIf and writes no backup' {
        $result = New-Raw @{ IsPrivileged = $true } | Get-RiskyRoleAssignment | Remove-RiskyRoleAssignment -BackupPath $backupPath -WhatIf
        $result.Result | Should -Be 'Skipped'
        Test-Path $backupPath | Should -BeFalse
    }

    It 'writes the backup before acting' {
        $result = New-Raw @{ Name = 'gone' ; IsPrivileged = $true } | Get-RiskyRoleAssignment | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false
        $result.Result | Should -Be 'Removed'
        @(Get-Content $backupPath -Raw | ConvertFrom-Json)[0].Name | Should -Be 'gone'
    }

    It 'never touches protected objects' {
        $result = New-Raw @{ Protected = $true; IsPrivileged = $true } | Get-RiskyRoleAssignment | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false -WarningAction SilentlyContinue
        $result.Result | Should -Be 'Skipped'
        $result.Reason | Should -Be 'Protected'
        Test-Path $backupPath | Should -BeFalse
    }

    It 'rejects objects that did not come from Get-RiskyRoleAssignment' {
        { [pscustomobject]@{ Name = 'raw' } | Remove-RiskyRoleAssignment -WhatIf -ErrorAction Stop } | Should -Throw
    }
}
