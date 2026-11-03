# Phase 0 – Guardrails

Goal: make it impossible to spend real money or drift outside the lab's scope before building anything.

Account: personal **Azure free account** ($200 credit for 30 days, spending limit on, 12 months of free services). Trial activated in November 2026.

## Checklist

### Account
- [x] Sign up for the Azure free account with a personal Microsoft account
- [ ] Verify **spending limit = On** (Cost Management → Subscriptions)
- [ ] Enable MFA on the admin account
- [ ] Note the credit expiry date in this file (no IDs)
- [x] Register the `Microsoft.Compute` resource provider (needed to read quotas)

### Quotas (checked with `az vm list-usage`)
- [x] West Europe, Italy North, Sweden Central: **4 vCPUs total per region**, 4 per VM family
- Consequence: single-node DR site (see [architecture](architecture.md))

### Region availability (checked with `az vm list-skus` and test VNets)
- **West Europe**: new networking rejected (`RequestDisallowedByAzure`, region not accepting new customers); B-series restricted
- **Italy North**: networking OK, every B-series size `NotAvailableForSubscription`
- North Europe, France Central: B-series restricted
- **Sweden Central**: networking OK, `B2as_v2` and `B2s_v2` available → **lab region**
- Latency Italy ↔ Sweden (~40–50 ms) is irrelevant for asynchronous mirroring

### Cost
- [ ] Budget on the subscription: **150 EUR**, alerts at 25 %, 50 %, 80 %, 100 % actual + 100 % forecast
- [ ] Cost Analysis view grouped by tag `project` and `phase`, saved
- [ ] Review the credit balance at the start of every session
- [ ] Deallocate the DR node when not testing

Estimated spend for 30 days (to be checked against the Pricing Calculator):

| Item | Estimate |
|---|---|
| DR node B2as_v2 / B2s_v2 (2 vCPU, 8 GB) | ~60 USD |
| Managed disks (OS + 2 OSD, small) | ~10–15 USD |
| VPN Gateway Basic + public IP | ~30 USD |
| Monitoring, experiments | ~10–20 USD |
| **Total** | **~110–125 USD** |

### Azure Policy (assigned on the subscription)
- [ ] **Allowed locations**: Sweden Central, Italy North, West Europe
- [ ] **Allowed virtual machine size SKUs**: `Standard_B1s`, `Standard_B2as_v2`, `Standard_B2s_v2`, `Standard_B4as_v2`
- [ ] **Require a tag on resources**: `project`, `env`, `phase` (built-in policy, one assignment per tag)
- [ ] **Not allowed resource types**: Azure Firewall, Application Gateway, Azure Bastion

### Verification
- [ ] Try to create a VM outside the allowed sizes → denied by policy
- [ ] Try to create a resource in another region → denied by policy
- [ ] Screenshots of budget, policy assignments and denied attempts in `screenshots/phase-0/`

## Notes

- 2026-11: the lab started as a GLPI deployment and was redesigned as a hybrid DR lab before any resource was created.
