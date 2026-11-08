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

# ---- Phase 3: Proxmox DR node ----

output "pve_private_ip" {
  description = "Private IP of the Proxmox DR node (reach it over the VPN)"
  value       = azurerm_network_interface.pve.private_ip_address
}

output "pve_ssh_jump" {
  description = "SSH to the DR node, jumping through a home cluster node"
  value       = "ssh -J root@${var.home_jump_host} ${var.admin_username}@${azurerm_network_interface.pve.private_ip_address}"
}

output "route_table" {
  value = azurerm_route_table.dr.name
}