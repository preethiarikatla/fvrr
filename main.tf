terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.19.0"
    }
  }
}
provider "azurerm" {
  features {}
}
#
resource "azurerm_resource_group" "test" {
  name     = "rg-nic-test"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-nic-test"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-test"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
#
# Public IPs (simulated reserved IPs)
resource "azurerm_public_ip" "reserved" {
  for_each = toset(["fw1", "fw2"])

  name                = "avx-eastus-pa-${each.key}-pip"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Static"
  sku                 = "Basic"
}



