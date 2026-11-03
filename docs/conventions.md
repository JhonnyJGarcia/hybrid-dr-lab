# Conventions

## Naming

Based on the Microsoft Cloud Adoption Framework: `<type>-<workload>-<env>-<region>[-<nn>]`

- workload: `dr`
- env: `lab`
- region: `weu` (West Europe) or `itn` (Italy North)

| Resource | Abbreviation | Example |
|---|---|---|
| Resource group | `rg` | `rg-dr-lab-weu` |
| Virtual network | `vnet` | `vnet-dr-lab-weu` |
| Subnet | `snet` | `GatewaySubnet`, `snet-pve`, `snet-guests` |
| Network security group | `nsg` | `nsg-snet-pve` |
| Route table | `rt` | `rt-snet-guests` |
| Virtual machine | `vm` | `vm-pve-dr-lab-weu-01` |
| Network interface | `nic` | `nic-vm-pve-dr-lab-weu-01` |
| Managed disk | `disk` | `disk-vm-pve-dr-lab-weu-01-osd1` |
| Public IP (VPN Gateway only) | `pip` | `pip-vpng-dr-lab-weu` |
| Virtual network gateway | `vpng` | `vpng-dr-lab-weu` |
| Local network gateway | `lgw` | `lgw-home` |
| VPN connection | `con` | `con-home-to-weu` |
| Key Vault | `kv` | `kv-dr-lab-weu-<suffix>` (globally unique, max 24 chars) |
| Log Analytics workspace | `log` | `log-dr-lab-weu` |

Home side (nested cluster): nodes `pve-hci-01`…`03`, cluster `hci-lab`; Azure node `pve-dr-01`.

## Tags

Every Azure resource carries these tags (enforced by Azure Policy in phase 0):

| Tag | Values | Purpose |
|---|---|---|
| `project` | `dr-lab` | group all lab costs in Cost Analysis |
| `owner` | name | who to ask |
| `env` | `lab` | environment |
| `phase` | `0`–`8` | which phase created it, for cost per phase |
| `managed-by` | `portal` / `terraform` | how the resource was created |

## Publishing rules

- No public IPs, private addressing plans, hostnames of the real homelab, subscription or tenant IDs, keys or secrets in the repo
- VPN pre-shared keys and Ceph keyrings never leave the hosts and Key Vault
- Screenshots are checked and redacted before commit
- `*.tfvars`, state files and Ansible vaults are gitignored; only `.example` files are committed
