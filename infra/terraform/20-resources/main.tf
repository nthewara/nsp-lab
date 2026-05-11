# ──────────────────────────────────────────────────────────────────────
# 20-resources: KV, Storage, Azure SQL, AI Services + gpt-4o-mini, AI Search, Cosmos
# All MI-only (no keys). All keep publicNetworkAccess=Enabled — NSP layers on top.
# ──────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.30" }
    azapi   = { source = "Azure/azapi", version = "~> 2.2" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
  backend "azurerm" { key = "20-resources.tfstate" }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id                 = var.subscription_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"
}
provider "azapi" { subscription_id = var.subscription_id }
provider "azuread" { tenant_id = var.tenant_id }

# ─── variables ─────────────────────────────────────────────────────────
variable "subscription_id" { type = string }
variable "tenant_id" { type = string }
variable "aoai_model_capacity" {
  type    = number
  default = 30
}

# ─── consume 10-perimeter outputs via remote state ─────────────────────
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

variable "tfstate_rg" { type = string }
variable "tfstate_account" { type = string }
variable "tfstate_container" {
  type    = string
  default = "tfstate"
}

locals {
  rg          = data.terraform_remote_state.p.outputs.rg_name
  location    = data.terraform_remote_state.p.outputs.location
  name_prefix = data.terraform_remote_state.p.outputs.name_prefix
  suffix      = data.terraform_remote_state.p.outputs.suffix
  uami_pid    = data.terraform_remote_state.p.outputs.uami_principal_id
  uami_id     = data.terraform_remote_state.p.outputs.uami_id
  tags        = data.terraform_remote_state.p.outputs.tags
  agent_pid   = data.azurerm_client_config.current.object_id
}

data "azurerm_client_config" "current" {}
data "azuread_client_config" "ad" {}

# ─── Key Vault ─────────────────────────────────────────────────────────
resource "azurerm_key_vault" "kv" {
  name                          = substr("kv-${local.name_prefix}-${local.suffix}", 0, 24)
  resource_group_name           = local.rg
  location                      = local.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  tags                          = local.tags
}
resource "azurerm_role_assignment" "kv_secrets_user_uami" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.uami_pid
}
resource "azurerm_role_assignment" "kv_crypto_user_uami" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = local.uami_pid
}
resource "azurerm_role_assignment" "kv_secrets_officer_agent" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = local.agent_pid
}

# ─── Storage ───────────────────────────────────────────────────────────
resource "azurerm_storage_account" "st" {
  name                            = substr("st${replace(local.name_prefix, "-", "")}${local.suffix}", 0, 24)
  resource_group_name             = local.rg
  location                        = local.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = true
  min_tls_version                 = "TLS1_2"
  tags                            = local.tags
}
resource "azurerm_role_assignment" "st_blob_contrib_uami" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.uami_pid
}
resource "azurerm_role_assignment" "st_blob_contrib_agent" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.agent_pid
}

# ─── Azure SQL (Entra-only) ────────────────────────────────────────────
data "azuread_service_principal" "agent" {
  client_id = data.azurerm_client_config.current.client_id
}
resource "azurerm_mssql_server" "sql" {
  name                          = "sql-${local.name_prefix}-${local.suffix}"
  resource_group_name           = local.rg
  location                      = local.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  azuread_administrator {
    azuread_authentication_only = true
    login_username              = data.azuread_service_principal.agent.display_name
    object_id                   = data.azuread_service_principal.agent.object_id
    tenant_id                   = var.tenant_id
  }
  tags = local.tags
}
resource "azurerm_mssql_database" "db" {
  name        = "db-nsp-lab"
  server_id   = azurerm_mssql_server.sql.id
  sku_name    = "Basic"
  max_size_gb = 2
  tags        = local.tags
}

# ─── AI Services (multi-service) + gpt-4o-mini ─────────────────────────
resource "azurerm_cognitive_account" "aoai" {
  name                          = "aoai-${local.name_prefix}-${local.suffix}"
  resource_group_name           = local.rg
  location                      = local.location
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = "aoai-${local.name_prefix}-${local.suffix}"
  public_network_access_enabled = true
  local_auth_enabled            = false
  identity { type = "SystemAssigned" }
  tags = local.tags
}
resource "azurerm_cognitive_deployment" "gpt4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.aoai.id
  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = "2024-07-18"
  }
  sku {
    name     = "GlobalStandard"
    capacity = var.aoai_model_capacity
  }
}
resource "azurerm_role_assignment" "aoai_user_uami" {
  scope                = azurerm_cognitive_account.aoai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = local.uami_pid
}
resource "azurerm_role_assignment" "aoai_user_agent" {
  scope                = azurerm_cognitive_account.aoai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = local.agent_pid
}
resource "azurerm_role_assignment" "aoai_contrib_agent" {
  scope                = azurerm_cognitive_account.aoai.id
  role_definition_name = "Cognitive Services Contributor"
  principal_id         = local.agent_pid
}

# ─── AI Search ─────────────────────────────────────────────────────────
resource "azurerm_search_service" "srch" {
  name                          = "srch-${local.name_prefix}-${local.suffix}"
  resource_group_name           = local.rg
  location                      = local.location
  sku                           = "basic"
  local_authentication_enabled  = false
  authentication_failure_mode   = "http403"
  public_network_access_enabled = true
  identity { type = "SystemAssigned" }
  tags = local.tags
}
resource "azurerm_role_assignment" "srch_svc_contrib_uami" {
  scope                = azurerm_search_service.srch.id
  role_definition_name = "Search Service Contributor"
  principal_id         = local.uami_pid
}
resource "azurerm_role_assignment" "srch_index_contrib_uami" {
  scope                = azurerm_search_service.srch.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = local.uami_pid
}

# ─── Cosmos DB (Serverless, SQL API) ───────────────────────────────────
resource "azurerm_cosmosdb_account" "cos" {
  name                = "cos-${local.name_prefix}-${local.suffix}"
  resource_group_name = local.rg
  location            = local.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  capabilities { name = "EnableServerless" }
  consistency_policy { consistency_level = "Session" }
  geo_location {
    location          = local.location
    failover_priority = 0
  }
  public_network_access_enabled = true
  local_authentication_disabled = true
  tags                          = local.tags
}
resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "nsplab"
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.cos.name
}
# Cosmos data-plane RBAC: Built-in Data Contributor at db scope
resource "azurerm_cosmosdb_sql_role_assignment" "cos_contrib_uami" {
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.cos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = local.uami_pid
  scope               = azurerm_cosmosdb_account.cos.id
}
resource "azurerm_cosmosdb_sql_role_assignment" "cos_contrib_agent" {
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.cos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = local.agent_pid
  scope               = azurerm_cosmosdb_account.cos.id
}

# ─── outputs ───────────────────────────────────────────────────────────
output "kv_id" { value = azurerm_key_vault.kv.id }
output "kv_name" { value = azurerm_key_vault.kv.name }
output "kv_uri" { value = azurerm_key_vault.kv.vault_uri }
output "st_id" { value = azurerm_storage_account.st.id }
output "st_name" { value = azurerm_storage_account.st.name }
output "sql_id" { value = azurerm_mssql_server.sql.id }
output "sql_server_fqdn" { value = azurerm_mssql_server.sql.fully_qualified_domain_name }
output "sql_db_id" { value = azurerm_mssql_database.db.id }
output "sql_db_name" { value = azurerm_mssql_database.db.name }
output "sql_admin_login" { value = data.azuread_service_principal.agent.display_name }
output "aoai_id" { value = azurerm_cognitive_account.aoai.id }
output "aoai_name" { value = azurerm_cognitive_account.aoai.name }
output "aoai_endpoint" { value = azurerm_cognitive_account.aoai.endpoint }
output "aoai_model_deployment" { value = azurerm_cognitive_deployment.gpt4o_mini.name }
output "srch_id" { value = azurerm_search_service.srch.id }
output "srch_name" { value = azurerm_search_service.srch.name }
output "srch_endpoint" { value = "https://${azurerm_search_service.srch.name}.search.windows.net" }
output "cos_id" { value = azurerm_cosmosdb_account.cos.id }
output "cos_name" { value = azurerm_cosmosdb_account.cos.name }
output "cos_endpoint" { value = azurerm_cosmosdb_account.cos.endpoint }
output "cos_db_name" { value = azurerm_cosmosdb_sql_database.db.name }
