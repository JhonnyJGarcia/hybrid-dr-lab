# azure-glpi-lab

A full-cloud lab on **Microsoft Azure**: deploying **GLPI** (IT service desk and asset management) the way a small organisation would run it — private networking, managed database, central identity, monitoring and backups — first by hand in the **Azure portal**, then rebuilt as code with **Terraform** and **Ansible**.

> Status: preparation (no Azure resources yet).

## Goals

- Learn each Azure service hands-on in the portal before automating it
- Rebuild the same environment with **Terraform** and compare it with the portal's exported template
- Configure the VM and GLPI with **Ansible**
- Apply **Zero Trust** principles: no public IPs on servers, **Entra ID** SSO with **MFA** and **Conditional Access**, secrets in **Key Vault**, **Managed Identity**
- Prove operations: **Azure Monitor** alerts, **Azure Backup** with a tested restore
- Run everything from **GitHub Actions** with OIDC (no stored cloud credentials)
- Keep the whole lab inside a free-trial budget, with cost guardrails from day one

## Architecture (target)

| Area | Service |
|---|---|
| Network | VNet with app and data subnets, NSGs, no public IP on the VM |
| Admin access | Azure Bastion (Developer SKU) |
| Compute | Linux VM (B1s) running GLPI |
| Database | Azure Database for MySQL – Flexible Server (B1ms), private access |
| Identity | Entra ID SSO, MFA, Conditional Access, Managed Identity |
| Secrets | Key Vault |
| Monitoring | Azure Monitor, Log Analytics, alert rules |
| Backup | Azure Backup with documented restore test |
| Inventory | GLPI Agent deployed with Ansible |

## Phases

| # | Phase | Notes |
|---|---|---|
| 0 | [Guardrails](docs/phase-0-guardrails.md) | Budgets, Azure Policy, cost analysis |
| 1 | Portal build | ClickOps, with screenshots |
| 2 | Terraform rebuild | Destroy and recreate as code |
| 3 | Ansible configuration | GLPI install, hardening, agent |
| 4 | Identity and Zero Trust | Entra ID SSO, MFA, Conditional Access |
| 5 | Monitoring and backup | Alerts, backup, restore test |
| 6 | CI/CD | GitHub Actions with OIDC |
| 7 | Agentic operations | Sub-agents for IaC review, cost and health checks |
| 8 | Wrap-up | Documentation, teardown |

Naming and tagging rules: [docs/conventions.md](docs/conventions.md).

## Layout

```
docs/          one page per phase, conventions, screenshots/
terraform/     infrastructure as code (phase 2)
ansible/       VM and application configuration (phase 3)
```
