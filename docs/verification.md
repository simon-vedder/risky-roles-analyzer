# Verification log

What ran, on what, and how long it took. Every row is a real run; nothing here is extrapolated.

| Date | Scenario | Target | Result |
|---|---|---|---|
| 2026-09-06 | Full Pester suite on the synthetic tenant fixture (15 findings across two subscriptions, inherited MG assignment, nested group cycle, custom roles, dormant and deactivated apps, disabled user, PIM eligibility) | Local, PowerShell 7 on macOS, Pester 6.0.1, Az.Resources 10.0.0, Microsoft.Graph.Authentication 2.36.1 | 109 passed, 0 failed, 5 s |
| 2026-09-06 | Suite extended: report renderer, `Export-`, `Show-`, `Restore-`, PIM activation (16 findings) | Local, as above, Pester 6.0.1 and 5.7.1 | 130 passed, 0 failed, 3 s |
| 2026-09-06 | `Export-RiskyRoleReport` on 14 synthetic findings, opened in headless Chrome | macOS, Chrome headless 1600 px | All rows rendered, cards and filters populated, screenshot in `docs/images/report.png` |
| | Real tenant, read path | | not yet |
| | Real tenant, `Remove-RiskyRoleAssignment` Azure and Entra with backup | | not yet |
