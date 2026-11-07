# Phase 3: Azure DR node

A Proxmox VE node on an Azure VM, created with Terraform and reachable only through the VPN.

## Region and quota

The trial subscription started in **West Europe**, which turned out to reject new networking resources for this trial ("region not accepting new customers"), while B-series sizes were restricted in West Europe, Italy North, North Europe and France Central. The lab moved to **Sweden Central** (`sdc` in names), where `Standard_B2as_v2` is available. Regional quota: **4 vCPUs**, which is why the DR site is a single node ([architecture](architecture.md)).

## Terraform

Run with a dedicated service principal (`sp-terraform-dr-lab`), scoped to the subscription; its credentials stay in a password manager. State is local for now (remote backend in phase 6).

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-dr-lab-sdc` | |
| VNet | `vnet-dr-lab-sdc` | `10.50.0.0/16` |
| Subnets | `GatewaySubnet`, `snet-pve` | `10.50.0.0/27`, `10.50.1.0/24` |
| NSG | `nsg-snet-pve` | SSH, Proxmox GUI (8006), Ceph, ICMP; sources: home lab network and the VNet only |
| NIC | `nic-vm-pve-dr-lab-sdc-01` | Static `10.50.1.10`, **no public IP**, **IP forwarding on** (the node routes for its containers), accelerated networking off |
| VM | `vm-pve-dr-lab-sdc-01` | `Standard_B2as_v2` (2 vCPU, 8 GB), Debian 13 Gen2, SSH key only |
| Data disks | 2 × 32 GB Standard SSD | Ceph OSDs (`sdb`, `sdc`) |

Cost of a running node: about 0.078 USD/h for the VM plus ~2.40 USD/month per disk. The VM is **deallocated** when not in use.

## Proxmox VE on Debian 13

Installed on top of the Debian image following the official "Install Proxmox VE on Debian" procedure, with two deliberate changes for a cloud VM:

- **The Debian kernel is kept** as a boot fallback. On-premises the guide removes it, but in Azure there is no install media to recover an unbootable VM; the serial console (boot diagnostics) is the only way in.
- GRUB is installed on the OS disk only; when package upgrades ask about the GRUB config, the local version is kept.

Also: `/etc/network/interfaces` from the Azure image lacks `source /etc/network/interfaces.d/*`. Proxmox SDN writes its config there, so the line has to be added before SDN zones work (they show as *error* otherwise).

## Access

No public IP. Everything goes through the site-to-site VPN:

```bash
# SSH, jumping through a home cluster node
ssh -J root@<home-node> -i ~/.ssh/azure_dr <admin-user>@10.50.1.10

# Proxmox GUI through an SSH port-forward, then https://localhost:8006
ssh -J root@<home-node> -i ~/.ssh/azure_dr -L 8006:localhost:8006 <admin-user>@10.50.1.10
```

A laptop on the remote-access VPN cannot reach `10.50.0.0/16` directly: it would need a route on the remote-access server, NAT, and the extra prefix in Azure's local network gateway. The SSH jump avoids all three.

## Single-node Ceph

Set up in [phase 4](phase-4-rbd-mirroring.md): 1 MON, 1 MGR, 2 OSDs, CRUSH failure domain `osd`.
