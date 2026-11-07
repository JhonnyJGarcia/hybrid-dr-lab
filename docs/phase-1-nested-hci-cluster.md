# Phase 1: Nested HCI cluster (primary site)

A 3-node hyper-converged cluster (Proxmox VE + Ceph) built as VMs on one physical Proxmox host at home. It proves the design, not the performance.

## Build

| Item | Value |
|---|---|
| Nodes | 3 VMs on the physical host, Proxmox VE 9.2 |
| Disks per node | `sda` ZFS (OS), `sdb` 32 GB (Ceph OSD) |
| RAM per node | ~3.4 GB |
| NIC 1 (`vmbr0`) | Management + **Ceph public** network, behind OPNsense (default gateway) |
| NIC 2 | Internal **cluster** network, no gateway |
| MTU | 1450 on both networks |
| Ceph | 20.2 (Tentacle): 3 MON, 3 MGR, 3 OSD, pool `rbd-dr` (size 3, min_size 2) added as Proxmox storage |

Network roles:

| Traffic | Network | Why |
|---|---|---|
| Corosync link 0 | Internal cluster network | Dedicated, low-latency link for quorum |
| Corosync link 1 | Management network | Redundant fallback link |
| Ceph public (MON, clients) | Management network | Must be **routable over the VPN**: the `rbd-mirror` daemon in Azure talks to the home MONs and OSDs directly |
| Ceph cluster (OSD replication) | Internal cluster network | Keeps replication traffic off the routed network |

Ceph memory is reduced for the small nodes:

```bash
ceph config set osd osd_memory_target 1073741824   # 1 GiB per OSD
```

## HA test

An Alpine container on `rbd-dr` with HA enabled. One node was **powered off hard** (not shut down). HA fenced the node and restarted the container on another node; the gap in a continuous ping is the local RTO. Shared Ceph storage means nothing has to be copied: the container simply starts elsewhere.

## Issues found and fixes

### Cloned nodes shared their identity
Two nodes were cloned from the first one without resetting it. They shared the `machine-id`, the SSH host keys and the root key pair, and `/etc/hosts` mapped their own IP to the first node's name. Cluster join, SSH between nodes and Ceph auth all failed (MONs not forming quorum, `RADOS permission denied`).

Fix, from the CLI on each clone:
1. Ceph fully purged, OSD disk wiped (packages kept), cluster dissolved
2. New `machine-id` (`/etc/machine-id` and `/var/lib/dbus/machine-id`), new SSH host keys and root key pair
3. `/etc/hosts` listing all three nodes with their own names
4. New per-node certificates (`pvecm updatecerts --force`)

The cluster and Ceph were then rebuilt from the GUI.

**Lesson:** a Proxmox node template must be generalized (machine-id, SSH keys, hostname/hosts) before cloning, exactly like a Windows image needs sysprep.

### Leftovers from the first Ceph install
The first cleanup missed two things that blocked the new OSDs:
- stale bootstrap keyrings in `/var/lib/ceph/bootstrap-*`
- runtime unit links in `/run/systemd/system/ceph-osd.target.wants`, which kept triggering failing OSD units until systemd's start limit locked them out

Both removed, then `systemctl reset-failed`.

### RBD storage "inactive" in Proxmox
Ceph 20.2 generates 60-character keys ending in a single `=`. The `libpve-storage-perl` 9.1.5 parser expected `==`, so Proxmox showed the RBD storage as inactive although Ceph was healthy. Fixed in 9.1.13 (`pve-no-subscription`): nodes updated with `apt full-upgrade`, **one at a time**, keeping quorum and Ceph healthy throughout.
