function ConvertTo-PowerShellLiteral {
    <#
    .SYNOPSIS
    Make a value safe to paste inside a single-quoted PowerShell string.
    .DESCRIPTION
    The cleanup commands in the report are text a person copies into a shell, and role and group
    names come from the tenant being audited. A name holding an apostrophe would end the quoted
    string early: 'Simon's Admin Role' is a syntax error, and a name crafted as
    "x'; <command> #" would turn the pasted line into something else. Doubling the apostrophe is
    how PowerShell escapes it inside a single-quoted string. Line breaks are collapsed as well,
    so a name can neither end a comment line nor start a statement of its own.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) { return '' }
    return ($Value -replace '[\r\n\t]+', ' ').Replace("'", "''")
}
