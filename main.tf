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

# MUST MATCH STATE ADDRESS EXACTLY
moved {
  from = azurerm_resource_group.rg
  to   = azurerm_resource_group.rg_new
}

# ONLY NEW RESOURCE EXISTS
resource "azurerm_resource_group" "rg_new" {
  name     = "pree"
  location = "eastus"
}

