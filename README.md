# powershell-tool-skeleton

The starting point for every PowerShell tool I publish: a Gallery-grade module layout, Pester and
PSScriptAnalyzer wired into CI, a tag-driven release workflow that publishes to the PowerShell
Gallery, the documentation set every repository carries, and, for tools that run inside a tenant,
a Bicep deployment with a Deploy-to-Azure button.

It is extracted from [azure-vm-inplace-upgrade](https://github.com/simon-vedder/azure-vm-inplace-upgrade),
the first tool built this way, and it changes when that pattern changes.

## Use it

Click *Use this template* on GitHub (or clone), then run the initialiser once from the repository root:

```powershell
./init.ps1 -ModuleName RiskyRolesAnalyzer -RepoName risky-roles-analyzer -Noun RiskyRoleAssignment `
    -Description 'Finds privileged Azure RBAC and Entra role assignments that posture tools miss.' `
    -Construct Audit
```

`init.ps1` replaces the placeholders (`__ModuleName__`, `__RepoName__`, `__Noun__`, `__Description__`,
`__Tagline__`, `__Slug__`, the module GUID), renames the placeholder files and folders, removes what
the construct does not need, swaps in the tool README from `.skeleton/` and deletes itself.
`-WhatIf` shows the plan.

## Two constructs

| | Audit | Automation |
|---|---|---|
| Runs | on the administrator's machine, delegated sign-in | inside the customer's tenant, managed identity |
| Shape | `Get-*` → report → optional `Remove-*` | Bicep deploys Automation Account, identity, custom role, thin runbook |
| Module source | PowerShell Gallery | PowerShell Gallery, imported by the deployment at a pinned version |
| Extra files | none | `deploy/`, `src/runbooks/`, Bicep drift check in CI |

Anything that fits neither stays a script in a collection repo.

## What is in the box

```
src/<Module>/            manifest, loader, Public/ (one function per file), Private/ (pure decision functions)
src/runbooks/            thin Azure Automation wrapper                       (Automation)
tests/                   Pester: manifest, exports, help, ShouldProcess, rules on fixtures
deploy/                  main.bicep + modules, azuredeploy.json, lab notes   (Automation)
docs/                    release.md, when-not-to-use-this.md, verification.md, decisions/ (ADRs), images/ (hero + social preview sources)
.github/workflows/       ci.yml (analyzer, tests, Bicep drift), release.yml (tag v* → Gallery + GitHub release)
CHANGELOG.md CONTRIBUTING.md SECURITY.md KNOWN-ISSUES.md LICENSE (MIT)
```

## Rules the skeleton bakes in

- PowerShell 7.2+, `Set-StrictMode -Version Latest`, approved verbs, one function per file,
  comment-based help on every public function including the exact permissions it needs.
- Read-only by default. Every state-changing function has `SupportsShouldProcess`; `Remove-*` has
  `ConfirmImpact = 'High'`, writes a JSON backup before acting and refuses objects marked protected.
  The tests enforce the first two.
- Rules are pure functions in `Private/` and are proven on fixtures, without a tenant.
- Nothing claimed in a README that did not run; `docs/verification.md` holds the runs.
- No secrets, tenant or subscription ids anywhere. No GitHub Pages: each tool has one page on
  [simonvedder.com/tools](https://simonvedder.com/tools) and the README links to it.
- Feature branch always. A version tag publishes; the tag must match the manifest.

## Keeping the skeleton current

When a tool improves the pattern (a better CI step, a new test rule, a Bicep fix), port it back
here in the same week. The skeleton is only useful while it is the best known version.
