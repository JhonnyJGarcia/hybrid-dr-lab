# Architecture and design decisions

## Scenario

The primary site is a 3-node hyper-converged cluster (Proxmox VE + Ceph). The DR site lives in Azure. If the whole primary cluster is lost, the protected workloads restart in Azure from replicated storage.

## Decisions

### Two independent clusters, not one stretched cluster
Proxmox clustering relies on **Corosync**, which needs low, stable latency (a few milliseconds). A cluster stretched over a VPN to a cloud region would lose quorum on every latency spike. This is also true for companies with fibre: stretched clusters are only used between nearby sites. The DR site is therefore a separate cluster.

### Ceph RBD mirroring instead of Proxmox storage replication
Proxmox's built-in storage replication (`pvesr`) works only between nodes of the **same** cluster and only with ZFS. Between two Ceph clusters the native tool is **RBD mirroring**:
- **snapshot-based** mode (works with `krbd`, which Proxmox uses for containers); journal-based mode needs `librbd` and does not apply to LXC
- an `rbd-mirror` daemon on the DR side pulls snapshots on a schedule (target: every 5 minutes)
- Proxmox does not manage this from the GUI: the guest configuration (`/etc/pve/lxc/<id>.conf`) must be copied to the DR node separately

Mirroring copies mistakes too (deletions, ransomware), so it does not replace backups.

### Single-node DR site
The Azure free trial allows **4 vCPUs per region**. A 3-node Ceph cluster would need at least 6. The DR site is one Proxmox node running Ceph with the CRUSH failure domain set to `osd` (1 MON, 1 MGR, 2–3 OSDs on separate disks). It is not redundant, which is acceptable for a DR target and is stated as a known limit.

### Containers only, no nested virtualization needed in Azure
The protected workload is an LXC container. Containers do not need hardware virtualization, so the Azure node can use an inexpensive B-series size. Firewalling and routing on the DR side are done by Azure networking, so OPNsense is not replicated.

### Nested primary cluster
The three primary nodes are VMs on one physical Proxmox host. Ceph runs with reduced memory settings (`osd_memory_target`) and one small OSD per node. Cluster and Ceph traffic use an internal bridge behind OPNsense. This proves the design, not the performance.

### Networking
- Site-to-site **IPsec** (IKEv2, route-based) between OPNsense and Azure VPN Gateway (Basic SKU)
- Ceph public network, mirroring traffic and management cross the VPN; nothing is exposed to the internet
- Guests on the Azure node use routed networking, because Azure drops frames from unknown MAC addresses

## Recovery objectives (targets, to be measured in phase 5)

| Metric | Target |
|---|---|
| RPO | ≤ 5–10 minutes (mirror snapshot interval) |
| RTO | ≤ 30 minutes (promote image, register guest, start) |

## Out of scope

- Live migration between sites
- High availability inside the DR site
- Replicating large data sets (home upload bandwidth is the limit)
