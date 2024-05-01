# Create Public IP
resource "azurerm_public_ip" "publicip" {
  for_each = toset(var.vm_names)
  name     = join("-nic", [each.value])
  location            = var.location
  resource_group_name = var.resourcegroup
  allocation_method   = "Static"
  domain_name_label   = join("-", [var.prefix, each.value])

  tags = {
    environment = "k8sdev"
  }
}

# Create network interface card 
resource "azurerm_network_interface" "nic" {
  for_each            = toset(var.vm_names)
  name                = join("-nic", [each.value])
  location            = var.location
  resource_group_name = var.resourcegroup

  ip_configuration {
    name                          = "testconfig"
    subnet_id                     = var.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip[each.key].id
  }
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  for_each            = toset(var.vm_names)
  name                  = each.value
  location              = var.location
  resource_group_name   = var.resourcegroup
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]
  size                  = var.vmsize
  admin_username        = "azureuser"

  # get images via az CLI
  # az vm image list --all --publisher Canonical | jq '[.[] | select(.sku=="22_04-lts")]| max_by(.version)'
  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
    # Ubuntu 22.04
    # publisher = "Canonical"
    # offer     = "0001-com-ubuntu-server-jammy"
    # sku       = "22_04-lts"
    # version   = "22.04.202403280"
    # Ubuntu 20.04
    # offer     = "0001-com-ubuntu-server-focal"
    # sku       = "20_04-lts"
    # version   = "20.04.202301130"
    # Ubuntu 18.04
    # offer     = "UbuntuServer"
    # sku       = "18.04-LTS"
    # version   = "latest"
    # CentOS 8
    # publisher = "OpenLogic"
    # offer     = "CentOS"
    # sku       = "8_2"
    # version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.publickey
  }

  tags = {
    environment = "k8sdev"
  }
}
