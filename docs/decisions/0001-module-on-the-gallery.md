# 0001 — A PowerShell Gallery module, not a script

**Status:** accepted · 2026

## Context

Single-file scripts work and are untestable, unusable outside the shell they were written for and
impossible to review in pieces. Every tool in this family started as one.

## Decision

The logic is a module, `RiskyRolesAnalyzer`, one function per file, published to the PowerShell
Gallery. Rules are pure functions in `Private/` and are tested on fixtures. Anything that runs
elsewhere (an Azure Automation runbook, a pipeline step) is a thin wrapper that signs in, resolves
scope, calls the module and summarises.

## Why

- Local use is a first-class scenario: `Install-Module RiskyRolesAnalyzer`, sign in, `Get-RiskyRoleAssignment`.
  That is how anyone tries it before trusting it.
- Pester can prove every rule without a tenant.
- One implementation for local, Cloud Shell, pipeline and runbook.

## Rejected

Flattening the module into a script at build time: no distribution step, but a second artefact
to keep in sync and no `Install-Module` story. The Gallery is the channel the audience already uses.

## Consequences

- PowerShell 7.2+ only.
- Semantic versioning from the first release; the tag must match the manifest.
