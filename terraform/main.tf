locals {
  name_suffix = "dr-lab-${var.region_short}"

  tags = {
    project      = "dr-lab"
    owner        = var.owner
    env          = "lab"
    phase        = var.phase
    "managed-by" = "terraform"
  }
}

# Who is Terraform running as? (user via az login, or service principal)
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "dr" {
  name     = "rg-${local.name_suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "dr" {
  name                = "vnet-${local.name_suffix}"
  location            = azurerm_resource_group.dr.location
  resource_group_name = azurerm_resource_group.dr.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

# Name is fixed by Azure: the VPN Gateway only deploys into "GatewaySubnet"
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

resource "azurerm_subnet" "pve" {
  name                 = "snet-pve"
  resource_group_name  = azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = [var.pve_subnet_prefix]
}
