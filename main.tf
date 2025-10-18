terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.106.0" 
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg_test" {
  name     = "rg-test-low-version"
  location = "East US"
}

# keep the existing RG from Commit A
resource "azurerm_resource_group" "rg" {
  name     = "tf-rg-baseline-demo"
  location = "East US"
}

# NEW resource that will fail at apply (but plan OK)
# bogus principal_id ensures "Principal not found" or auth failure from ARM
resource "azurerm_role_assignment" "will_fail_on_apply" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = "00000000-0000-0000-0000-000000000000"  # invalid principal
}
