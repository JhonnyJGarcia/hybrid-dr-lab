# Hybrid DR lab: Proxmox + Ceph to Azure

A disaster-recovery lab that connects a **hyper-converged Proxmox VE + Ceph cluster** at home to **Microsoft Azure**: storage is replicated asynchronously with **Ceph RBD mirroring** over a **site-to-site VPN**, so that if the whole home cluster goes down, workloads restart on a **Proxmox node running in Azure**.

> Status: phases 0–5 and 7 done: replication, failover to Azure and failback to home tested; agentic operations layer in place. Azure free trial active.

## Goals

- Build a real **3-node hyper-converged cluster** (Proxmox VE + Ceph), nested on a single home host
- Connect home and cloud with a **site-to-site VPN** between **OPNsense** and **Azure VPN Gateway**
- Replicate container storage off-site with **Ceph RBD snapshot mirroring** (`rbd-mirror`)
- Run a **documented failover and failback**, with measured **RPO** and **RTO**
- Rebuild the Azure side as code with **Terraform** and configure hosts with **Ansible**
- Run everything from **GitHub Actions** with OIDC (no stored cloud credentials)
- Stay inside the free-trial credit, with cost guardrails from day one

## Architecture

```
 HOME (primary site)                                   AZURE (DR site)
 ┌──────────────────────────────────────┐              ┌──────────────────────────────┐
 │ Physical Proxmox host                │              │ VNet                         │
 │  ├─ OPNsense (firewall, VPN)  ◄──────┼── IPsec ─────┼─► VPN Gateway                │
 │  └─ Nested cluster (3 nodes)         │   S2S VPN    │                              │
 │      ├─ Proxmox VE + Ceph (MON, OSD) │              │  Proxmox VE node (single)    │
 │      ├─ Proxmox VE + Ceph (MON, OSD) │  RBD mirror  │   ├─ Ceph, 1 MON, 2–3 OSD    │
 │      └─ Proxmox VE + Ceph (MON, OSD) │ ───────────► │   ├─ rbd-mirror daemon       │
 │          └─ test LXC on Ceph RBD     │  snapshots   │   └─ test LXC (on failover)  │
 └──────────────────────────────────────┘              └──────────────────────────────┘
```

Design decisions and their reasons: [docs/architecture.md](docs/architecture.md).

## Phases

| # | Phase | Notes |
|---|---|---|
| 0 | [Guardrails](docs/phase-0-guardrails.md) | Budget, Azure Policy, quotas |
| 1 | [Nested HCI cluster](docs/phase-1-nested-hci-cluster.md) | 3 Proxmox VE nodes + Ceph on the home host, test LXC on RBD |
| 2 | [Site-to-site VPN](docs/phase-2-site-to-site-vpn.md) | OPNsense ↔ Azure VPN Gateway (IPsec, route-based) |
| 3 | [Azure DR node](docs/phase-3-azure-dr-node.md) | Proxmox VE on an Azure VM, single-node Ceph |
| 4 | [Ceph RBD mirroring](docs/phase-4-rbd-mirroring.md) | Snapshot-based mirroring, container config sync |
| 5 | [Failover and failback](runbooks/failover-failback.md) | Runbook, measured RPO/RTO, failback to home |
| 6 | Infrastructure as code and CI | Terraform (Azure side), Ansible (hosts), GitHub Actions with OIDC |
| 7 | [Agentic operations](docs/phase-7-agentic-ops.md) | Orchestrator + sub-agents for IaC review, health and cost checks, failover preparation (executed by the operator) |
| 8 | Wrap-up | Documentation, teardown |

Naming and tagging rules: [docs/conventions.md](docs/conventions.md).

## Layout

```
docs/          architecture, one page per phase, conventions, screenshots/
terraform/     Azure infrastructure as code (phase 6)
ansible/       Proxmox, Ceph and rbd-mirror configuration (phase 6)
runbooks/      failover and failback procedures (phase 5)
scripts/       read-only helpers used by the agents (phase 7)
.claude/       sub-agents, permission rules and guardrail hook (phase 7)
CLAUDE.md      orchestrator instructions and autonomy tiers (phase 7)
```
