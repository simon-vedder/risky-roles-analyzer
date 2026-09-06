# Verification log

What ran, on what, and how long it took. Every row is a real run; nothing here is extrapolated.

| Date | Scenario | Target | Result |
|---|---|---|---|
| 2026-09-06 | Full Pester suite on the synthetic tenant fixture (15 findings across two subscriptions, inherited MG assignment, nested group cycle, custom roles, dormant and deactivated apps, disabled user, PIM eligibility) | Local, PowerShell 7 on macOS, Pester 6.0.1, Az.Resources 10.0.0, Microsoft.Graph.Authentication 2.36.1 | 109 passed, 0 failed, 5 s |
| | Real tenant, read path | | not yet |
| | Real tenant, `Remove-RiskyRoleAssignment` Azure and Entra with backup | | not yet |
