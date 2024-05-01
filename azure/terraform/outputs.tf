output "masters-vm_names" {
  value = module.masters.vm_names
}

output "masters-public_ips" {
  value = module.masters.public_ips
}

output "workers-vm_names" {
  value = module.workers.vm_names
}

output "workers-public_ips" {
  value = module.workers.public_ips
}
