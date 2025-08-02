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
    public_key = "ssh-rsa AAAAB3..."
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

locals {
  egress_nic_name = "egress-nic"
}

data "azurerm_network_interface" "egress" {
  name                = local.egress_nic_name
  resource_group_name = azurerm_resource_group.test.name
}

data "azurerm_public_ip" "manual" {
  name                = "rg-avx-pip-1"
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_resource_group_template_deployment" "patch_nic1" {
  count               = var.enable_nic_patch && data.azurerm_network_interface.egress.ip_configuration[0].public_ip_address_id != data.azurerm_public_ip.manual.id ? 1 : 0
  name                = "patch-${local.egress_nic_name}"
  resource_group_name = azurerm_resource_group.test.name
  deployment_mode     = "Incremental"

  template_content = file("nic_patch_template.json")

  parameters_content = jsonencode({
    nicName = {
      value = data.azurerm_network_interface.egress.name
    }
    publicIPId = {
      value = data.azurerm_public_ip.manual.id
    }
    subnetId = {
      value = data.azurerm_network_interface.egress.ip_configuration[0].subnet_id
    }
    ipConfigName = {
      value = data.azurerm_network_interface.egress.ip_configuration[0].name
    }
    location = {
      value = azurerm_resource_group.test.location
    }
    tags = {
      value = data.azurerm_network_interface.egress.tags
    }
    networkSecurityGroupId = {
      value = data.azurerm_network_interface.egress.network_security_group[0].id
    }
    enableAcceleratedNetworking = {
      value = lookup(data.azurerm_network_interface.egress, "enable_accelerated_networking", false)
    }
    enableIPForwarding = {
      value = lookup(data.azurerm_network_interface.egress, "enable_ip_forwarding", true)
    }
    disableTcpStateTracking = {
      value = lookup(data.azurerm_network_interface.egress, "disable_tcp_state_tracking", false)
    }
  })

  lifecycle {
    ignore_changes = [parameters_content, template_content]
  }

  depends_on = [azurerm_linux_virtual_machine.fw]
}
