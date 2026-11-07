# Phase 4: Ceph RBD mirroring

One-way, snapshot-based replication of container disks from the home Ceph cluster to the single Ceph node in Azure.

```
 HOME Ceph (pool rbd-dr, primary images)          AZURE Ceph (pool rbd-dr, non-primary images)
 ┌──────────────────────────────┐   IPsec VPN   ┌──────────────────────────────────────┐
 │ mgr rbd_support:             │ ◄──────────── │ rbd-mirror daemon (rx-only)          │
 │  takes a mirror snapshot     │  pulls diffs  │  reads home MONs/OSDs, writes local  │
 │  every 15 min                │               │                                      │
 └──────────────────────────────┘               └──────────────────────────────────────┘
```

- **Mode:** `image` on the pool, `snapshot` per image. Snapshot mode works with `krbd`, which Proxmox uses for containers.
- **Direction:** `rx-only`. Only Azure runs an `rbd-mirror` daemon; home is never written by Azure.
- **Schedule:** a mirror snapshot every 15 minutes, created on the home cluster by the `rbd_support` manager module. This interval is the worst-case RPO.
- **Same pool name on both sides** (`rbd-dr`): mirroring pairs pools by name.

## 1. Single-node Ceph on the DR node

The DR node has one host and two OSDs (two managed disks). The default CRUSH rule places replicas on different **hosts**, which a single host can never satisfy: placement groups would stay `undersized` forever. A dedicated rule spreads replicas across **OSDs** instead.

```bash
ceph osd crush rule create-replicated replicated_osd default osd
pveceph pool create rbd-dr --size 2 --min_size 1 --crush_rule replicated_osd \
  --pg_autoscale_mode on --add_storages
```

`size 2` survives the loss of one disk, not of the node. That is acceptable for a DR copy: the authoritative data stays at home.

The node has 8 GB of RAM, so the OSD memory target is lowered from the 4 GiB default:

```bash
ceph config set osd osd_memory_target 2147483648   # 2 GiB per OSD
```

## 2. Enable mirroring

Home (any cluster node):

```bash
rbd mirror pool enable rbd-dr image
rbd mirror pool peer bootstrap create --site-name home rbd-dr > /root/rbd-mirror-token
```

DR node:

```bash
apt install -y rbd-mirror
rbd mirror pool enable rbd-dr image

ceph auth get-or-create client.rbd-mirror.azure mon 'profile rbd-mirror' osd 'profile rbd' \
  -o /etc/ceph/ceph.client.rbd-mirror.azure.keyring
chown ceph:ceph /etc/ceph/ceph.client.rbd-mirror.azure.keyring

rbd mirror pool peer bootstrap import --site-name azure --direction rx-only rbd-dr /root/rbd-mirror-token
systemctl enable --now ceph-rbd-mirror@rbd-mirror.azure
```

The bootstrap token contains a cephx key for the remote site: it is deleted from both nodes after the import.

Home, per protected container disk:

```bash
rbd mirror image enable rbd-dr/vm-100-disk-0 snapshot
rbd mirror snapshot schedule add --pool rbd-dr 15m
```

## 3. Verification

```bash
rbd mirror pool status rbd-dr --verbose
```

```
health: OK
daemon health: OK
image health: OK
images: 1 total
    1 replaying
...
vm-100-disk-0:
  state:       up+replaying
  description: replaying, {"bytes_per_second":2291712.0,"last_snapshot_bytes":82829312,
               "last_snapshot_sync_seconds":38, ..., "replay_state":"idle"}
```

The first full sync of the test container (~80 MB) took 38 seconds over the VPN (~2.2 MB/s).

## Issues found and fixes

| Symptom | Cause | Fix |
|---|---|---|
| `HEALTH_WARN OSD count 2 < osd_pool_default_size 3` with every PG `active+clean` | The check is about the **default** size for new pools. `pveceph init` writes `osd_pool_default_size = 3` into `/etc/pve/ceph.conf`, and the file overrides `ceph config set` | Set `osd_pool_default_size = 2` and `osd_pool_default_min_size = 1` in `/etc/pve/ceph.conf`, restart MON and MGR |
| `ceph-rbd-mirror@….service does not exist` | The daemon is a separate package, not installed by `pveceph install` | `apt install rbd-mirror` (same Ceph release as the cluster) |
| Daemon exits: `unable to find a keyring … /etc/pve/priv/ceph.client.rbd-mirror.azure.keyring: (13) Permission denied` | Proxmox's `[client]` section points every client at `/etc/pve/priv/`, which only root can read; the daemon runs as user `ceph` | Add a `[client.rbd-mirror.azure]` section with `keyring = /etc/ceph/ceph.client.rbd-mirror.azure.keyring`; key file owned by `ceph` |
| Daemon running, but `daemon health: ERROR`, callout `unable to connect to local cluster` | `/etc/ceph/ceph.conf` is a symlink into `/etc/pve`, readable only by root and `www-data`. The daemon reads it as root at start-up, then drops to `ceph` and cannot read it when it opens the local cluster connection | `usermod -aG www-data ceph` and restart the daemon. A tighter alternative is a minimal `ceph.conf` owned by `ceph`, passed with `CEPH_CONF` in a systemd drop-in |

Connectivity to the home cluster was checked first, so it could be ruled out quickly: from the DR node, TCP 3300/6789 (MON) and 6800+ (OSD) on the home Ceph public network all answered through the VPN.

## Not replicated: guest configuration

RBD mirroring copies disks, not Proxmox configuration. The container definition (`/etc/pve/lxc/<id>.conf`) is a few lines that rarely change, and it must be edited at failover anyway (different bridge and IP). It is **not** copied into `/etc/pve/lxc/` on the DR node ahead of time: the container would then show up as startable in Azure while it still runs at home, one click away from two writers on the same disk. Failover and failback steps: [runbooks/failover-failback.md](../runbooks/failover-failback.md).
