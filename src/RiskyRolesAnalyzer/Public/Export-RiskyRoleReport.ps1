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

    .PARAMETER Open
    Open the report in the default browser after writing it.

    .EXAMPLE
    $findings = Get-RiskyRoleAssignment
    $findings | Export-RiskyRoleReport -Open

    .EXAMPLE
    Get-RiskyRoleAssignment -SkipAzure | Export-RiskyRoleReport -Path ./entra-roles.html -Title 'Contoso Entra roles'

    .OUTPUTS
    System.IO.FileInfo
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
        $html = ConvertTo-RiskyRoleReportHtml -InputObject $items.ToArray() -TenantId $TenantId -Title $Title

        if (-not $PSCmdlet.ShouldProcess($Path, "Write HTML report with $($items.Count) finding(s)")) { return }
        Set-Content -Path $Path -Value $html -Encoding utf8 -NoNewline
        $file = Get-Item -Path $Path
        Write-Verbose "Report with $($items.Count) finding(s): $($file.FullName)"
        if ($Open) { Invoke-Item -Path $file.FullName }
        $file
    }
}
