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

resource "azurerm_resource_group" "rg" {
  name     = "copilot-test-rg"
  location = "East US"
}

# Virtual Network and Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "copilot-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "copilot-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# NSG
resource "azurerm_network_security_group" "nsg" {
  name                = "copilot-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Public IP
resource "azurerm_public_ip" "pip" {
  name                = "copilot-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Basic"

  lifecycle {
    prevent_destroy = true
  }
}

# NIC
resource "azurerm_network_interface" "nic" {
  name                = "copilot-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# NIC + NSG Association
resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_interface" "dummy_nic" {
  name                = "copilot-dummy-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}
# Linux VM
resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "copilot-test-vm"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = "Standard_B1s"
  network_interface_ids           = [azurerm_network_interface.dummy_nic.id]
  #network_interface_ids           = [azurerm_network_interface.nic.id]
  depends_on = [azurerm_network_interface.dummy_nic]
  admin_username                  = "azureuser"
  disable_password_authentication = true
  # 👇 Required dummy key – no login needed
  admin_ssh_key {
  username   = "azureuser"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRJaB9f+o1bWUQFfigorqJVfcLNKX2Ox29MtvqyPgMz4D/WuSpa09nIbgp195vuqLbHiGG0gV2WNQab1MOLbI8xSm9wLNyX0Srm4+jwWXylHpjflm3L1QnceQANnt2LVqr7h2mSMubytDxKhImOnSXejgylyVp+nFV0624lHuyJXDNHZl+RXC0giEE1Iujz3Mu2lyZ1DkWAYzAbvvZfu8jOVuSk8hdpjZn6k0jvMkBGbCNxyg18SM/TSgx5X5Mwszjbx2dU1tNpXfW87XcvRn9zVE7Asw196YoZHx2yRadEf1KCv+vJxW/6Pwu1V7Uqg4k2t58rJ46217l39ZlKUJ9 preethi@SandboxHost-638883515602013682"
}
source_image_reference {
  publisher = "Canonical"
  offer     = "UbuntuServer"
  sku       = "18.04-LTS"
  version   = "latest"
}

  os_disk {
    name                 = "copilot-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_linux_virtual_machine" "vm_new" {
  name                            = "copilot-new-vm"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = "Standard_B1s"
  network_interface_ids           = [azurerm_network_interface.nic.id]  # original NIC
  depends_on = [azurerm_linux_virtual_machine.vm] 
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRJaB9f+o1bWUQFfigorqJVfcLNKX2Ox29MtvqyPgMz4D/WuSpa09nIbgp195vuqLbHiGG0gV2WNQab1MOLbI8xSm9wLNyX0Srm4+jwWXylHpjflm3L1QnceQANnt2LVqr7h2mSMubytDxKhImOnSXejgylyVp+nFV0624lHuyJXDNHZl+RXC0giEE1Iujz3Mu2lyZ1DkWAYzAbvvZfu8jOVuSk8hdpjZn6k0jvMkBGbCNxyg18SM/TSgx5X5Mwszjbx2dU1tNpXfW87XcvRn9zVE7Asw196YoZHx2yRadEf1KCv+vJxW/6Pwu1V7Uqg4k2t58rJ46217l39ZlKUJ9 preethi@SandboxHost-638883515602013682"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    name                 = "copilot-new-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}
