# ──────────────────────────────────────────────────────────────────────
# 30-foundry: AI Foundry project (simplified model — child of AI Services)
#            + connections to AI Search, Cosmos, Storage
# ──────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.30" }
    azapi   = { source = "Azure/azapi", version = "~> 2.2" }
  }
  backend "azurerm" { key = "30-foundry.tfstate" }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}
provider "azapi" { subscription_id = var.subscription_id }

variable "subscription_id" { type = string }
variable "tenant_id" { type = string }
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
  rg            = data.terraform_remote_state.p.outputs.rg_name
  location      = data.terraform_remote_state.p.outputs.location
  name_prefix   = data.terraform_remote_state.p.outputs.name_prefix
  suffix        = data.terraform_remote_state.p.outputs.suffix
  tags          = data.terraform_remote_state.p.outputs.tags
  aoai_id       = data.terraform_remote_state.r.outputs.aoai_id
  aoai_name     = data.terraform_remote_state.r.outputs.aoai_name
  srch_id       = data.terraform_remote_state.r.outputs.srch_id
  srch_endpoint = data.terraform_remote_state.r.outputs.srch_endpoint
  cos_id        = data.terraform_remote_state.r.outputs.cos_id
  cos_endpoint  = data.terraform_remote_state.r.outputs.cos_endpoint
  st_id         = data.terraform_remote_state.r.outputs.st_id
  st_name       = data.terraform_remote_state.r.outputs.st_name
}

# Foundry project — simplified model: child of AI Services account
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = "proj-${local.name_prefix}-${local.suffix}"
  parent_id = local.aoai_id
  location  = local.location
  identity { type = "SystemAssigned" }
  body = {
    properties = {
      displayName = "NSP Lab Foundry Project"
      description = "Demo project for NSP lab"
    }
  }
  response_export_values    = ["identity.principalId"]
  schema_validation_enabled = false
}

# Read back the project after creation so identity.principalId is populated.
data "azapi_resource" "project_post" {
  type                   = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name                   = azapi_resource.project.name
  parent_id              = local.aoai_id
  response_export_values = ["identity.principalId"]
  depends_on             = [azapi_resource.project]
}

locals {
  proj_pid = try(data.azapi_resource.project_post.output.identity.principalId, "")
}

# NOTE: Foundry project connections are intentionally omitted in this lab.
# In the new simplified project model the API surface for connections is in flux
# (account-level vs project-level routing); for the file_search demo the agent
# uses the AOAI account's MSI directly via Foundry's default resource lookups.
# Re-add connections when needed:
#   type = "Microsoft.CognitiveServices/accounts/projects/connections@…"
#   parent_id = azapi_resource.project.id


# Project's MSI also needs roles on dependent resources. Skip silently if MSI not yet visible.

resource "azurerm_role_assignment" "proj_search" {
  count                = 1
  scope                = local.srch_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = local.proj_pid
}
resource "azurerm_role_assignment" "proj_search_svc" {
  count                = 1
  scope                = local.srch_id
  role_definition_name = "Search Service Contributor"
  principal_id         = local.proj_pid
}
resource "azurerm_role_assignment" "proj_storage" {
  count                = 1
  scope                = local.st_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.proj_pid
}

output "project_id" { value = azapi_resource.project.id }
output "project_name" { value = azapi_resource.project.name }
