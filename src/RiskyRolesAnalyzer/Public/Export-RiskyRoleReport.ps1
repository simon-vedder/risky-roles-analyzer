function Export-RiskyRoleReport {
    <#
    .SYNOPSIS
    Write the findings to a self-contained HTML report.

    .DESCRIPTION
    One file, no external resources, opens anywhere: summary cards, search, filters, sortable
    columns, CSV export, the native cleanup command per finding, and a checkbox per removable
    finding that builds the Remove-RiskyRoleAssignment command for your PowerShell session.
    Nothing runs from the page; it only helps you decide and copy.

    .PARAMETER InputObject
    Findings from Get-RiskyRoleAssignment.

    .PARAMETER Path
    Where to write the report. Default: ./RiskyRolesAnalyzer-report-<timestamp>.html.

    .PARAMETER Title
    Heading of the report. Default: Privileged Role Audit.

    .PARAMETER TenantId
    Shown in the header. Default: the tenant of the current Graph session.

    .PARAMETER TenantName
    Shown next to the id. Default: the organisation display name from Graph, when readable.

    .PARAMETER Open
    Open the report in the default browser after writing it.

    .EXAMPLE
    $findings = Get-RiskyRoleAssignment
    $findings | Export-RiskyRoleReport -Open

    .EXAMPLE
    Get-RiskyRoleAssignment -SkipAzure | Export-RiskyRoleReport -Path ./entra-roles.html -Title 'Contoso Entra roles'

    .OUTPUTS
    System.IO.FileInfo

    .NOTES
    Required permissions: none beyond what produced the findings. The report is rendered from the
    objects you pass in. The tenant name is looked up through Graph when a session exists and the
    organisation is readable; without it the header shows the tenant id alone.

    The file is self-contained: no external scripts, styles or fonts, nothing is sent anywhere, and
    the findings are embedded as JSON. It is safe to hand to someone outside your organisation only
    if the findings themselves are, because it contains principal names, ids and scopes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [PSTypeName('RiskyRolesAnalyzer.RiskyRoleAssignment')]
        [object[]]$InputObject,

        [Parameter()]
        [string]$Path = (Join-Path (Get-Location) ('RiskyRolesAnalyzer-report-{0:yyyyMMdd-HHmmss}.html' -f (Get-Date))),

        [Parameter()]
        [string]$Title = 'Privileged Role Audit',

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$TenantName,

        [Parameter()]
        [switch]$Open
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in @($InputObject)) { if ($null -ne $item) { $items.Add($item) } }
    }

    end {
        if (-not $TenantId) {
            $context = Get-MgContext -ErrorAction SilentlyContinue
            $TenantId = [string](Get-PropertyOrDefault -InputObject $context -Name 'TenantId' -Default '')
        }
        if (-not $TenantName) {
            try {
                $organisation = @(Get-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName')
                if ($organisation.Count) { $TenantName = [string](Get-PropertyOrDefault -InputObject $organisation[0] -Name 'displayName' -Default '') }
            }
            catch { Write-Verbose "Organisation name not readable: $($_.Exception.Message)" }
        }
        $html = ConvertTo-RiskyRoleReportHtml -InputObject $items.ToArray() -TenantId $TenantId -TenantName $TenantName -Title $Title

        if (-not $PSCmdlet.ShouldProcess($Path, "Write HTML report with $($items.Count) finding(s)")) { return }
        Set-Content -Path $Path -Value $html -Encoding utf8 -NoNewline
        $file = Get-Item -Path $Path
        Write-Verbose "Report with $($items.Count) finding(s): $($file.FullName)"
        if ($Open) { Invoke-Item -Path $file.FullName }
        $file
    }
}
