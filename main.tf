terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.50.0" 
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.13, != 1.13.0"
    }
  }
}

provider "azurerm" {
  features {}
}
# keep existing resources
resource "azurerm_resource_group" "rg" {
  name     = "rg-rollback-demo"
  location = "East US"
}

resource "azapi_resource" "rg_tags_v2" {
  type      = "Microsoft.Resources/tags@2021-04-01"
  name      = "default-v2"
  parent_id = azurerm_resource_group.rg.id
  body = jsonencode({
    properties = {
      tags = { env = "v2" }
    }
  })
}

# NEW: this plans fine but will FAIL on apply (bogus principal)
resource "azurerm_role_assignment" "will_fail_on_apply" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = "00000000-0000-0000-0000-000000000000"
}
