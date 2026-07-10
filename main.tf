terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.50.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Change this value to 1 or 2
variable "gateway_count" {
  description = "Number of ExpressRoute VNGs to create"
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2], var.gateway_count)
    error_message = "gateway_count must be either 1 or 2."
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-er-test"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet" {
  count = var.gateway_count

  name                = "vnet-er-test-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  address_space = [
    count.index == 0 ? "10.0.0.0/16" : "10.1.0.0/16"
  ]
}

resource "azurerm_subnet" "gateway" {
  count = var.gateway_count

  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[count.index].name

  address_prefixes = [
    count.index == 0 ? "10.0.255.0/27" : "10.1.255.0/27"
  ]
}
resource "azurerm_virtual_network_gateway" "er_vng" {
  count = var.gateway_count

  name                = "vng-er-test-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  type     = "ExpressRoute"
  sku      = "UltraPerformance"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    subnet_id                     = azurerm_subnet.gateway[count.index].id
  }
}
