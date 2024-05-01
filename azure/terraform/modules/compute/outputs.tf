output "vms" {
  value = azurerm_linux_virtual_machine.vm
}

output "vm_names" {
  description = "Name of VMs"
  value = [for k, vm in azurerm_linux_virtual_machine.vm: vm.name]
}

output "private_ips" {
  description = "Private IPs of VMs"
  value = [for k, vm in azurerm_linux_virtual_machine.vm: vm.private_ip_address]
}

output "public_ips" {
  description = "Public IPs of VMs"
  value = [for k, pip in azurerm_public_ip.publicip: pip.ip_address]
}