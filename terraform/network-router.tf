# ---------------------------------------------------------------------------
# Phase 4: route the DR LXC subnet (SDN on the Proxmox node) through the node.
#
# Home <-> 10.50.0.0/16 already works through system routes propagated by the
# VPN gateway (LNG prefix 192.168.50.0/24): nothing to add for that.
# 10.50.2.0/24 is not an Azure subnet, so Azure must be told the next hop.
# ---------------------------------------------------------------------------

locals {
  tags_phase4 = merge(local.tags, { phase = "4" })
}

resource "azurerm_route_table" "dr" {
  name                = "rt-${local.name_suffix}"
  location            = azurerm_resource_group.dr.location
  resource_group_name = azurerm_resource_group.dr.name
  tags                = local.tags_phase4

  # MUST stay true: the GatewaySubnet uses this table and needs gateway routes
  bgp_route_propagation_enabled = true

  route {
    name                   = "to-dr-lxc-via-pve"
    address_prefix         = var.dr_lxc_subnet_prefix
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.pve.private_ip_address
  }
}

# Traffic coming from home enters the VNet here: this is the association that matters
resource "azurerm_subnet_route_table_association" "gateway" {
  subnet_id      = azurerm_subnet.gateway.id
  route_table_id = azurerm_route_table.dr.id
}

# Other VMs in snet-pve (none today) also reach the LXC subnet via the node
resource "azurerm_subnet_route_table_association" "pve" {
  subnet_id      = azurerm_subnet.pve.id
  route_table_id = azurerm_route_table.dr.id
}