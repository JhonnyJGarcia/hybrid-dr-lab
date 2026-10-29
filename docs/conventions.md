# Conventions

## Naming

Based on the Microsoft Cloud Adoption Framework: `<type>-<workload>-<env>-<region>[-<nn>]`

- workload: `glpi`
- env: `lab`
- region: `weu` (West Europe) or `itn` (Italy North)

| Resource | Abbreviation | Example |
|---|---|---|
| Resource group | `rg` | `rg-glpi-lab-weu` |
| Virtual network | `vnet` | `vnet-glpi-lab-weu` |
| Subnet | `snet` | `snet-app`, `snet-data` |
| Network security group | `nsg` | `nsg-snet-app` |
| Virtual machine | `vm` | `vm-glpi-lab-weu-01` |
| Network interface | `nic` | `nic-vm-glpi-lab-weu-01` |
| MySQL Flexible Server | `mysql` | `mysql-glpi-lab-weu` |
| Key Vault | `kv` | `kv-glpi-lab-weu-<suffix>` (globally unique, max 24 chars) |
| Log Analytics workspace | `log` | `log-glpi-lab-weu` |
| Recovery Services vault | `rsv` | `rsv-glpi-lab-weu` |
| Bastion | `bas` | `bas-glpi-lab-weu` |
| Managed identity | `id` | `id-glpi-lab-weu` |

## Tags

Every resource carries these tags (enforced by Azure Policy in phase 0):

| Tag | Values | Purpose |
|---|---|---|
| `project` | `glpi-lab` | group all lab costs in Cost Analysis |
| `owner` | name | who to ask |
| `env` | `lab` | environment |
| `phase` | `1`–`8` | which phase created it, for cost per phase |
| `managed-by` | `portal` / `terraform` | how the resource was created |

## Publishing rules

- No public IPs, subscription or tenant IDs, keys or secrets in the repo
- Screenshots are checked and redacted before commit
- `*.tfvars`, state files and Ansible vaults are gitignored; only `.example` files are committed
