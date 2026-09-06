# When not to use this

Read this before running it against anything that matters.

## What Microsoft offers instead

If your tenant has Entra ID P2 and you already run **Privileged Identity Management** with
*Discovery and insights* and **access reviews** on the privileged roles, you have a continuous
process; this module is a snapshot. Use the process. The module is for the tenants that do not
have that, for the Azure RBAC side that PIM's insights do not cover, and for the day someone asks
for the complete list with reasons.

**Microsoft Defender for Cloud** raises recommendations about owners, guests and deprecated
accounts on subscriptions. It does not read custom role actions or expand groups; if its
recommendations are all you need, stay with them.

## Do not use for

| Case | Why | Do this instead |
|---|---|---|
| Continuous monitoring | One run is one point in time. Nothing watches the tenant afterwards. | Defender for Cloud, Entra ID Protection, Sentinel analytics on role changes |
| Attack path analysis | The module lists assignments and rates them. It does not chain them. | BloodHound / AzureHound |
| Compliance baselines | It has no notion of a baseline to compare against. | Maester, ScubaGear |
| Unattended cleanup | Every removal is meant to pass a person. `-Confirm:$false` exists for scripted use by that person, not for a schedule. | An access review with auto-apply, if you must automate |
| Tenants you are not accountable for | The cleanup commands and the module remove access. Read is fine; write needs a mandate. | Report only |

## Things the tool cannot see

- The context behind a finding. A privileged assignment may be there for a reason nobody documented.
- Whether removing something breaks an automation that depends on it. The backup file is a rollback
  point, not a test.
- Conditional Access, authentication strength and sign-in risk. A Global Administrator behind
  phishing-resistant MFA and a Global Administrator with a password score the same here.
- Azure resource-level data plane permissions outside the risky-action list, Key Vault access
  policies, storage account keys in use.
