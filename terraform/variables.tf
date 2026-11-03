variable "subscription_id" {
  description = "Azure subscription ID (not a secret, kept out of git anyway)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}

variable "region_short" {
  description = "Short region code used in names (weu, itn)"
  type        = string
  default     = "weu"
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
