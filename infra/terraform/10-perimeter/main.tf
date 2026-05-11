# ──────────────────────────────────────────────────────────────────────
# 10-perimeter: RG + LAW + UAMI + VNet + Jump VM + NSP (with default profile)
# ──────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.30" }
    azapi   = { source = "Azure/azapi", version = "~> 2.2" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
  backend "azurerm" {
    key = "10-perimeter.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription_id
}
provider "azapi" {
  subscription_id = var.subscription_id
}

# ─── variables ──────────────────────────────────────────────────────────
variable "subscription_id" { type = string }
variable "tenant_id" { type = string }
variable "location" {
  type    = string
  default = "australiaeast"
}
variable "name_prefix" {
  type    = string
  default = "nsp-lab"
}
variable "allowed_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
variable "vm_admin_user" {
  type    = string
  default = "labadmin"
}
variable "vm_ssh_public_key" {
  type        = string
  description = "OpenSSH public key for the jump VM admin user"
}
variable "tags" {
  type    = map(string)
  default = { lab = "nsp-lab", managed_by = "terraform" }
}

# ─── helpers ────────────────────────────────────────────────────────────
resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
  numeric = true
}

locals {
  suffix = random_string.suffix.result
  rg     = "rg-${var.name_prefix}-${local.suffix}"
}

data "azurerm_client_config" "current" {}

# ─── RG ─────────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = local.rg
  location = var.location
  tags     = var.tags
}

# ─── LAW ────────────────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.name_prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ─── UAMI ───────────────────────────────────────────────────────────────
resource "azurerm_user_assigned_identity" "uami" {
  name                = "uami-${var.name_prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = var.tags
}

# ─── VNet + Jump VM ─────────────────────────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.name_prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.50.0.0/16"]
  tags                = var.tags
}
resource "azurerm_subnet" "snet_jump" {
  name                 = "snet-jump"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.1.0/24"]
}
resource "azurerm_network_security_group" "nsg_jump" {
  name                = "nsg-${var.name_prefix}-jump"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }
  tags = var.tags
}
resource "azurerm_subnet_network_security_group_association" "nsg_attach" {
  subnet_id                 = azurerm_subnet.snet_jump.id
  network_security_group_id = azurerm_network_security_group.nsg_jump.id
}
resource "azurerm_public_ip" "pip_jump" {
  name                = "pip-${var.name_prefix}-jump"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
resource "azurerm_network_interface" "nic_jump" {
  name                = "nic-${var.name_prefix}-jump"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.snet_jump.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_jump.id
  }
  tags = var.tags
}
resource "azurerm_linux_virtual_machine" "jump" {
  name                            = "vm-${var.name_prefix}-jump"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B2s"
  admin_username                  = var.vm_admin_user
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nic_jump.id]
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uami.id]
  }
  admin_ssh_key {
    username   = var.vm_admin_user
    public_key = var.vm_ssh_public_key
  }
  os_disk {
    name                 = "osd-${var.name_prefix}-jump"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - curl
      - jq
      - unzip
      - ca-certificates
      - apt-transport-https
      - gnupg
      - python3
      - python3-pip
      - python3-venv
    runcmd:
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
      - curl -sLO https://packages.microsoft.com/keys/microsoft.asc && install -D -m 0644 microsoft.asc /etc/apt/trusted.gpg.d/microsoft.asc
      - curl -sLO https://packages.microsoft.com/config/ubuntu/24.04/prod.list && mv prod.list /etc/apt/sources.list.d/mssql-release.list
      - ACCEPT_EULA=Y apt-get update && ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev
      - ln -sf /opt/mssql-tools18/bin/sqlcmd /usr/local/bin/sqlcmd
  CLOUDINIT
  )
  tags = var.tags
}

# ─── NSP itself ─────────────────────────────────────────────────────────
resource "azapi_resource" "nsp" {
  type      = "Microsoft.Network/networkSecurityPerimeters@2024-07-01"
  name      = "nsp-${var.name_prefix}-perimeter"
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  tags      = var.tags
  body = {
    properties = {}
  }
  response_export_values = ["*"]
}

resource "azapi_resource" "nsp_profile" {
  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "default"
  parent_id = azapi_resource.nsp.id
  body = {
    properties = {}
  }
  response_export_values = ["*"]
}

resource "azapi_resource" "rule_inbound_sub" {
  type      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name      = "allow-sub-inbound"
  parent_id = azapi_resource.nsp_profile.id
  body = {
    properties = {
      direction     = "Inbound"
      subscriptions = [{ id = "/subscriptions/${var.subscription_id}" }]
    }
  }
}

# Outbound rule omitted: same-perimeter outbound is allowed by default,
# and outbound rules require fqdns/emails/phones (not 'subscriptions').
# To allow outbound to specific public FQDNs (e.g. api.openai.com), add an
# azapi_resource with direction=Outbound + fullyQualifiedDomainNames=[...]


# ─── outputs ────────────────────────────────────────────────────────────
output "rg_name" { value = azurerm_resource_group.rg.name }
output "location" { value = azurerm_resource_group.rg.location }
output "law_id" { value = azurerm_log_analytics_workspace.law.id }
output "law_name" { value = azurerm_log_analytics_workspace.law.name }
output "law_workspace_id" { value = azurerm_log_analytics_workspace.law.workspace_id }
output "uami_id" { value = azurerm_user_assigned_identity.uami.id }
output "uami_principal_id" { value = azurerm_user_assigned_identity.uami.principal_id }
output "uami_client_id" { value = azurerm_user_assigned_identity.uami.client_id }
output "uami_name" { value = azurerm_user_assigned_identity.uami.name }
output "nsp_id" { value = azapi_resource.nsp.id }
output "nsp_name" { value = azapi_resource.nsp.name }
output "nsp_profile_id" { value = azapi_resource.nsp_profile.id }
output "jump_public_ip" { value = azurerm_public_ip.pip_jump.ip_address }
output "jump_vm_name" { value = azurerm_linux_virtual_machine.jump.name }
output "name_prefix" { value = var.name_prefix }
output "suffix" { value = local.suffix }
output "subscription_id" { value = var.subscription_id }
output "tenant_id" { value = var.tenant_id }
output "tags" { value = var.tags }
