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

variable "enable_nic_patch" {
  description = "Set to true to run the NIC patch ARM deployment"
  type        = bool
  default     = true
}

resource "azurerm_resource_group" "test" {
  name     = "rg-avx-sim"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-avx-sim"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-fw"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_public_ip" "mgmt" {
  name                = "fw-mgmt-pip"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "mgmt" {
  name                = "fw-mgmt-nic"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mgmt.id
  }
}

resource "azurerm_linux_virtual_machine" "fw" {
  name                            = "fw-test-vm"
  location                        = azurerm_resource_group.test.location
  resource_group_name             = azurerm_resource_group.test.name
  size                            = "Standard_B1s"
  network_interface_ids           = [azurerm_network_interface.mgmt.id]
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRJaB9f+o1bWUQFfigorqJVfcLNKX2Ox29MtvqyPgMz4D/WuSpa09nIbgp195vuqLbHiGG0gV2WNQab1MOLbI8xSm9wLNyX0Srm4+jwWXylHpjflm3L1QnceQANnt2LVqr7h2mSMubytDxKhImOnSXejgylyVp+nFV0624lHuyJXDNHZl+RXC0giEE1Iujz3Mu2lyZ1DkWAYzAbvvZfu8jOVuSk8hdpjZn6k0jvMkBGbCNxyg18SM/TSgx5X5Mwszjbx2dU1tNpXfW87XcvRn9zVE7Asw196YoZHx2yRadEf1KCv+vJxW/6Pwu1V7Uqg4k2t58rJ46217l39ZlKUJ9 preethi@SandboxHost-638883515602013682"
  }

  os_disk {
    name                 = "fw-vm-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  lifecycle {
    ignore_changes = [network_interface_ids]
  }
}

# Define multiple NICs to patch
locals {
  egress_nics = {
    "fw-egress-nic"  = "egress-nic"
    #"fw2-egress-nic" = "egress-nic-fw2"
  }
}

# Fetch each NIC
data "azurerm_network_interface" "egress" {
  for_each            = local.egress_nics
  name                = each.value
  resource_group_name = azurerm_resource_group.test.name
}

# Fetch the shared public IP (same for all NICs)
data "azurerm_public_ip" "manual" {
  name                = "rg-avx-pip-1"
  resource_group_name = azurerm_resource_group.test.name
}
resource "azurerm_resource_group_template_deployment" "patch_nic1" {
  for_each = local.egress_nics

  name                = "patch-${each.key}"
  resource_group_name = azurerm_resource_group.test.name
  deployment_mode     = "Incremental"

  template_content = jsonencode({
    "$schema" : "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion" : "1.0.0.0",
    "parameters" : {
      "nicName" : {
        "type" : "String"
      },
      "publicIPId" : {
        "type" : "String"
      },
      "egressIpId" : {
        "type" : "String"
      },
      "subnetId" : {
        "type" : "String"
      },
      "ipConfigName" : {
        "type" : "String"
      },
      "location" : {
        "type" : "String"
      },
      "tags" : {
        "type" : "Object"
      },
      "networkSecurityGroupId" : {
        "type" : "String"
      },
      "disableTcpStateTracking" : {
        "type" : "Bool"
      },
      "enableAcceleratedNetworking" : {
        "type" : "Bool"
      },
      "enableIPForwarding" : {
        "type" : "Bool"
      },
      "privateIPAddress" : {
         "type" : "String"
      }
    },
    "resources" : [
      {
        "type" : "Microsoft.Network/networkInterfaces",
        "apiVersion" : "2020-11-01",
        "name" : "[parameters('nicName')]",
        "condition" : "[not(equals(parameters('egressIpId'),parameters('publicIPId')))]",
        "location" : "[parameters('location')]",
        "tags" : "[parameters('tags')]",
        "properties" : {
          "disableTcpStateTracking" : "[parameters('disableTcpStateTracking')]",
          "enableAcceleratedNetworking" : "[parameters('enableAcceleratedNetworking')]",
          "enableIPForwarding" : "[parameters('enableIPForwarding')]",
          "ipConfigurations" : [
            {
              "name" : "[parameters('ipConfigName')]",
              "properties" : {
                "primary" : true,
                "privateIPAddress" : "[parameters('privateIPAddress')]",
                "privateIPAllocationMethod" : "Dynamic",
                "publicIPAddress" : {
                  "id" : "[parameters('publicIPId')]"
                },
                "subnet" : {
                  "id" : "[parameters('subnetId')]"
                }
              }
            }
          ],
          "networkSecurityGroup" : {
            "id" : "[parameters('networkSecurityGroupId')]"
          }
        }
      }
    ]
  })

  parameters_content = jsonencode({
    nicName = {
      value = data.azurerm_network_interface.egress[each.key].name
    },
    publicIPId = {
      value = data.azurerm_public_ip.manual.id
    },
    egressIpId = {
      value = data.azurerm_network_interface.egress[each.key].ip_configuration[0].public_ip_address_id
    },
    subnetId = {
      value = data.azurerm_network_interface.egress[each.key].ip_configuration[0].subnet_id
    },
    ipConfigName = {
      value = data.azurerm_network_interface.egress[each.key].ip_configuration[0].name
    },
    privateIPAddress = {
      value = data.azurerm_network_interface.egress[each.key].ip_configuration[0].private_ip_address
    },
    location = {
      value = azurerm_resource_group.test.location
    },
    tags = {
      value = try(data.azurerm_network_interface.egress[each.key].tags, {})
    },
    networkSecurityGroupId = {
      value = try(data.azurerm_network_interface.egress[each.key].network_security_group_id, null)
    },
    disableTcpStateTracking = {
      value = false
    },
    enableAcceleratedNetworking = {
      value = false
    },
    enableIPForwarding = {
      value = true
    }
  })
}
