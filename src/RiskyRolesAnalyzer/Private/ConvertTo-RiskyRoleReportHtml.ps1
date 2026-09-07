function ConvertTo-RiskyRoleReportHtml {
    <#
    .SYNOPSIS
    Render findings into the self-contained HTML report.
    .DESCRIPTION
    Pure: findings in, one HTML string out. The page lives in Resources/report.html with three
    placeholders (__TITLE__, __DATA__, __META__); the findings go in as a JSON array without the
    raw Source objects. Counts, filters and the removal command are computed in the page from that
    array, so the numbers on the cards cannot drift from the rows. Nothing in the page calls out.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$TenantId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$TenantName,

        [Parameter()]
        [string]$Title = 'Privileged Role Audit',

        [Parameter()]
        [datetime]$GeneratedAt = (Get-Date)
    )

    $template = Get-RiskyRoleReportTemplate

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($InputObject)) {
        if ($null -eq $item) { continue }
        $rows.Add(($item | Select-Object -Property * -ExcludeProperty Source))
    }
    $data = if ($rows.Count) { ConvertTo-Json -InputObject $rows.ToArray() -Depth 6 -Compress } else { '[]' }
    $meta = ConvertTo-Json -InputObject @{
        title     = $Title
        tenantId  = $TenantId
        tenantName = $TenantName
        generated = $GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')
        version   = $script:ModuleVersion
        count     = $rows.Count
    } -Compress

    # A closing tag inside a JSON string would end the script block; escape the slash.
    $data = $data.Replace('</', '<\/')
    $meta = $meta.Replace('</', '<\/')
    $safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)

    return $template.Replace('__TITLE__', $safeTitle).Replace('__DATA__', $data).Replace('__META__', $meta)
}
