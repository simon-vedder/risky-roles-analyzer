# Write-path test of Remove- and Restore-RiskyRoleAssignment on a real tenant, with a test user who
# holds nothing else. Everything this script creates, it removes again in `finally`.
#
#   Azure: throwaway resource group in the current subscription, Reader for the test user there.
#   Entra: Directory Readers (harmless built-in role) for the test user, tenant-wide.
#   Module: Get- with the two roles declared privileged, Remove -WhatIf, Remove, Restore, verify each step.
#
# Needs an interactive sign-in: Connect-RiskyRolesAnalyzer -RequestWriteScopes opens the browser.
param(
    # Display-name prefix of a test user who holds nothing else. Exactly one user must match.
    [Parameter(Mandatory)]
    [string]$UserNamePrefix,
    [string]$ResourceGroupName = 'rg-rra-writetest-weu',
    [string]$Location = 'westeurope'
)
$ErrorActionPreference = 'Stop'
$out = if ($env:RRA_TEST_OUT) { $env:RRA_TEST_OUT } else { [System.IO.Path]::GetTempPath() }
Import-Module (Join-Path $PSScriptRoot '..' '..' 'src' 'RiskyRolesAnalyzer' 'RiskyRolesAnalyzer.psd1') -Force

$readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'          # Azure built-in Reader
$directoryReadersId = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'     # Entra built-in Directory Readers
$steps = [System.Collections.Generic.List[string]]::new()
function Step([string]$Text) { $script:steps.Add($Text); "==> $Text" }

$session = Connect-RiskyRolesAnalyzer -RequestWriteScopes
if (-not $session.WriteScope) { throw 'Graph session has no write scope; the consent must have been declined.' }
$subscription = (Get-AzContext).Subscription
"Tenant $($session.TenantId) | Graph $($session.GraphAccount) | Azure $($session.AzureAccount) | subscription $($subscription.Name)"

# The test user: exactly one match, or stop before anything is created.
$users = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$filter=startswith(displayName,'$UserNamePrefix')&`$select=id,displayName,userPrincipalName").value)
if ($users.Count -ne 1) { throw "Expected exactly one user whose display name starts with '$UserNamePrefix', found $($users.Count): $(($users | ForEach-Object { $_.displayName }) -join ', ')" }
$user = $users[0]
"Test user: $($user.displayName) ($($user.userPrincipalName))"

$rgScope = "/subscriptions/$($subscription.Id)/resourceGroups/$ResourceGroupName"
$backupPath = Join-Path $out 'writetest-backup.json'
Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue

try {
    Step "Create $ResourceGroupName and give $($user.displayName) Reader there"
    $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{ purpose = 'RiskyRolesAnalyzer write-path test'; deleteAfter = (Get-Date).AddDays(1).ToString('yyyy-MM-dd') } -Force
    $null = New-AzRoleAssignment -ObjectId $user.id -RoleDefinitionId $readerRoleId -Scope $rgScope

    Step "Give $($user.displayName) Directory Readers tenant-wide"
    $null = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' -ContentType 'application/json' -Body @{
        '@odata.type' = '#microsoft.graph.unifiedRoleAssignment'; principalId = $user.id; roleDefinitionId = $directoryReadersId; directoryScopeId = '/'
    }
    Start-Sleep -Seconds 15

    Step 'Get-RiskyRoleAssignment with Reader and Directory Readers declared privileged'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $findings = @(Get-RiskyRoleAssignment -SubscriptionId $subscription.Id -AdditionalAzureRole Reader -AdditionalEntraRole 'Directory Readers' -WarningAction SilentlyContinue)
    $sw.Stop()
    $mine = @($findings | Where-Object PrincipalId -eq $user.id)
    "$($findings.Count) finding(s) in $([int]$sw.Elapsed.TotalSeconds) s, $($mine.Count) for $($user.displayName):"
    $mine | Format-Table Severity, RoleScope, RoleName, ScopeLevel, AssignmentType, Protected, AssignmentId | Out-String -Width 200
    if ($mine.Count -ne 2) { throw "Expected 2 findings for the test user (Azure Reader on the RG, Entra Directory Readers), got $($mine.Count)." }

    Step 'Remove -WhatIf'
    $whatIf = @($mine | Remove-RiskyRoleAssignment -BackupPath $backupPath -WhatIf)
    $whatIf | Format-Table Result, RoleScope, RoleName, Reason | Out-String -Width 200
    if (Test-Path $backupPath) { throw '-WhatIf wrote a backup file.' }

    Step 'Remove -Confirm:$false'
    $removed = @($mine | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false)
    $removed | Format-Table Result, RoleScope, RoleName, Reason | Out-String -Width 200
    if (@($removed | Where-Object Result -ne 'Removed').Count) { throw 'Not every assignment was removed.' }
    Start-Sleep -Seconds 10

    Step 'Verify both assignments are gone'
    $azureLeft = @(Get-AzRoleAssignment -ObjectId $user.id -Scope $rgScope -RoleDefinitionId $readerRoleId).Count
    $entraLeft = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($user.id)' and roleDefinitionId eq '$directoryReadersId'").value).Count
    "Azure Reader on RG: $azureLeft | Entra Directory Readers: $entraLeft"
    if ($azureLeft -or $entraLeft) { throw 'Removal did not take effect.' }
    "Backup: $((Get-Content $backupPath -Raw | ConvertFrom-Json).Count) entries in $backupPath"

    Step 'Restore -Confirm:$false from the backup file'
    $restored = @(Restore-RiskyRoleAssignment -Path $backupPath -Confirm:$false)
    $restored | Format-Table Result, RoleScope, RoleName, Reason | Out-String -Width 200
    if (@($restored | Where-Object Result -ne 'Restored').Count) { throw 'Not every assignment was restored.' }
    Start-Sleep -Seconds 10

    Step 'Verify both assignments are back'
    $azureBack = @(Get-AzRoleAssignment -ObjectId $user.id -Scope $rgScope -RoleDefinitionId $readerRoleId).Count
    $entraBack = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($user.id)' and roleDefinitionId eq '$directoryReadersId'").value)
    "Azure Reader on RG: $azureBack | Entra Directory Readers: $($entraBack.Count)"
    if ($azureBack -ne 1 -or $entraBack.Count -ne 1) { throw 'Restore did not take effect.' }

    Step 'RESULT: write path verified end to end'
}
finally {
    '==> Cleanup'
    try {
        foreach ($assignment in @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($user.id)' and roleDefinitionId eq '$directoryReadersId'").value)) {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$($assignment.id)" | Out-Null
            "Removed Entra Directory Readers assignment $($assignment.id)"
        }
    }
    catch { Write-Warning "Entra cleanup: $($_.Exception.Message)" }
    try {
        if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) {
            Remove-AzResourceGroup -Name $ResourceGroupName -Force | Out-Null
            "Deleted $ResourceGroupName (and the Reader assignment with it)"
        }
    }
    catch { Write-Warning "Azure cleanup: $($_.Exception.Message)" }
    $left = @(Get-AzRoleAssignment -ObjectId $user.id -ErrorAction SilentlyContinue | Where-Object Scope -like "$rgScope*").Count
    "Remaining test assignments for $($user.displayName): Azure $left"
    Disconnect-MgGraph | Out-Null
    'Graph session with the write scope closed.'
    ''
    'Steps completed:'
    $steps | ForEach-Object { "  $_" }
}
