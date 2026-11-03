output "running_as_client_id" {
  description = "Client ID Terraform authenticated with (matches the SP appId when using tf-sp)"
  value       = data.azurerm_client_config.current.client_id
}

output "resource_group" {
  value = azurerm_resource_group.dr.name
}

output "vnet" {
  value = azurerm_virtual_network.dr.name
}

output "subnets" {
  value = {
    gateway = azurerm_subnet.gateway.name
    pve     = azurerm_subnet.pve.name
  }
}
