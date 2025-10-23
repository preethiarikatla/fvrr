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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {}
}
# Stable, unique suffix so names don't collide with existing resources
resource "random_pet" "suffix" { length = 2 }

# 1) Create a fresh RG (unique name avoids conflicts)
resource "azurerm_resource_group" "rg" {
  name     = "rg-rollback-demo-${random_pet.suffix.id}"
  location = "East US"
}

# 2) Harmless RG-scoped ARM deployment via AzAPI (works on v1 and v2)
#    This just deploys an empty template; it's safe and idempotent.
resource "azapi_resource" "noop_deployment" {
  type      = "Microsoft.Resources/deployments@2021-04-01"
  name      = "noop-deployment"
  parent_id = azurerm_resource_group.rg.id

  body = jsonencode({
    properties = {
      mode      = "Incremental"
      template  = {
        "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        "contentVersion" = "1.0.0.0"
        "resources"      = []
        "outputs"        = {}
      }
      parameters = {}
    }
  })
}
