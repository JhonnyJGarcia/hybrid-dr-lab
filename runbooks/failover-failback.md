# Runbook: failover to Azure and failback to home

Applies to containers whose disk is mirrored to the DR node ([phase 4](../docs/phase-4-rbd-mirroring.md)). Example: container `100`, disk `rbd-dr/vm-100-disk-0`.

## Networking on the DR side

Failed-over containers do not keep their home address. They live in the Proxmox SDN **simple zone** `drzone` on the DR node:

| Item | Value |
|---|---|
| Subnet | `10.50.2.0/24`, gateway `10.50.2.1` (the DR node) |
| Internet egress | SNAT to the node's private IP, then Azure default outbound |
| Reachability from home | Azure route table `rt-dr-lab-sdc`: `10.50.2.0/24` → DR node, attached to `GatewaySubnet` and `snet-pve` (NIC IP forwarding enabled) |

Reusing the home subnet in Azure was rejected: a connected route to the home network on the DR node would capture traffic to the home Ceph MONs and break mirroring.

## Failover (planned test)

**Home**

```bash
ha-manager remove ct:100                       # otherwise HA restarts it at home
rbd mirror image snapshot rbd-dr/vm-100-disk-0 # final sync, RPO ≈ 0 for a planned failover
pct shutdown 100
```

**DR node**

```bash
rbd mirror pool status rbd-dr --verbose        # wait for the last snapshot to be replayed
rbd mirror image promote --force rbd-dr/vm-100-disk-0
```

`--force` is what a real disaster requires, since the home site cannot demote its copy. In a planned test the home image can be demoted first and `--force` dropped.

Register the container, using a copy of its home config:

```bash
cp /root/dr-configs/100.conf /etc/pve/lxc/100.conf
# edit net0: bridge=<drzone vnet>, ip=10.50.2.x/24, gw=10.50.2.1
pct start 100
```

**Checks**

| Check | Result |
|---|---|
| Container starts with the replicated data | ✅ |
| DR gateway `10.50.2.1` reachable from the container | ✅ |
| Container reachable from home through the VPN | ✅ |
| DNS resolution | ✅ |
| Internet egress over TCP (HTTP request answered) | ✅ |
| `ping` to the internet | ❌ expected: Azure default outbound access does not carry ICMP for a VM without a public IP. Verified with TCP instead |

## Failback (home site recovered)

After a forced promote both copies are primary (split-brain). The mirroring is one-way, so failback keeps the **home** copy and **discards writes made in Azure** during the failover.

**DR node**

```bash
pct stop 100
mkdir -p /root/dr-configs
mv /etc/pve/lxc/100.conf /root/dr-configs/100.conf.failover   # not pct destroy: it deletes the disk
rbd mirror image demote rbd-dr/vm-100-disk-0
rbd mirror image resync rbd-dr/vm-100-disk-0
```

**Home**

```bash
pct start 100
ha-manager add ct:100
```

**Check (DR node):** `rbd mirror pool status rbd-dr --verbose` → `up+replaying`, health `OK`. Protection is back in place.

In the test, HA placed the container on a different home node than the one it left. That is expected: all home nodes share the same Ceph pool.

## Results (2026-11-07)

| Metric | Target | Measured |
|---|---|---|
| RPO, planned failover | — | 0 (forced snapshot before shutdown) |
| RPO, unplanned | ≤ 15 min | Bounded by the 15-minute snapshot schedule |
| RTO | ≤ 30 min | _to be timed_ |

## Known limits and next steps

- **Failback loses Azure-side writes.** Keeping them needs mirroring in the reverse direction (an `rbd-mirror` daemon at home, two-way peer), resync home from Azure, then switch back.
- **Manual steps.** Copying configs to a staging folder (`/root/dr-configs`, outside `/etc/pve`) and the failover sequence will become a script/playbook, then an approval-gated task for the agentic layer (phase 7).
- The test container runs a very old Alpine release whose `wget` lacks HTTPS; replace it with a current release for future tests.
