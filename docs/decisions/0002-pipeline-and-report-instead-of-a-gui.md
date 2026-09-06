# 0002. Pipeline and HTML report instead of a GUI

Date: 2026-09-06
Status: accepted

## Context

The original script produced a single HTML report. The question came up whether the module
should instead open an operable GUI in which findings are selected and removed with a click.
The reference point was DeviceOffboardingManager, a PowerShell WPF tool with a real user base.

## Decision

The module has three output layers and no GUI:

1. **Objects.** `Get-RiskyRoleAssignment` returns typed objects; the operable path is the
   pipeline, `Get-… | Out-ConsoleGridView -PassThru | Remove-… `, with one ShouldProcess prompt
   per assignment.
2. **HTML report.** Interactive in the browser (filter, sort, select) but without a backend. Its
   one action is "copy the removal command" for the open PowerShell session.
3. **Grid.** A `Show-` wrapper may open the platform's grid view and pipe the selection back.

A local web GUI (Pode) is possible as a later addition, only on demand.

## Consequences

- The report stays the shareable evidence and the screenshot for the tool page; a GUI cannot be
  handed to a manager.
- Every safety mechanism (ShouldProcess, `-WhatIf`, backup, Protected) exists once, in the
  cmdlets. A click GUI would have to duplicate or bypass it.
- Cross-platform and testable. WPF is Windows-only and untestable from CI; the reference tool's
  author retired his WPF script in favour of a native app, which confirms the ceiling.
- The audience for an audit tool distrusts a local web server acting with their admin token.
  Not having one is a feature.
