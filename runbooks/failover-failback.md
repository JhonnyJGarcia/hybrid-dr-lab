# Runbook: failover to Azure and failback to home

Applies to containers whose disk is mirrored two-way ([phase 4](../docs/phase-4-rbd-mirroring.md)). Example: container `101`, disk `rbd-dr/vm-101-disk-0`.

**The one rule:** never start a container on a non-primary image. Proxmox will start it, the filesystem will be corrupted. Every start below is chained to a successful promote and a primary check, so it cannot run on its own.

## Networking on the DR side

Failed-over containers do not keep their home address. They live in the Proxmox SDN **simple zone** `drnet` (vnet `drnet`) on the DR node:

| Item | Value |
|---|---|
| Subnet | `10.50.2.0/24`, gateway `10.50.2.1` (the DR node) |
| Internet egress | SNAT to the node's private IP, then Azure default outbound |
| Reachability from home | Azure route table `rt-dr-lab-sdc`: `10.50.2.0/24` → DR node, attached to `GatewaySubnet` and `snet-pve` (NIC IP forwarding enabled) |

Reusing the home subnet in Azure was rejected: a connected route to the home network on the DR node would capture traffic to the home Ceph MONs and break mirroring.

## Preparation (once per container)

On the DR node, a copy of the container config with the DR network, kept **outside** `/etc/pve/lxc/`:

```bash
mkdir -p /root/dr-configs
# same as the home config (pct config <id>), with:
#   net0: ...,bridge=drnet,gw=10.50.2.1,ip=10.50.2.<id>/24,...   and no HA entry
vi /root/dr-configs/101.conf
```

## Planned failover (home reachable)

**Home**

```bash
ha-manager set ct:101 --state stopped
ha-manager status | grep ct:101                # repeat until "stopped"
ha-manager remove ct:101
rbd mirror image demote rbd-dr/vm-101-disk-0   # final mirror snapshot; no site is primary now
```

**DR node**

```bash
rbd mirror image status rbd-dr/vm-101-disk-0   # wait: local_snapshot_timestamp = remote_snapshot_timestamp

rbd mirror image promote rbd-dr/vm-101-disk-0 \
  && rbd info rbd-dr/vm-101-disk-0 | grep -q 'mirroring primary: true' \
  && cp /root/dr-configs/101.conf /etc/pve/lxc/101.conf \
  && pct start 101 && echo "FAILOVER OK"
```

If the promote fails because the image is not synced yet, wait and run the same block again. RPO is zero: Ceph refuses a non-forced promote until the demotion snapshot has been replayed.

## Disaster failover (home unreachable)

Home cannot be demoted, so the DR copy is promoted by force. Data written at home after the last replayed mirror snapshot is lost (at most the 15-minute schedule).

```bash
rbd mirror image status rbd-dr/vm-101-disk-0   # note local_snapshot_timestamp: that is your recovery point

# ⚠️ point of no return: both sites will consider themselves primary
rbd mirror image promote --force rbd-dr/vm-101-disk-0 \
  && rbd info rbd-dr/vm-101-disk-0 | grep -q 'mirroring primary: true' \
  && cp /root/dr-configs/101.conf /etc/pve/lxc/101.conf \
  && pct start 101 && echo "FAILOVER OK"
```

When home comes back, its copy is still primary (split-brain): before anything else, **keep HA from starting the container at home** (`ha-manager remove ct:101`), then follow *Failback after a disaster*.

## Planned failback (Azure → home, keeps Azure-side writes)

**DR node**

```bash
pct shutdown 101 \
  && mv /etc/pve/lxc/101.conf /root/dr-configs/101.conf \
  && rbd mirror image demote rbd-dr/vm-101-disk-0 && echo "DEMOTED"
```

**Home**

```bash
rbd mirror image status rbd-dr/vm-101-disk-0   # wait: local = remote

rbd mirror image promote rbd-dr/vm-101-disk-0 \
  && rbd info rbd-dr/vm-101-disk-0 | grep -q 'mirroring primary: true' \
  && ha-manager add ct:101 --state started && echo "FAILBACK OK"
```

## Failback after a disaster

Both copies are primary. Azure has the newer data, so home's copy is the one to discard:

```bash
# home: make the old copy non-primary and rebuild it from Azure
# ⚠️ point of no return: writes made at home after the last snapshot replayed to Azure are discarded
rbd mirror image demote rbd-dr/vm-101-disk-0
rbd mirror image resync rbd-dr/vm-101-disk-0
```

Wait for home to show `up+replaying` and caught up, then run the planned failback.

## Results (2026-11-07)

**One-way test** (disaster-style failover with `--force`, failback with resync, Azure-side writes discarded):

| Check | Result |
|---|---|
| Container starts in Azure with the replicated data | ✅ |
| DR gateway, reachability from home through the VPN, DNS | ✅ |
| Internet egress over TCP | ✅ |
| `ping` to the internet | ❌ expected: Azure default outbound access does not carry ICMP for a VM without a public IP |

**Two-way test** (planned failover and failback, no `--force`, no resync):

| Check | Result |
|---|---|
| Marker written at home before failover, present in Azure | ✅ |
| Marker written in Azure during failover, present at home after failback | ✅ |
| Filesystem after the round trip | ✅ `rw`, no errors |
| Mirroring after failback | ✅ home primary, Azure `up+replaying`, both daemons `OK` |
| Container restarted on a different home node (HA) | ✅ |

| Metric | Value |
|---|---|
| RPO, planned failover/failback | 0 (non-forced promote waits for the demotion snapshot) |
| RPO, disaster | Up to the 15-minute schedule |
| RTO | Not timed; the manual steps take a few minutes |

### Incident during the first two-way attempt

The first failback corrupted the container's filesystem (two names on one inode, root mounted `emergency_ro`). Kernel log on the home node:

```
rbd: rbd0: peer will not release lock
rbd: rbd0: write result -30
Buffer I/O error on dev rbd0, logical block 9255, lost sync page write
EXT4-fs error (device rbd0): ext4_journal_check_start:86: comm cat: Detected aborted journal
EXT4-fs (rbd0): Remounting filesystem read-only
```

The promote at home had failed (not synced yet) and HA started the container on the still non-primary image. The home `rbd-mirror` daemon, holding the image lock, kept writing replayed blocks under the mounted filesystem. The test container was rebuilt and the runbook changed to chain promote, primary check and start. The repeated test passed.

## Known limits

- The home `rbd-mirror` daemon runs on one node.
- Container configs are staged by hand; a sync script/playbook is the next step.
- Failover and failback are run by the operator; the `dr-operator` agent prepares and checks them ([phase 7](../docs/phase-7-agentic-ops.md)).
