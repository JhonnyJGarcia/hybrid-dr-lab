variable "subscription_id" {
  description = "Azure subscription ID (not a secret, kept out of git anyway)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "swedencentral"
}

variable "region_short" {
  description = "Short region code used in names (sdc, itn, weu)"
  type        = string
  default     = "sdc"
}

variable "owner" {
  description = "Value of the owner tag"
  type        = string
}

variable "phase" {
  description = "Lab phase that creates these resources (tag)"
  type        = string
  default     = "6"
}

variable "vnet_address_space" {
  description = "VNet address space; must not overlap any home network"
  type        = list(string)
}

variable "gateway_subnet_prefix" {
  description = "GatewaySubnet prefix for the VPN Gateway (/27 or larger)"
  type        = string
}

variable "pve_subnet_prefix" {
  description = "Subnet for the Proxmox DR node"
  type        = string
}

# ---- Phase 3: Proxmox DR node ----

variable "vm_size" {
  description = "VM size for the Proxmox node (B-series v2, Gen2)"
  type        = string
  default     = "Standard_B2as_v2"
}

variable "admin_username" {
  description = "Admin (sudo) user created on the Debian VM"
  type        = string
  default     = "jhonny"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key authorized on the VM"
  type        = string
}

variable "pve_private_ip" {
  description = "Static private IP of the Proxmox node inside snet-pve"
  type        = string
  default     = "10.50.1.10"
}

variable "accelerated_networking" {
  description = "Enable accelerated networking (set false if the apply rejects it)"
  type        = bool
  default     = false
}

variable "os_disk_size_gb" {
  description = "OS disk size (GiB)"
  type        = number
  default     = 32
}

variable "osd_disk_count" {
  description = "Number of extra disks for Ceph OSDs"
  type        = number
  default     = 2
}

variable "osd_disk_size_gb" {
  description = "Size of each Ceph OSD disk (GiB)"
  type        = number
  default     = 32
}

variable "mgmt_source_cidrs" {
  description = "Networks allowed to reach SSH/PVE/ICMP over the VPN"
  type        = list(string)
  default     = ["192.168.50.0/24", "10.50.0.0/16"]
}

variable "ceph_source_cidrs" {
  description = "Networks allowed to reach Ceph ports (home cluster, for mirroring)"
  type        = list(string)
  default     = ["192.168.50.0/24"]
}

variable "image_publisher" {
  description = "VM image publisher"
  type        = string
  default     = "Debian"
}

variable "image_offer" {
  description = "VM image offer"
  type        = string
  default     = "debian-13"
}

variable "image_sku" {
  description = "VM image SKU (Gen2 for B-series v2)"
  type        = string
  default     = "13-gen2"
}

variable "image_version" {
  description = "VM image version"
  type        = string
  default     = "latest"
}
