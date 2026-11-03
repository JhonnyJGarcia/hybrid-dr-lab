# No credentials here: the provider reads ARM_CLIENT_ID / ARM_CLIENT_SECRET /
# ARM_TENANT_ID from the environment (service principal) or falls back to the
# Azure CLI session (az login).
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
