# 3. The report ships as a script; the module is not published

Date: 2026-09-07
Status: accepted
Supersedes part of [0001](0001-module-on-the-gallery.md)

## Context

0001 chose a Gallery module because a runbook can only import modules, and because a module is
composable and testable. The first of those reasons never applied here: this tool is a local audit
that a person runs, not an unattended job. What is left is a module you install in order to produce
an HTML file you read once a quarter.

Simon put it plainly while looking at the finished thing: "ich will nur ein report und muss erstmal
ein powershell modul installieren, was ich ggf eh nur 1-2 mal ausfuehre." Removing a role assignment
is not a gap either. The portal does it in two clicks, `Remove-AzRoleAssignment` in one line. The
module's write path adds a safety net, not a capability, and a safety net is only reached by someone
who already decided to remove several assignments at once, which is rare.

## Decision

The report path ships as a single generated script, `dist/Invoke-RiskyRolesAudit.ps1`. Download it,
run it, get the report. Nothing installed.

The module stays in the repository and stays tested, because the script is generated from it. It is
no longer published to the PowerShell Gallery; version 0.1.0-preview is unlisted, which keeps the
name reserved and stops the package from being found. Anyone who wants the removal path clones the
repository and imports it.

The report no longer emits module commands. Every finding carries its native Azure or Graph command,
and the bulk selection now copies those, with a line saying they ask for no confirmation.

## Consequences

- The first thing between a reader and the report is gone.
- The safety net is one step further away. Someone who removes assignments from the copied native
  commands has no backup file and no refusal for break-glass or PIM. The report says so where the
  commands are shown.
- The rules keep their tests. The script is built from the module sources, so the class of bug the
  old hand-written script still carries, custom roles silently rated harmless on Az.Resources 10,
  cannot come back.
- A Gallery download count is no longer a usage signal for this tool. That was never a good one.

## What would reverse this

A reason for the tool to run unattended, in Automation or a pipeline. That needs a module, and this
decision would be revisited rather than worked around.
