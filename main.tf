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
  sku                 = "Standard"
}

# NICs that may or may not match the reserved IPs
resource "azurerm_network_interface" "nic" {
  for_each = toset(["fw1", "fw2"])

  name                = "${each.key}-nic"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
  lifecycle {
    ignore_changes = [
      ip_configuration[0].public_ip_address_id
    ]
  }
}
resource "azurerm_resource_group_template_deployment" "patch_nic" {
  for_each = {
    for key in ["fw1", "fw2"] :
    key => azurerm_network_interface.nic[key]
    if azurerm_network_interface.nic[key].ip_configuration[0].public_ip_address_id != azurerm_public_ip.reserved[key].id
  }

  name                = "patch-${each.key}-egress"
  resource_group_name = azurerm_resource_group.test.name
  deployment_mode     = "Incremental"

 template_content = <<JSON
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "nicName": {
      "type": "string"
    },
    "publicIPId": {
      "type": "string"
    },
    "subnetId": {
      "type": "string"
    },
    "location": {
      "type": "string"
    }
  },
  "resources": [
    {
      "type": "Microsoft.Network/networkInterfaces",
      "apiVersion": "2020-11-01",
      "name": "[parameters('nicName')]",
      "location": "[parameters('location')]",
      "properties": {
        "ipConfigurations": [
          {
            "name": "ipconfig1",
            "properties": {
              "subnet": {
                "id": "[parameters('subnetId')]"
              },
              "publicIPAddress": {
                "id": "[parameters('publicIPId')]"
              }
            }
          }
        ]
      }
    }
  ]
}
JSON

parameters_content = jsonencode({
  nicName = {
    value = each.value.name
  }
  publicIPId = {
    value = azurerm_public_ip.reserved[each.key].id
  }
  subnetId = {
    value = azurerm_subnet.subnet.id
  }
  location = {
    value = azurerm_resource_group.test.location
  }
})

  depends_on = [azurerm_network_interface.nic]
}

