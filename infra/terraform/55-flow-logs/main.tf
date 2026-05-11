# ──────────────────────────────────────────────────────────────────────
# 55-flow-logs: VNet flow logs + Traffic Analytics → same LAW as NSP
# ──────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.30" }
    azapi   = { source = "Azure/azapi", version = "~> 2.2" }
  }
  backend "azurerm" { key = "55-flow-logs.tfstate" }
}
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}
provider "azapi" { subscription_id = var.subscription_id }

variable "subscription_id" { type = string }
variable "tfstate_rg" { type = string }
variable "tfstate_account" { type = string }
variable "tfstate_container" {
  type    = string
  default = "tfstate"
}

data "terraform_remote_state" "p" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg
    storage_account_name = var.tfstate_account
    container_name       = var.tfstate_container
    key                  = "10-perimeter.tfstate"
    use_azuread_auth     = true
    subscription_id      = var.subscription_id
  }
}

locals {
  rg          = data.terraform_remote_state.p.outputs.rg_name
  location    = data.terraform_remote_state.p.outputs.location
  name_prefix = data.terraform_remote_state.p.outputs.name_prefix
  suffix      = data.terraform_remote_state.p.outputs.suffix
  law_id      = data.terraform_remote_state.p.outputs.law_id
  tags        = data.terraform_remote_state.p.outputs.tags
  sub         = data.terraform_remote_state.p.outputs.subscription_id
}

# Look up the existing VNet (created in 10-perimeter)
data "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.name_prefix}"
  resource_group_name = local.rg
}

# Storage for RAW flow logs (separate account so it doesn't log itself).
# Allow shared-key + public access here on purpose — Network Watcher writes via Storage SDK
# and this account is NOT in the NSP, so it isn't part of the lockdown.
resource "azurerm_storage_account" "flow" {
  name                          = substr("stflow${replace(local.name_prefix, "-", "")}${local.suffix}", 0, 24)
  resource_group_name           = local.rg
  location                      = local.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  account_kind                  = "StorageV2"
  shared_access_key_enabled     = true # required for Network Watcher writer
  public_network_access_enabled = true
  min_tls_version               = "TLS1_2"
  tags                          = local.tags
}

# Network Watcher is auto-created per-region by Azure as 'NetworkWatcherRG/NetworkWatcher_<region>'.
# Reference it by name without trying to create it; safest is a data source.
data "azapi_resource" "nw" {
  type      = "Microsoft.Network/networkWatchers@2024-05-01"
  name      = "NetworkWatcher_${local.location}"
  parent_id = "/subscriptions/${local.sub}/resourceGroups/NetworkWatcherRG"
}

# VNet flow log → enables flow capture + Traffic Analytics into the same LAW
resource "azurerm_network_watcher_flow_log" "vnet" {
  name                 = "fl-${local.name_prefix}-vnet"
  network_watcher_name = "NetworkWatcher_${local.location}"
  resource_group_name  = "NetworkWatcherRG"
  storage_account_id   = azurerm_storage_account.flow.id
  enabled              = true
  version              = 2

  target_resource_id = data.azurerm_virtual_network.vnet.id

  retention_policy {
    enabled = true
    days    = 10
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = data.terraform_remote_state.p.outputs.law_workspace_id
    workspace_region      = local.location
    workspace_resource_id = local.law_id
    interval_in_minutes   = 10
  }

  tags = local.tags
}

output "flow_storage_id" { value = azurerm_storage_account.flow.id }
output "flow_log_id" { value = azurerm_network_watcher_flow_log.vnet.id }
