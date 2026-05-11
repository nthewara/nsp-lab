# ──────────────────────────────────────────────────────────────────────
# 40-associations: bind every in-perimeter resource to the NSP default profile
# accessMode = Learning by default; toggle scripts flip to Enforced.
# ──────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azapi = { source = "Azure/azapi", version = "~> 2.2" }
  }
  backend "azurerm" { key = "40-associations.tfstate" }
}
provider "azapi" { subscription_id = var.subscription_id }

variable "subscription_id" { type = string }
variable "tfstate_rg" { type = string }
variable "tfstate_account" { type = string }
variable "tfstate_container" {
  type    = string
  default = "tfstate"
}
variable "access_mode" {
  type    = string
  default = "Learning"
  validation {
    condition     = contains(["Learning", "Enforced", "Audit"], var.access_mode)
    error_message = "access_mode must be Learning | Enforced | Audit"
  }
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
  nsp_id     = data.terraform_remote_state.p.outputs.nsp_id
  profile_id = data.terraform_remote_state.p.outputs.nsp_profile_id

  targets = {
    kv      = data.terraform_remote_state.r.outputs.kv_id
    storage = data.terraform_remote_state.r.outputs.st_id
    sql     = data.terraform_remote_state.r.outputs.sql_id
    aoai    = data.terraform_remote_state.r.outputs.aoai_id
    search  = data.terraform_remote_state.r.outputs.srch_id
    cosmos  = data.terraform_remote_state.r.outputs.cos_id
  }
}

resource "azapi_resource" "assoc" {
  for_each  = local.targets
  type      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name      = "${each.key}-assoc"
  parent_id = local.nsp_id
  body = {
    properties = {
      accessMode          = var.access_mode
      privateLinkResource = { id = each.value }
      profile             = { id = local.profile_id }
    }
  }
  response_export_values = ["*"]
  # Don't let TF replace on every access_mode toggle — we use scripts for that
  lifecycle {
    ignore_changes = [body.properties.accessMode]
  }
}

output "associations" {
  value = { for k, v in azapi_resource.assoc : k => v.id }
}
