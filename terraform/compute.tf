# ---------------------------------------------------------------------------
# Phase 3: Proxmox DR node (single Azure VM, Debian 13 -> PVE 9 installed later)
#
# No public IP: the node is reached only over the site-to-site VPN
# (ssh -J root@<home-node> <admin>@<private-ip>). Inbound from the internet is
# denied by the NSG; only the home cluster and the Azure VNet are allowed in.
# ---------------------------------------------------------------------------

locals {
  # Phase-3 resources carry phase = "3" instead of the file-wide default.
  tags_phase3 = merge(local.tags, { phase = "3" })
}

# --- Network security group for the Proxmox subnet -------------------------
resource "azurerm_network_security_group" "pve" {
  name                = "nsg-snet-pve"
  location            = azurerm_resource_group.dr.location
  resource_group_name = azurerm_resource_group.dr.name
  tags                = local.tags_phase3
}

# SSH from management networks (home cluster + Azure VNet)
resource "azurerm_network_security_rule" "ssh" {
  name                        = "Allow-SSH"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.mgmt_source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.pve.name
}

# Proxmox web UI (8006) from management networks
resource "azurerm_network_security_rule" "pve_web" {
  name                        = "Allow-PVE-Web"
  priority                    = 1010
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8006"
  source_address_prefixes     = var.mgmt_source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.pve.name
}

# Ceph (mon 3300/6789, mgr/osd 6800-7300) from the home cluster, for RBD mirroring
resource "azurerm_network_security_rule" "ceph" {
  name                        = "Allow-Ceph"
  priority                    = 1020
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["3300", "6789", "6800-7300"]
  source_address_prefixes     = var.ceph_source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.pve.name
}

# ICMP from management networks (ping tests across the tunnel)
resource "azurerm_network_security_rule" "icmp" {
  name                        = "Allow-ICMP"
  priority                    = 1030
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Icmp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = var.mgmt_source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.pve.name
}

resource "azurerm_subnet_network_security_group_association" "pve" {
  subnet_id                 = azurerm_subnet.pve.id
  network_security_group_id = azurerm_network_security_group.pve.id
}

# --- NIC (no public IP; IP forwarding on for routed LXC traffic) -----------
resource "azurerm_network_interface" "pve" {
  name                           = "nic-vm-pve-${local.name_suffix}-01"
  location                       = azurerm_resource_group.dr.location
  resource_group_name            = azurerm_resource_group.dr.name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = var.accelerated_networking
  tags                           = local.tags_phase3

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.pve.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.pve_private_ip
  }
}

# --- The Proxmox node VM ---------------------------------------------------
resource "azurerm_linux_virtual_machine" "pve" {
  name                  = "vm-pve-${local.name_suffix}-01"
  location              = azurerm_resource_group.dr.location
  resource_group_name   = azurerm_resource_group.dr.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.pve.id]
  tags                  = local.tags_phase3

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    name                 = "disk-vm-pve-${local.name_suffix}-01-os"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }
}

# --- Extra disks for Ceph OSDs --------------------------------------------
resource "azurerm_managed_disk" "osd" {
  count                = var.osd_disk_count
  name                 = "disk-vm-pve-${local.name_suffix}-01-osd${count.index + 1}"
  location             = azurerm_resource_group.dr.location
  resource_group_name  = azurerm_resource_group.dr.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.osd_disk_size_gb
  tags                 = local.tags_phase3
}

resource "azurerm_virtual_machine_data_disk_attachment" "osd" {
  count              = var.osd_disk_count
  managed_disk_id    = azurerm_managed_disk.osd[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.pve.id
  lun                = count.index
  caching            = "None" # Ceph OSDs: no host-side caching
}
