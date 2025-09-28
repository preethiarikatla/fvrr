terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=2.50.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# --- simple naming + region ---
locals {
  location = "eastus2"
  prefix   = "tfw-demo"
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# --- resource group ---
resource "azurerm_resource_group" "rg" {
  name     = "${local.prefix}-${random_string.suffix.result}-rg"
  location = local.location
}

# --- vnet + subnets ---
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.prefix}-${random_string.suffix.result}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Azure Firewall requires the subnet name EXACTLY "AzureFirewallSubnet" and at least /26
resource "azurerm_subnet" "afw" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/26"]
}

# A sample workload subnet that will use the route table
resource "azurerm_subnet" "workload" {
  name                 = "workload-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# --- public IP for Firewall ---
resource "azurerm_public_ip" "afw" {
  name                = "${local.prefix}-${random_string.suffix.result}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# --- Azure Firewall ---
resource "azurerm_firewall" "afw" {
  name                = "${local.prefix}-${random_string.suffix.result}-afw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "AZFW_VNet"   # VNet-deployed firewall
  sku_tier            = "Standard"    # or "Premium"
  threat_intel_mode   = "Alert"

  ip_configuration {
    name                 = "afw-ipconfig"
    subnet_id            = azurerm_subnet.afw.id
    public_ip_address_id = azurerm_public_ip.afw.id
  }
}

# --- Route table + default route via firewall private IP ---
resource "azurerm_route_table" "rt" {
  name                = "${local.prefix}-${random_string.suffix.result}-rt"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  disable_bgp_route_propagation = false
}

resource "azurerm_route" "default_to_afw" {
  name                   = "default-to-afw"
  resource_group_name    = azurerm_resource_group.rg.name
  route_table_name       = azurerm_route_table.rt.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"

  # <-- THIS is the key line. Becomes known during the same apply.
  next_hop_in_ip_address = azurerm_firewall.afw.ip_configuration[0].private_ip_address
}

# Associate the RT to the workload subnet so traffic uses the firewall
resource "azurerm_subnet_route_table_association" "workload_assoc" {
  subnet_id      = azurerm_subnet.workload.id
  route_table_id = azurerm_route_table.rt.id
}

# (Optional) quick visibility; safe to remove if you truly want "no outputs".
output "firewall_private_ip" {
  value = azurerm_firewall.afw.ip_configuration[0].private_ip_address
}
