function Get-RiskyRoleGridCommand {
    <#
    .SYNOPSIS
    The grid view available on this host, or nothing.
    .DESCRIPTION
    Out-ConsoleGridView (Microsoft.PowerShell.ConsoleGuiTools, any platform) first, then
    Out-GridView (Windows). Both take -Title and -OutputMode Multiple. Separate so tests can
    substitute a grid without a terminal.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.CommandInfo])]
    param()

    foreach ($name in 'Out-ConsoleGridView', 'Out-GridView') {
        $command = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command }
    }
    return $null
}
