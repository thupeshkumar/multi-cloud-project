variable "name" { type = string }
variable "admin_cidr" { type = string }
variable "ssh_key" { type = string }
variable "startup" { type = string }

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}
resource "azurerm_resource_group" "lab" {
  name     = var.name
  location = "westus2"
}
resource "azurerm_virtual_network" "lab" {
  name                = var.name
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}
resource "azurerm_subnet" "lab" {
  name                 = "app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.1.0/24"]
}
resource "azurerm_public_ip" "lab" {
  name                = var.name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_network_security_group" "lab" {
  name                = var.name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  security_rule {
    name                       = "http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_interface" "lab" {
  name                = var.name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  ip_configuration {
    name                          = "app"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab.id
  }
}
resource "azurerm_network_interface_security_group_association" "lab" {
  network_interface_id      = azurerm_network_interface.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}
resource "azurerm_linux_virtual_machine" "lab" {
  name                  = var.name
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  size                  = "Standard_D2als_v7"
  admin_username        = "labadmin"
  network_interface_ids = [azurerm_network_interface.lab.id]
  admin_ssh_key {
    username   = "labadmin"
    public_key = var.ssh_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  custom_data = base64encode(var.startup)
  depends_on  = [azurerm_network_interface_security_group_association.lab]
}
resource "azurerm_storage_account" "lab" {
  name                            = "${var.name}sa"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}
resource "azurerm_storage_container" "lab" {
  name                  = "backups"
  storage_account_id    = azurerm_storage_account.lab.id
  container_access_type = "private"
}
output "ip" { value = azurerm_public_ip.lab.ip_address }
output "account" { value = azurerm_storage_account.lab.name }
