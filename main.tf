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

moved {
  from = module.rg.azurerm_resource_group.rg
  to   = module.rg.azurerm_resource_group.rg_new
}

resource "azurerm_resource_group" "rg_new" {
  name     = "pree"
  location = "eastus"
}

