function Get-RiskyRoleReportTemplate {
    <#
    .SYNOPSIS
    The HTML report template.
    .DESCRIPTION
    In the module the template is a file next to the code. The single-file audit script has no
    file to read, so the build inlines the template and replaces this function with one that
    returns it. Keeping the lookup behind a function is what lets both forms share the renderer.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Get-Content -Path (Join-Path $script:ModuleRoot 'Resources' 'report.html') -Raw -Encoding utf8
}
