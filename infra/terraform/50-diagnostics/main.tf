# ──────────────────────────────────────────────────────────────────────
# 50-diagnostics: send NSP diag categories + native categories → LAW
# on every in-perimeter resource and on the NSP itself.
# ──────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.30" }
  }
  backend "azurerm" { key = "50-diagnostics.tfstate" }
}
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}

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
data "terraform_remote_state" "r" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg
    storage_account_name = var.tfstate_account
    container_name       = var.tfstate_container
    key                  = "20-resources.tfstate"
    use_azuread_auth     = true
    subscription_id      = var.subscription_id
  }
}

locals {
  law_id = data.terraform_remote_state.p.outputs.law_id
  nsp_id = data.terraform_remote_state.p.outputs.nsp_id
  kv_id  = data.terraform_remote_state.r.outputs.kv_id
  st_id  = data.terraform_remote_state.r.outputs.st_id
  sql_db = data.terraform_remote_state.r.outputs.sql_db_id
  aoai   = data.terraform_remote_state.r.outputs.aoai_id
  srch   = data.terraform_remote_state.r.outputs.srch_id
  cos    = data.terraform_remote_state.r.outputs.cos_id

  nsp_cats = [
    "NspPublicInboundPerimeterRulesAllowed",
    "NspPublicInboundPerimeterRulesDenied",
    "NspPublicOutboundPerimeterRulesAllowed",
    "NspPublicOutboundPerimeterRulesDenied",
    "NspCrossPerimeterInboundAllowed",
    "NspCrossPerimeterOutboundAllowed",
    "NspPrivateInboundAllowed",
    "NspOutboundAttempt",
  ]
}

# NSP itself
resource "azurerm_monitor_diagnostic_setting" "nsp" {
  name                       = "to-law"
  target_resource_id         = local.nsp_id
  log_analytics_workspace_id = local.law_id
  dynamic "enabled_log" {
    for_each = toset(local.nsp_cats)
    content { category = enabled_log.value }
  }
}

# Common helper module: every resource gets a "to-law" diag setting
# We use a flat list here for readability; metrics omitted for cost.

# Key Vault
resource "azurerm_monitor_diagnostic_setting" "kv" {
  name                       = "to-law"
  target_resource_id         = local.kv_id
  log_analytics_workspace_id = local.law_id
  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }
}

# Storage — diag settings are *per service*; we cover blob since that's what Foundry uses
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "to-law"
  target_resource_id         = "${local.st_id}/blobServices/default"
  log_analytics_workspace_id = local.law_id
  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
}

# SQL — diag setting on the DATABASE, not server
resource "azurerm_monitor_diagnostic_setting" "sql_db" {
  name                       = "to-law"
  target_resource_id         = local.sql_db
  log_analytics_workspace_id = local.law_id
  enabled_log { category_group = "audit" }
  enabled_log { category_group = "allLogs" }
}

# AI Services
resource "azurerm_monitor_diagnostic_setting" "aoai" {
  name                       = "to-law"
  target_resource_id         = local.aoai
  log_analytics_workspace_id = local.law_id
  enabled_log { category = "Audit" }
  enabled_log { category = "RequestResponse" }
}

# AI Search
resource "azurerm_monitor_diagnostic_setting" "srch" {
  name                       = "to-law"
  target_resource_id         = local.srch
  log_analytics_workspace_id = local.law_id
  enabled_log { category = "OperationLogs" }
}

# Cosmos
resource "azurerm_monitor_diagnostic_setting" "cos" {
  name                       = "to-law"
  target_resource_id         = local.cos
  log_analytics_workspace_id = local.law_id
  enabled_log { category = "DataPlaneRequests" }
  enabled_log { category = "ControlPlaneRequests" }
}
