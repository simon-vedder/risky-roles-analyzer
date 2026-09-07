# Real-tenant test of group expansion, custom role rating, disabled-user scoring and the
# refuse/remove/restore path, with the one approved test user. Everything this script creates,
# it removes again in `finally` and re-enables the user.
#
#   Azure: throwaway resource group, a custom role assignable only there that can write role
#          assignments, a security group with the test user as member, the role assigned to the
#          group and directly to the user. The user is disabled for the duration of the audit.
#   Graph: session borrowed from the Az context (a Graph session does not survive a new pwsh),
#          which cannot read PIM schedules, so the Entra part is skipped here.
param(
    # Display-name prefix of a test user who holds nothing else. Exactly one user must match.
    [Parameter(Mandatory)]
    [string]$UserNamePrefix,
    [string]$ResourceGroupName = 'rg-rra-grouptest-weu',
    [string]$GroupName = 'rra-test-group',
    [string]$RoleName = 'RRA Test Role Assigner',
    [string]$Location = 'westeurope'
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'   # Az breaking-change banners
$out = if ($env:RRA_TEST_OUT) { $env:RRA_TEST_OUT } else { [System.IO.Path]::GetTempPath() }
Import-Module (Join-Path $PSScriptRoot '..' '..' 'src' 'RiskyRolesAnalyzer' 'RiskyRolesAnalyzer.psd1') -Force

$steps = [System.Collections.Generic.List[string]]::new()
function Step([string]$Text) { $script:steps.Add($Text); "==> $Text" }
function Wait-Until([scriptblock]$Condition, [string]$What, [int]$TimeoutSeconds = 240) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (& $Condition)) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw "Timed out waiting for $What" }
        Start-Sleep -Seconds 10
    }
    "  $What after $([int]$sw.Elapsed.TotalSeconds) s"
}

$graphToken = Get-AzAccessToken -ResourceTypeName MSGraph -AsSecureString
Connect-MgGraph -AccessToken $graphToken.Token -NoWelcome
$mg = Get-MgContext
$subscription = (Get-AzContext).Subscription
"Tenant $($mg.TenantId) | Graph $($mg.Account) ($($mg.AuthType)) | subscription $($subscription.Name) | Az.Resources $((Get-Module Az.Resources).Version)"

$users = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$filter=startswith(displayName,'$UserNamePrefix')&`$select=id,displayName,userPrincipalName,accountEnabled").value)
if ($users.Count -ne 1) { throw "Expected exactly one user whose display name starts with '$UserNamePrefix', found $($users.Count): $(($users | ForEach-Object { $_.displayName }) -join ', ')" }
$user = $users[0]
if (-not $user.accountEnabled) { throw "$($user.displayName) is already disabled; not touching it." }
"Test user: $($user.displayName) ($($user.userPrincipalName)), enabled"

$rgScope = "/subscriptions/$($subscription.Id)/resourceGroups/$ResourceGroupName"
$group = $null; $role = $null; $disabled = $false
$backupPath = Join-Path $out 'grouptest-backup.json'
Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
$checks = [ordered]@{}

try {
    Step "Create $ResourceGroupName"
    $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{ purpose = 'RiskyRolesAnalyzer group and custom-role test'; deleteAfter = (Get-Date).AddDays(1).ToString('yyyy-MM-dd') } -Force

    Step "Create custom role '$RoleName', assignable only at the resource group"
    $roleFile = Join-Path $out 'grouptest-role.json'
    $permission = @{
        Actions        = @('Microsoft.Authorization/roleAssignments/write', 'Microsoft.Authorization/roleAssignments/read', 'Microsoft.Resources/subscriptions/resourceGroups/read')
        NotActions     = @()
        DataActions    = @()
        NotDataActions = @()
    }
    @{
        Name             = $RoleName
        IsCustom         = $true
        Description      = 'RiskyRolesAnalyzer test: can write role assignments in one resource group'
        Permissions      = @($permission)   # Az.Resources 10 input shape; older versions took the four arrays flattened
        AssignableScopes = @($rgScope)
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $roleFile -Encoding utf8
    $role = New-AzRoleDefinition -InputFile $roleFile
    "  role id $($role.Id)"
    Wait-Until { [bool](Get-AzRoleDefinition -Id $role.Id -Scope $rgScope -ErrorAction SilentlyContinue) } 'custom role readable at the resource group'
    $listedAtSub = [bool](Get-AzRoleDefinition -Custom | Where-Object Id -eq $role.Id)
    "  listed by Get-AzRoleDefinition -Custom at subscription scope: $listedAtSub"
    $sample = Get-AzRoleDefinition -Id $role.Id -Scope $rgScope
    "  PSRoleDefinition members: Actions=$($null -ne ($sample | Get-Member -Name Actions)) Permissions=$($null -ne ($sample | Get-Member -Name Permissions)) | flattened Actions count: $(@($sample.Actions).Count)"

    Step "Create group '$GroupName' with $($user.displayName) as member"
    $group = New-AzADGroup -DisplayName $GroupName -MailNickname ($GroupName -replace '[^a-z0-9]', '') -SecurityEnabled -Description 'RiskyRolesAnalyzer test group'
    Add-AzADGroupMember -TargetGroupObjectId $group.Id -MemberObjectId $user.id
    Wait-Until { @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($group.Id)/members?`$select=id").value).Count -eq 1 } 'group membership visible'

    Step "Assign '$RoleName' to the group and directly to $($user.displayName) on the resource group"
    Wait-Until {
        try { $null = New-AzRoleAssignment -ObjectId $group.Id -RoleDefinitionId $role.Id -Scope $rgScope -ErrorAction Stop; $true }
        catch { "  retry: $($_.Exception.Message.Split("`n")[0])"; $false }
    } 'group assignment created'
    $null = New-AzRoleAssignment -ObjectId $user.id -RoleDefinitionId $role.Id -Scope $rgScope
    Wait-Until { @(Get-AzRoleAssignment -Scope $rgScope -RoleDefinitionId $role.Id | Where-Object Scope -eq $rgScope).Count -eq 2 } 'both assignments listed'

    Step "Disable $($user.displayName) for the duration of the audit"
    try {
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)" -ContentType 'application/json' -Body @{ accountEnabled = $false } | Out-Null
        $disabled = $true
        Wait-Until { -not (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)?`$select=accountEnabled").accountEnabled } 'user disabled'
    }
    catch { "  could not disable the user with this token: $($_.Exception.Message.Split("`n")[0]); the disabled-user checks are skipped" }

    Step 'Get-RiskyRoleAssignment on this subscription (-SkipEntra: PIM schedules are not readable with a borrowed token)'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $findings = @(Get-RiskyRoleAssignment -SubscriptionId $subscription.Id -SkipEntra)
    $sw.Stop()
    $onRg = @($findings | Where-Object Scope -eq $rgScope)
    "$($findings.Count) finding(s) in $([int]$sw.Elapsed.TotalSeconds) s, $($onRg.Count) on the test resource group:"
    $onRg | Format-Table Severity, RiskScore, RoleName, IsCustomRole, PrincipalType, PrincipalName, ActivityStatus, ViaGroup, Protected, ProtectedReason | Out-String -Width 240
    "  risky actions: $(($onRg | ForEach-Object { $_.RiskyActions } | Sort-Object -Unique) -join ', ')"

    $groupFinding = @($onRg | Where-Object PrincipalId -eq $group.Id)
    $viaGroup = @($onRg | Where-Object { $_.PrincipalId -eq $user.id -and $_.ViaGroupId })
    $direct = @($onRg | Where-Object { $_.PrincipalId -eq $user.id -and -not $_.ViaGroupId })
    $checks['three findings on the resource group (group, member via group, direct)'] = ($onRg.Count -eq 3)
    $checks['custom role recognised as custom with the risky action listed'] = ($onRg.Count -gt 0 -and -not @($onRg | Where-Object { -not $_.IsCustomRole -or 'Microsoft.Authorization/roleAssignments/write' -notin $_.RiskyActions }).Count)
    $checks['scope level ResourceGroup everywhere'] = ($onRg.Count -gt 0 -and -not @($onRg | Where-Object ScopeLevel -ne 'ResourceGroup').Count)
    $checks['group itself reported as PrincipalType Group, 5.9 Medium'] = ($groupFinding.Count -eq 1 -and $groupFinding[0].PrincipalType -eq 'Group' -and $groupFinding[0].RiskScore -eq 5.9 -and $groupFinding[0].Severity -eq 'Medium')
    $checks['member via group: protected with the group named'] = ($viaGroup.Count -eq 1 -and $viaGroup[0].Protected -and $viaGroup[0].ViaGroup -eq $GroupName -and $viaGroup[0].ViaGroupId -eq $group.Id -and $viaGroup[0].ProtectedReason -eq "Inherited through group '$GroupName'")
    $checks['direct assignment: not protected, user type, UPN filled'] = ($direct.Count -eq 1 -and -not $direct[0].Protected -and $direct[0].PrincipalType -eq 'User' -and $direct[0].UPN -eq $user.userPrincipalName)
    $checks['finding ids differ between direct and via-group'] = ($direct.Count -eq 1 -and $viaGroup.Count -eq 1 -and $direct[0].Id -ne $viaGroup[0].Id)
    if ($disabled) {
        $checks['disabled user: ActivityStatus Disabled, AccountEnabled False, on both findings'] = (@(@($direct) + @($viaGroup) | Where-Object { $_.ActivityStatus -eq 'Disabled' -and $_.AccountEnabled -eq $false }).Count -eq 2)
        $checks['disabled user scored 3.9 Low (9.0 x 0.65 - 2.0)'] = ($direct.Count -eq 1 -and $direct[0].RiskScore -eq 3.9 -and $direct[0].Severity -eq 'Low')
    }

    Step 'Remove-RiskyRoleAssignment on all three: the inherited one must be refused, the other two removed'
    $removed = @($onRg | Remove-RiskyRoleAssignment -BackupPath $backupPath -Confirm:$false)
    $removed | Format-Table Result, RoleName, PrincipalName, Reason | Out-String -Width 200
    $checks['remove: inherited finding skipped with the protection reason'] = ($viaGroup.Count -eq 1 -and @($removed | Where-Object { $_.Id -eq $viaGroup[0].Id -and $_.Result -eq 'Skipped' -and $_.Reason -like 'Inherited through group*' }).Count -eq 1)
    $checks['remove: group assignment and direct assignment removed'] = (@($removed | Where-Object Result -eq 'Removed').Count -eq 2)
    Start-Sleep -Seconds 15
    $left = @(Get-AzRoleAssignment -Scope $rgScope -RoleDefinitionId $role.Id | Where-Object Scope -eq $rgScope)
    $checks['remove: nothing left on the resource group'] = ($left.Count -eq 0)
    $backup = @(Get-Content $backupPath -Raw | ConvertFrom-Json)
    $checks['backup holds exactly the two removed entries'] = ($backup.Count -eq 2 -and -not @($backup | Where-Object ViaGroupId).Count)

    Step 'Restore-RiskyRoleAssignment from the backup (custom role by definition id, group principal)'
    $restored = @(Restore-RiskyRoleAssignment -Path $backupPath -Confirm:$false)
    $restored | Format-Table Result, RoleName, PrincipalName, Reason | Out-String -Width 200
    $checks['restore: both restored'] = (@($restored | Where-Object Result -eq 'Restored').Count -eq 2)
    Start-Sleep -Seconds 15
    $back = @(Get-AzRoleAssignment -Scope $rgScope -RoleDefinitionId $role.Id | Where-Object Scope -eq $rgScope)
    $checks['restore: both assignments back on the resource group'] = ($back.Count -eq 2 -and ($back.ObjectId | Sort-Object) -join ',' -eq (@($group.Id, $user.id) | Sort-Object) -join ',')

    ''
    'Checks:'
    $failed = 0
    foreach ($check in $checks.GetEnumerator()) { if ($check.Value) { "  PASS  $($check.Key)" } else { "  FAIL  $($check.Key)"; $failed++ } }
    if ($failed) { throw "$failed check(s) failed." }
    Step 'RESULT: group expansion, custom role rating, disabled-user scoring and refuse/remove/restore verified'
}
finally {
    '==> Cleanup'
    if ($disabled) {
        try {
            Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)" -ContentType 'application/json' -Body @{ accountEnabled = $true } | Out-Null
            "Re-enabled $($user.displayName)"
        }
        catch { "RE-ENABLE FAILED for $($user.displayName): $($_.Exception.Message)" }
    }
    try {
        foreach ($assignment in @(Get-AzRoleAssignment -Scope $rgScope -ErrorAction SilentlyContinue | Where-Object Scope -eq $rgScope)) {
            Remove-AzRoleAssignment -InputObject $assignment -ErrorAction Stop | Out-Null
            "Removed assignment $($assignment.RoleDefinitionName) for $($assignment.DisplayName)"
        }
    }
    catch { "Assignment cleanup: $($_.Exception.Message)" }
    if ($role) {
        try { $null = Remove-AzRoleDefinition -Id $role.Id -Scope $rgScope -Force -ErrorAction Stop; "Deleted custom role '$RoleName'" }
        catch { "Custom role cleanup failed, delete '$RoleName' by hand: $($_.Exception.Message)" }
    }
    if ($group) {
        try { Remove-AzADGroup -ObjectId $group.Id -ErrorAction Stop; "Deleted group '$GroupName'" }
        catch { "Group cleanup failed, delete '$GroupName' by hand: $($_.Exception.Message)" }
    }
    try {
        if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) { $null = Remove-AzResourceGroup -Name $ResourceGroupName -Force; "Deleted $ResourceGroupName" }
    }
    catch { "Resource group cleanup: $($_.Exception.Message)" }

    $enabledNow = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)?`$select=accountEnabled").accountEnabled
    $rolePresent = [bool](Get-AzRoleDefinition -Name $RoleName -ErrorAction SilentlyContinue)
    $groupPresent = if ($group) { [bool](Get-AzADGroup -ObjectId $group.Id -ErrorAction SilentlyContinue) } else { $false }
    $rgPresent = [bool](Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)
    "Final state: $($user.displayName) enabled=$enabledNow | custom role present=$rolePresent | group present=$groupPresent | resource group present=$rgPresent"
    Disconnect-MgGraph | Out-Null
    ''
    'Steps completed:'
    $steps | ForEach-Object { "  $_" }
}
