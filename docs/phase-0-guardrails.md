# Phase 0 – Guardrails

Goal: make it impossible to spend real money or drift outside the lab's scope before building anything.

Account: personal **Azure free account** ($200 credit for 30 days, spending limit on, 12 months of free services). The 30-day clock starts at sign-up, so this phase runs only when the lab can be worked on steadily.

## Checklist

### Account
- [ ] Sign up for the Azure free account with a personal Microsoft account
- [ ] Verify **spending limit = On** (Cost Management → Subscriptions)
- [ ] Enable MFA on the admin account
- [ ] Note the credit expiry date in this file (no IDs)

### Cost
- [ ] Budget `budget-glpi-lab` on the subscription: 20 USD/month, alerts at 25 % (5), 50 % (10), 100 % (20) actual + 100 % forecast
- [ ] Cost Analysis view grouped by tag `project` and `phase`, saved
- [ ] Review the credit balance at the start of every session

### Azure Policy (assigned on the subscription)
- [ ] **Allowed locations**: West Europe, Italy North
- [ ] **Allowed virtual machine size SKUs**: `Standard_B1s`, `Standard_B1ms`
- [ ] **Require a tag on resources**: `project`, `env`, `phase` (built-in policy, one assignment per tag)
- [ ] Optional: **Not allowed resource types** for expensive services (Azure Firewall, Application Gateway, Bastion Standard/Basic, VPN Gateway)

### Verification
- [ ] Try to create a VM larger than B1ms → denied by policy
- [ ] Try to create a resource in another region → denied by policy
- [ ] Screenshots of budget, policy assignments and denied attempts in `screenshots/phase-0/`

## Notes

_(decisions, problems and what was learned)_
