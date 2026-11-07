# Phase 4: Ceph RBD mirroring

Two-way, snapshot-based replication of container disks between the home Ceph cluster and the single Ceph node in Azure. It was built one-way first (home → Azure), then extended to two-way so that failback keeps the data written in Azure.

```
 HOME Ceph (pool rbd-dr)                              AZURE Ceph (pool rbd-dr)
 ┌────────────────────────────────┐   IPsec VPN   ┌────────────────────────────────┐
 │ rbd-mirror daemon (on 1 node)  │ ◄───────────► │ rbd-mirror daemon              │
 │  pulls from Azure when Azure   │               │  pulls from home when home     │
 │  is primary                    │               │  is primary                    │
 │ mgr rbd_support: mirror        │               │ mgr rbd_support: mirror        │
 │  snapshot every 15 min for     │               │  snapshot every 15 min for     │
 │  images primary here           │               │  images primary here           │
 └────────────────────────────────┘               └────────────────────────────────┘
```

## How it works

- Each mirrored image is **primary** on exactly one site (writable) and **non-primary** on the other (read-only replica).
- The site where the image is primary takes a **mirror snapshot** on a schedule (`rbd_support` manager module). The interval, 15 minutes, is the worst-case RPO for an unplanned failover.
- The `rbd-mirror` daemon on the **other** site connects to the primary cluster, reads the difference between the last two mirror snapshots and writes it into its local non-primary copy. The daemon always runs on the receiving side and **pulls**.
- Moving the primary role: `demote` on the active site (it takes a final mirror snapshot), wait for the other site to replay it, `promote` there. No `--force`, no data loss. `promote --force` is only for a disaster, when the active site cannot be demoted.
- **Mode:** `image` on the pool, `snapshot` per image. Snapshot mode works with `krbd`, which Proxmox uses for containers; journal-based mode needs `librbd`.
- **Same pool name on both sides** (`rbd-dr`): mirroring pairs pools by name.

### Peer direction

Each site has a **peer** entry describing the other site, with a direction:

| Direction | Meaning | Needs |
|---|---|---|
| `rx` | My daemon pulls **from** that peer | The peer's MON addresses and a cephx key for it |
| `tx` | That peer pulls **from me**: when I am primary, my mirror snapshots must track it | Nothing: it is the peer that connects |
| `rx-tx` | Both: required on **both** sites for two-way | |

## 1. Single-node Ceph on the DR node

The DR node has one host and two OSDs (two managed disks). The default CRUSH rule places replicas on different **hosts**, which a single host can never satisfy: placement groups would stay `undersized` forever. A dedicated rule spreads replicas across **OSDs** instead.

```bash
ceph osd crush rule create-replicated replicated_osd default osd
pveceph pool create rbd-dr --size 2 --min_size 1 --crush_rule replicated_osd \
  --pg_autoscale_mode on --add_storages
ceph osd pool set .mgr crush_rule replicated_osd     # the manager's own pool, see issues
```

`size 2` survives the loss of one disk, not of the node. That is acceptable for a DR copy: the authoritative data stays at home.

The node has 8 GB of RAM, so the OSD memory target is lowered from the 4 GiB default:

```bash
ceph config set osd osd_memory_target 2147483648   # 2 GiB per OSD
```

## 2. The rbd-mirror daemon on each site

The same steps on the DR node and on **one** home node. `<site>` is `azure` or `home`; `<fsid>` and `<mons>` are the **local** cluster's (`ceph fsid`, `mon_host` in `/etc/pve/ceph.conf`).

```bash
apt install -y rbd-mirror      # same Ceph release as the cluster

# Dedicated cephx user for the daemon
ceph auth get-or-create client.rbd-mirror.<site> mon 'profile rbd-mirror' osd 'profile rbd' \
  -o /etc/ceph/ceph.client.rbd-mirror.<site>.keyring
chown ceph:ceph /etc/ceph/ceph.client.rbd-mirror.<site>.keyring

# Minimal config the daemon can read as user ceph (see issues: /etc/pve is not readable)
cat > /etc/ceph/rbd-mirror.conf <<EOF
[global]
	fsid = <fsid>
	mon_host = <mons>

[client.rbd-mirror.<site>]
	keyring = /etc/ceph/ceph.client.rbd-mirror.<site>.keyring
EOF
chown ceph:ceph /etc/ceph/rbd-mirror.conf && chmod 640 /etc/ceph/rbd-mirror.conf

mkdir -p /etc/systemd/system/ceph-rbd-mirror@.service.d
cat > /etc/systemd/system/ceph-rbd-mirror@.service.d/conf.conf <<'EOF'
[Service]
Environment=CEPH_CONF=/etc/ceph/rbd-mirror.conf
EOF
systemctl daemon-reload
systemctl enable --now ceph-rbd-mirror@rbd-mirror.<site>
```

The home daemon runs on one node only: if that node is down, home cannot receive from Azure. Acceptable for the lab, noted as a limit.

## 3. Peering the two sites

Enable mirroring on the pool on both sites, then exchange a bootstrap token:

```bash
# both sites
rbd mirror pool enable rbd-dr image

# home: create a token (contains MON addresses and a cephx key for client.rbd-mirror-peer)
rbd mirror pool peer bootstrap create --site-name home rbd-dr > /root/token-home

# azure: import it
rbd mirror pool peer bootstrap import --site-name azure --direction rx-tx rbd-dr /root/token-home
```

Then make sure **both** peers are `rx-tx` and the home peer has the credentials to reach Azure (see issues: the import does not always set this):

```bash
# azure: credentials home will use
rbd mirror pool peer bootstrap create --site-name azure rbd-dr > /dev/null   # creates client.rbd-mirror-peer
ceph auth get-key client.rbd-mirror-peer

# home: complete the peer entry for azure
rbd mirror pool peer set rbd-dr <peer-uuid> client client.rbd-mirror-peer
rbd mirror pool peer set rbd-dr <peer-uuid> mon-host <azure-mon-ip>
rbd mirror pool peer set rbd-dr <peer-uuid> key-file /root/azure-peer.key
rbd mirror pool peer set rbd-dr <peer-uuid> direction rx-tx

rbd mirror pool info rbd-dr --all     # on both sites: peer direction rx-tx, client and mon host set
```

Tokens and key files contain secrets: delete them after use (the key is stored in the cluster's config-key store).

Mirror snapshot schedule, on **both** sites (each site snapshots the images that are primary there):

```bash
rbd mirror snapshot schedule add --pool rbd-dr 15m
```

Per protected container disk, on the site where it is primary:

```bash
rbd mirror image enable rbd-dr/vm-101-disk-0 snapshot
```

## 4. Verification

```bash
rbd mirror pool status rbd-dr --verbose
```

On the site where the image is primary: `up+stopped`, *local image is primary*. On the other site: `up+replaying`, with `local_snapshot_timestamp` equal to `remote_snapshot_timestamp` once caught up. Daemon health `OK` on both.

The first full sync of a test container (~80 MB) took 38 seconds over the VPN (~2.2 MB/s).

## Issues found and fixes

| Symptom | Cause | Fix |
|---|---|---|
| `HEALTH_WARN OSD count 2 < osd_pool_default_size 3` with every PG `active+clean` | The check is about the **default** size for new pools. `pveceph init` writes `osd_pool_default_size = 3` into `/etc/pve/ceph.conf`, and the file overrides `ceph config set` | Set `osd_pool_default_size = 2` and `osd_pool_default_min_size = 1` in `/etc/pve/ceph.conf`, restart MON and MGR |
| `HEALTH_WARN` with 1 PG `undersized`, hours after the pool was healthy | The `.mgr` pool, created by the manager on its own, uses the default CRUSH rule (replicas on different hosts) | `ceph osd pool set .mgr crush_rule replicated_osd`. Found by the health-checker agent ([phase 7](phase-7-agentic-ops.md)) |
| `ceph-rbd-mirror@….service does not exist` | The daemon is a separate package, not installed by `pveceph install` | `apt install rbd-mirror` |
| Daemon exits: `unable to find a keyring … /etc/pve/priv/ceph.client.rbd-mirror.<site>.keyring: (13) Permission denied` | Proxmox's `[client]` section points every client at `/etc/pve/priv/`, readable only by root; the daemon runs as user `ceph` | Keyring in `/etc/ceph/`, owned by `ceph`, named in a `[client.rbd-mirror.<site>]` section |
| Daemon running, but `daemon health: ERROR`, callout `unable to connect to local cluster` | `/etc/ceph/ceph.conf` is a symlink into `/etc/pve` (`root:www-data`, mode 640). The daemon starts as root, then drops to `ceph` and cannot read it when it opens the local cluster connection | A minimal config owned by `ceph`, passed with `CEPH_CONF` in a systemd drop-in (step 2) |
| Adding `ceph` to the `www-data` group does **not** fix the previous row | The daemon switches user with `--setuser ceph --setgroup ceph`, which sets uid and primary gid and **drops supplementary groups**: `/proc/<pid>/status` shows an empty `Groups:` line | Do not rely on group membership; use the dedicated config. Remove `ceph` from `www-data` again (least privilege) |
| After `bootstrap import` on home, its `azure` peer is still `tx-only` with no MON host; home daemon in `WARNING` | Home already had a peer entry for Azure (added automatically when Azure imported home's token). The import did not update the existing entry | Set client, MON host, key and direction with `rbd mirror pool peer set` |
| Two-way needs `rx-tx` on **both** peers | With `rx-only` on Azure, Azure does not track home as a destination of its own mirror snapshots when it becomes primary | `rbd mirror pool peer set rbd-dr <uuid> direction rx-tx` on both sites |
| **Container filesystem corrupted after failback**: two file names pointing to the same inode, root filesystem remounted `emergency_ro` | The container was started at home while the image was still **non-primary**. The kernel log shows `rbd0: write result -30` (read-only) and `peer will not release lock`: the local `rbd-mirror` daemon held the image's exclusive lock and kept writing replayed blocks under the mounted filesystem. The promote had failed (image not yet synced) and the next command started the container anyway | **Proxmox and krbd do not stop you** from starting a guest on a non-primary image. Promote, check and start are always one chained command: `rbd mirror image promote … && rbd info … \| grep -q 'mirroring primary: true' && <start>` ([runbook](../runbooks/failover-failback.md)) |

Connectivity was checked before any of this: from each site, TCP 3300/6789 (MON) and 6800+ (OSD) of the other site's Ceph public network must answer through the VPN.

## Not replicated: guest configuration

RBD mirroring copies disks, not Proxmox configuration. The container definition (`/etc/pve/lxc/<id>.conf`) is a few lines that rarely change, and it must be edited at failover anyway (different bridge and IP). It is kept in a staging folder on the DR node (`/root/dr-configs/`), **not** in `/etc/pve/lxc/`: there the container would show up as startable in Azure while it still runs at home. Failover and failback steps: [runbooks/failover-failback.md](../runbooks/failover-failback.md).
