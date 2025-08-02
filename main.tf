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
  network_interface_ids           = [
    azurerm_network_interface.mgmt.id,
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
  lifecycle {
    ignore_changes = [
      network_interface_ids
    ]
  }
}

# Step 1: Extract the egress NIC name from attached NICs
locals {
  # Assuming index 1 is the egress NIC. Adjust index if needed (e.g., [0] if it’s the first one)
  egress_nics = {
    "fw-egress-nic" = split("/", azurerm_linux_virtual_machine.fw.network_interface_ids[1])[length(split("/", azurerm_linux_virtual_machine.fw.network_interface_ids[1])) - 1]
  }
  nsg_map = {
    "fw-egress-nic" = "nsg-fw-egress"
  }
}

# Step 2: Fetch the NIC data
data "azurerm_network_interface" "egress" {
  for_each = local.egress_nics
  name                = each.value
  resource_group_name = azurerm_resource_group.test.name
}

# Step 3: Fetch the expected manually created public IP
data "azurerm_public_ip" "manual" {
  for_each = local.egress_nics
  name                = "rg-avx-pip-1"
  resource_group_name = azurerm_resource_group.test.name
}

data "azurerm_network_security_group" "egress_nsg" {
  for_each = local.nsg_map
  name                = "rg-avx-nsg"
  resource_group_name = azurerm_resource_group.test.name
}

# Step 4: Conditionally patch the NIC using template deployment

resource "azurerm_resource_group_template_deployment" "patch_nic1" {
  for_each = var.enable_nic_patch ? {
    for nic_name, nic in data.azurerm_network_interface.egress :
    nic_name => nic
    if try(nic.ip_configuration[0].public_ip_address_id, "") != try(data.azurerm_public_ip.manual[nic_name].id, "") || true
  } : {}
  name                = "patch-${each.key}"
  resource_group_name = azurerm_resource_group.test.name
  deployment_mode     = "Incremental"

  template_content = <<JSON
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "nicName": { "type": "string" },
    "publicIPId": { "type": "string" },
    "subnetId": { "type": "string" },
    "ipConfigName": { "type": "string" },
    "location": { "type": "string" },
    "tags": { "type": "object" },
    "networkSecurityGroupId": { "type": "string" },
    "enableAcceleratedNetworking": { "type": "bool" },
    "enableIPForwarding": { "type": "bool" },
    "disableTcpStateTracking": { "type": "bool" }
  },
  "resources": [{
    "type": "Microsoft.Network/networkInterfaces",
    "apiVersion": "2020-11-01",
    "name": "[parameters('nicName')]",
    "location": "[parameters('location')]",
    "tags": "[parameters('tags')]",
    "properties": {
      "enableAcceleratedNetworking": "[parameters('enableAcceleratedNetworking')]",
      "enableIPForwarding": "[parameters('enableIPForwarding')]",
      "disableTcpStateTracking": "[parameters('disableTcpStateTracking')]",
      "networkSecurityGroup": {
        "id": "[parameters('networkSecurityGroupId')]"
      },
      "ipConfigurations": [{
        "name": "[parameters('ipConfigName')]",
        "properties": {
          "subnet": { "id": "[parameters('subnetId')]" },
          "publicIPAddress": { "id": "[parameters('publicIPId')]" },
          "privateIPAllocationMethod": "Dynamic",
          "primary": true
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
      value = data.azurerm_public_ip.manual[each.key].id
    }
    subnetId = {
      value = each.value.ip_configuration[0].subnet_id
    }
    ipConfigName = {
      value = each.value.ip_configuration[0].name
    }
    location = {
      value = azurerm_resource_group.test.location
    }
    tags = {
      value = each.value.tags
    }
    networkSecurityGroupId = {
      value = data.azurerm_network_security_group.egress_nsg[each.key].id
    }
    enableAcceleratedNetworking = {
      value = lookup(each.value, "enable_accelerated_networking", false)
    }
    enableIPForwarding = {
      value = lookup(each.value, "enable_ip_forwarding", true)
    }
    disableTcpStateTracking = {
      value = lookup(each.value, "disable_tcp_state_tracking", false)
    }
  })

  depends_on = [azurerm_linux_virtual_machine.fw]
  lifecycle {
    prevent_destroy = true
  }
}
