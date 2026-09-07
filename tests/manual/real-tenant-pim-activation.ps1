# PIM activation detection on a real tenant, without touching any role the account already holds.
#
#   1. Give the signed-in account a PIM eligibility for a harmless role (Directory Readers), 3 h.
#   2. Activate it for 1 h. If PIM insists on the portal, the script waits for you.
#   3. Get-RiskyRoleAssignment -SkipAzure -AdditionalEntraRole 'Directory Readers'
#      Expected: one finding Activated and protected, one Eligible and protected, no Permanent one;
#      Remove -WhatIf refuses both.
#   4. Deactivate and remove the eligibility. Both expire on their own if that fails.
#
# The detection under test is role-agnostic: the module filters roleAssignmentSchedules on
# assignmentType eq 'Activated'. A harmless role proves the same thing as a privileged one, which is
# why this never goes near Global Administrator. Every write carries the test role's definition id.
#
# Needs Entra ID P2, an interactive sign-in with the write scope, and Privileged Role Administrator
# or Global Administrator to create the eligibility.
param(
    [string]$RoleName = 'Directory Readers',
    [string]$RoleDefinitionId = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b',
    # PIM refuses a deactivation in the first minutes after an activation.
    [int]$MinimumActivationAgeMinutes = 6
)
$ErrorActionPreference = 'Stop'
$out = if ($env:RRA_TEST_OUT) { $env:RRA_TEST_OUT } else { [System.IO.Path]::GetTempPath() }
Import-Module (Join-Path $PSScriptRoot '..' '..' 'src' 'RiskyRolesAnalyzer' 'RiskyRolesAnalyzer.psd1') -Force

$graph = 'https://graph.microsoft.com/v1.0'
$steps = [System.Collections.Generic.List[string]]::new()
$checks = [ordered]@{}
function Step([string]$Text) { $script:steps.Add($Text); "==> $Text" }
function Get-MySchedule([string]$Kind) {
    @((Invoke-MgGraphRequest -Method GET -Uri "$graph/roleManagement/directory/$Kind/filterByCurrentUser(on='principal')").value | Where-Object { $_.roleDefinitionId -eq $RoleDefinitionId })
}
function Get-GraphErrorText($ErrorRecord) {
    # The response body says why; the status line does not.
    $detail = $ErrorRecord.ErrorDetails.Message
    if ($detail) {
        try { return (ConvertFrom-Json $detail).error.message } catch { return $detail }
    }
    return $ErrorRecord.Exception.Message
}
function Invoke-PimRequest([string]$Kind, [hashtable]$Body) {
    Invoke-MgGraphRequest -Method POST -Uri "$graph/roleManagement/directory/$Kind" -ContentType 'application/json' -Body $Body -ErrorAction Stop
}
function Wait-Until([scriptblock]$Condition, [string]$What, [int]$TimeoutSeconds = 240) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (& $Condition)) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) { return $false }
        Start-Sleep -Seconds 10
    }
    "  $What after $([int]$sw.Elapsed.TotalSeconds) s"
    return $true
}

$session = Connect-RiskyRolesAnalyzer -RequestWriteScopes -SkipAzure
if (-not $session.WriteScope) { throw 'Graph session has no write scope; the consent must have been declined.' }
$me = Invoke-MgGraphRequest -Method GET -Uri "$graph/me?`$select=id,userPrincipalName,displayName"
"Tenant $($session.TenantId) | $($me.userPrincipalName)"

# The account must not hold the test role in any form, or the test proves nothing and the cleanup
# would remove something real.
$held = @((Invoke-MgGraphRequest -Method GET -Uri "$graph/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($me.id)' and roleDefinitionId eq '$RoleDefinitionId'").value)
if ($held.Count -or (Get-MySchedule 'roleEligibilitySchedules').Count -or (Get-MySchedule 'roleAssignmentSchedules').Count) {
    throw "$($me.userPrincipalName) already holds $RoleName in some form. Pick another harmless role with -RoleName and -RoleDefinitionId."
}

$eligible = $false
$common = @{ principalId = $me.id; roleDefinitionId = $RoleDefinitionId; directoryScopeId = '/'; justification = 'RiskyRolesAnalyzer: PIM activation detection test' }
$nowUtc = { (Get-Date).ToUniversalTime().ToString('o') }

try {
    Step "Create a 3 h PIM eligibility for $RoleName on $($me.userPrincipalName)"
    $null = Invoke-PimRequest 'roleEligibilityScheduleRequests' ($common + @{ action = 'adminAssign'; scheduleInfo = @{ startDateTime = (& $nowUtc); expiration = @{ type = 'afterDuration'; duration = 'PT3H' } } })
    $eligible = $true
    if (-not (Wait-Until { (Get-MySchedule 'roleEligibilitySchedules').Count -gt 0 } 'eligibility visible')) { throw 'The eligibility did not show up in roleEligibilitySchedules.' }

    Step "Activate $RoleName for 1 h"
    try {
        $null = Invoke-PimRequest 'roleAssignmentScheduleRequests' ($common + @{ action = 'selfActivate'; scheduleInfo = @{ startDateTime = (& $nowUtc); expiration = @{ type = 'afterDuration'; duration = 'PT1H' } } })
    }
    catch {
        Write-Warning "Activation through Graph was refused: $(Get-GraphErrorText $_)"
        "  Activate it in the portal instead: Entra ID > Identity governance > PIM > My roles > $RoleName > Activate (1 hour)."
        $null = Read-Host '  Press Enter once the portal shows the activation as active'
    }
    if (-not (Wait-Until { @(Get-MySchedule 'roleAssignmentSchedules' | Where-Object assignmentType -eq 'Activated').Count -gt 0 } 'activation visible in roleAssignmentSchedules')) {
        throw 'roleAssignmentSchedules never reported an Activated entry; the activation did not take effect.'
    }

    Step "Get-RiskyRoleAssignment -SkipAzure -AdditionalEntraRole '$RoleName'"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $findings = @(Get-RiskyRoleAssignment -SkipAzure -AdditionalEntraRole $RoleName -WarningAction SilentlyContinue)
    $sw.Stop()
    $findings | Export-Clixml -Path (Join-Path $out 'pim-findings.xml') -Depth 6
    $mine = @($findings | Where-Object { $_.PrincipalId -eq $me.id })
    "$($findings.Count) finding(s) in $([int]$sw.Elapsed.TotalSeconds) s, $($mine.Count) for $($me.userPrincipalName):"
    $mine | Format-Table RoleName, AssignmentType, Protected, ProtectedReason, RiskScore, Severity | Out-String -Width 200

    $test = @($mine | Where-Object RoleName -eq $RoleName)
    $activatedFinding = @($test | Where-Object AssignmentType -eq 'Activated')
    $eligibleFinding = @($test | Where-Object AssignmentType -eq 'Eligible')
    $checks["exactly one Activated finding for $RoleName"] = ($activatedFinding.Count -eq 1)
    $checks['the activation is protected with the PIM reason'] = ($activatedFinding.Count -eq 1 -and $activatedFinding[0].Protected -and $activatedFinding[0].ProtectedReason -like 'PIM activation*')
    $checks["exactly one Eligible finding for $RoleName, protected"] = ($eligibleFinding.Count -eq 1 -and $eligibleFinding[0].Protected)
    $checks["no Permanent finding for $RoleName (the activation is not mistaken for a permanent assignment)"] = (@($test | Where-Object AssignmentType -eq 'Permanent').Count -eq 0)
    # An activation is live privilege, an eligibility is not: the eligibility carries the -1.5 modifier.
    $checks['the activation scores higher than the eligibility of the same role'] = ($activatedFinding.Count -eq 1 -and $eligibleFinding.Count -eq 1 -and $activatedFinding[0].RiskScore -gt $eligibleFinding[0].RiskScore)
    $checks['the permanent role of the auditing account is still reported and protected'] = (@($mine | Where-Object { $_.AssignmentType -eq 'Permanent' -and $_.Protected -and $_.ProtectedReason -eq 'Identity running this audit' }).Count -ge 1)

    Step 'Remove-RiskyRoleAssignment -WhatIf on both test findings must refuse them'
    $whatIf = @($test | Remove-RiskyRoleAssignment -WhatIf -WarningAction SilentlyContinue)
    $whatIf | Format-Table Result, RoleName, Reason | Out-String -Width 200
    $checks['Remove -WhatIf skipped both as protected'] = ($whatIf.Count -eq 2 -and -not @($whatIf | Where-Object { $_.Result -ne 'Skipped' -or $_.Reason -notlike 'PIM*' }).Count)

    ''
    'Checks:'
    $failed = 0
    foreach ($check in $checks.GetEnumerator()) { if ($check.Value) { "  PASS  $($check.Key)" } else { "  FAIL  $($check.Key)"; $failed++ } }
    if ($failed) { throw "$failed check(s) failed." }
    Step 'RESULT: PIM activation recognised, typed Activated and protected'
}
finally {
    '==> Cleanup'
    # Order matters: PIM refuses a deactivation in the first minutes after activating, and it refuses
    # removing an eligibility while an assignment derived from it is still active.
    $activations = @(Get-MySchedule 'roleAssignmentSchedules' | Where-Object assignmentType -eq 'Activated')
    if ($activations.Count) {
        $age = ((Get-Date).ToUniversalTime() - [datetime]$activations[0].scheduleInfo.startDateTime).TotalMinutes
        if ($age -lt $MinimumActivationAgeMinutes) {
            $wait = [int](($MinimumActivationAgeMinutes - $age) * 60) + 5
            "Waiting $wait s before deactivating: PIM refuses it right after an activation."
            Start-Sleep -Seconds $wait
        }
        foreach ($attempt in 1, 2) {
            try { $null = Invoke-PimRequest 'roleAssignmentScheduleRequests' ($common + @{ action = 'selfDeactivate' }); "Deactivated $RoleName"; break }
            catch {
                Write-Warning "Deactivation attempt ${attempt}: $(Get-GraphErrorText $_)"
                if ($attempt -eq 2) { Write-Warning "The activation expires on its own within 1 h." } else { Start-Sleep -Seconds 60 }
            }
        }
        Start-Sleep -Seconds 20
    }
    if ($eligible -and (Get-MySchedule 'roleEligibilitySchedules').Count) {
        foreach ($attempt in 1, 2) {
            try { $null = Invoke-PimRequest 'roleEligibilityScheduleRequests' ($common + @{ action = 'adminRemove' }); "Removed the $RoleName eligibility"; break }
            catch {
                Write-Warning "Eligibility removal attempt ${attempt}: $(Get-GraphErrorText $_)"
                if ($attempt -eq 2) { Write-Warning "The eligibility expires on its own within 3 h." } else { Start-Sleep -Seconds 60 }
            }
        }
        Start-Sleep -Seconds 20
    }
    $activationsLeft = @(Get-MySchedule 'roleAssignmentSchedules' | Where-Object assignmentType -eq 'Activated').Count
    $eligibilitiesLeft = @(Get-MySchedule 'roleEligibilitySchedules').Count
    "Final state for ${RoleName}: $activationsLeft activation(s), $eligibilitiesLeft eligibility(ies) (both expire on their own if any is left)"
    Disconnect-MgGraph | Out-Null
    ''
    'Steps completed:'
    $steps | ForEach-Object { "  $_" }
}
