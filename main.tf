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
variable "enable_patch" {
  type    = bool
  default = false
  description = "Flag to enable or disable NIC patching"
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
data "azurerm_network_security_group" "existing_nsg" {
  name                = "rg-avx-nsg"
  resource_group_name = azurerm_resource_group.test.name
}
resource "azurerm_resource_group_template_deployment" "patch_nic1" {
for_each = data.azurerm_network_interface.egress

  name                = "patch-${each.key}"
  resource_group_name = azurerm_resource_group.test.name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/patch.json")  # ✅ Corrected here

  parameters_content = jsonencode({
    nicName = { value = each.value.name },
    publicIPId = { value = data.azurerm_public_ip.manual.id },
    egressIpId = { value = each.value.ip_configuration[0].public_ip_address_id },
    subnetId = { value = each.value.ip_configuration[0].subnet_id },
    ipConfigName = { value = each.value.ip_configuration[0].name },
    privateIPAddress = { value = each.value.ip_configuration[0].private_ip_address },
    location = { value = azurerm_resource_group.test.location },
    tags = { value = try(each.value.tags, {}) },
   networkSecurityGroupId = {
      value = data.azurerm_network_security_group.existing_nsg.id
   },
    #networkSecurityGroupId = {
    #  value = try(data.azurerm_network_interface.egress[each.key].network_security_group_id, null)
    #},
    disableTcpStateTracking = { value = false },
    enableAcceleratedNetworking = { value = false },
    enableIPForwarding = { value = true }
  })
 lifecycle {
  ignore_changes = [template_content, parameters_content]
}
}
