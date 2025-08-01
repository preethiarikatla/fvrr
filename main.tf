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

resource "azurerm_public_ip" "egress" {
  name                = "fw-egress-pip"
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

resource "azurerm_network_interface" "egress" {
  name                = "fw-egress-nic"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.egress.id
  }
}

resource "azurerm_linux_virtual_machine" "fw" {
  name                            = "fw-test-vm"
  location                        = azurerm_resource_group.test.location
  resource_group_name             = azurerm_resource_group.test.name
  size                            = "Standard_B1s"
  network_interface_ids           = [
    azurerm_network_interface.mgmt.id,
    azurerm_network_interface.egress.id
  ]
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
}

data "azurerm_public_ip" "manual" {
  name                = "rg-avx-pip-1"
  resource_group_name = "rg-avx-sim"
}

data "azurerm_network_interface" "egress" {
  for_each = {
    for k, v in {
      "fw-egress-nic" = azurerm_network_interface.egress
    } : k => v
  }

  name                = each.value.name
  resource_group_name = azurerm_resource_group.test.name

  depends_on = [azurerm_linux_virtual_machine.fw]
}

resource "azurerm_resource_group_template_deployment" "patch_nic" {
  for_each = {
    for key, nic in data.azurerm_network_interface.egress :
    key => nic
    if nic.ip_configuration[0].public_ip_address_id != data.azurerm_public_ip.manual.id
  }

  name                = "patch-${each.key}-egress"
  resource_group_name = azurerm_resource_group.test.name
  deployment_mode     = "Incremental"

  template_content = <<JSON
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "nicName": { "type": "string" },
    "publicIPId": { "type": "string" },
    "subnetId": { "type": "string" }
  },
  "resources": [{
    "type": "Microsoft.Network/networkInterfaces",
    "apiVersion": "2020-11-01",
    "name": "[parameters('nicName')]",
    "properties": {
      "ipConfigurations": [{
        "name": "ipconfig1",
        "properties": {
          "subnet": { "id": "[parameters('subnetId')]" },
          "publicIPAddress": { "id": "[parameters('publicIPId')]" }
        }
      }]
    }
  }]
}
JSON

  parameters_content = jsonencode({
    nicName = {
      value = each.value.name
    }
    publicIPId = {
      value = data.azurerm_public_ip.manual.id
    }
    subnetId = {
      value = each.value.ip_configuration[0].subnet_id
    }
  })

  depends_on = [azurerm_linux_virtual_machine.fw]
}
