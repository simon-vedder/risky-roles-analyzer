# Manual verification scripts

These do not run in CI. Each needs something CI has no business having: a real tenant with a
throwaway test user, or a local Chrome. Every run is logged in [docs/verification.md](../../docs/verification.md).

| Script | What it proves | Needs |
|---|---|---|
| `real-tenant-write-path.ps1 -UserNamePrefix <name>` | `Remove-` and `Restore-` end to end: Reader on a throwaway resource group and Directory Readers for the test user, `-WhatIf`, remove with backup, verify gone, restore from the file, verify back | Interactive sign-in with the write scope (`Connect-RiskyRolesAnalyzer -RequestWriteScopes`), Owner on the subscription, Privileged Role Administrator or Global Administrator |
| `real-tenant-group-custom-role.ps1 -UserNamePrefix <name>` | Group expansion, custom role rating (`Permissions[]` on Az.Resources 10), disabled-user scoring, `Remove-` refusing the inherited finding, remove and restore of a custom-role and a group assignment | An Az session on disk (`Connect-AzAccount`); the Graph session is built from the Az token, so PIM is out of scope here and `-SkipEntra` is used |
| `report-ui.py [url]` | The report's interactive parts: filters, search, sorting, selection, removal command popup, clipboard, cleanup popups, accept/hide, CSV export, narrow viewport | Google Chrome, Python 3 with `websockets`, the sample served over http: `python3 -m http.server 8765 --bind 127.0.0.1` in `docs/sample` |

Rules for the tenant scripts:

- The test user must hold nothing else. The scripts stop when the prefix matches more or fewer than one user.
- Everything a script creates is deleted in `finally`, and a disabled user is re-enabled there first.
  The last line prints the final state so a failed cleanup is visible, not silent.
- No tenant or subscription ids are hard-coded; the current Az context decides.
