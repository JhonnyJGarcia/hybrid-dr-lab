# Hybrid DR lab: Proxmox + Ceph to Azure

A disaster-recovery lab that connects a **hyper-converged Proxmox VE + Ceph cluster** at home to **Microsoft Azure**: storage is replicated asynchronously with **Ceph RBD mirroring** over a **site-to-site VPN**, so that if the whole home cluster goes down, workloads restart on a **Proxmox node running in Azure**.

> Status: phase 0 (guardrails). Azure free trial active.

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
| 1 | Nested HCI cluster | 3 Proxmox VE nodes + Ceph on the home host, test LXC on RBD |
| 2 | Site-to-site VPN | OPNsense ↔ Azure VPN Gateway (IPsec, route-based) |
| 3 | Azure DR node | Proxmox VE on an Azure VM, single-node Ceph |
| 4 | Ceph RBD mirroring | Snapshot-based mirroring, container config sync |
| 5 | Failover and failback | Runbook, measured RPO/RTO, failback to home |
| 6 | Infrastructure as code and CI | Terraform (Azure side), Ansible (hosts), GitHub Actions with OIDC |
| 7 | Agentic operations | Sub-agents for IaC review, cost and health checks, failover runbook with approval |
| 8 | Wrap-up | Documentation, teardown |

Naming and tagging rules: [docs/conventions.md](docs/conventions.md).

## Layout

```
docs/          architecture, one page per phase, conventions, screenshots/
terraform/     Azure infrastructure as code (phase 6)
ansible/       Proxmox, Ceph and rbd-mirror configuration (phase 6)
runbooks/      failover and failback procedures (phase 5)
```
