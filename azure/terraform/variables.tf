
variable "ssh_key_path" {
  description = "Name of the resource group"
  default     = "~/.ssh/rsa_id"
}

# you can get it from az CLI
# az account list --query "[0].id"
variable "azure_subscription_id" {
  description = "Azure subscription Id"
  default     = ""
}

# you can get it from az CLI
# az account list --query "[0].tenantId"
variable "tenant_id" {
  description = "Azure subscription tenant Id"
  default     = ""
}

variable "resourcegroup" {
  description = "Name of the resource group"
  default     = "k8s-kubeadm"
}

variable "location" {
  description = "Location of the resources"
  default     = "westus2"
}

variable "image" {
  description = "VM image"
  type        = map(string)
  default     = {
    # Ubuntu 22.04
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "22.04.202403280"
  }
}

variable "master_vm_name" {
  description = "Names of control plane VMs"
  type        = list(string)
  default     = ["k8s-master"]
}

variable "worker_vm_name" {
  description = "Names of worker VMs"
  type        = list(string)
  default     = ["k8s-worker1", "k8s-worker2"]
  # default     = ["k8s-worker1", "k8s-worker2", "k8s-worker3"]
}

# Standard_D8s_v3 instance type has nested virtualization feature
variable "master_vm_size" {
  description = "Size of master VM"
  default     = "Standard_D8s_v3"
}

# Standard_D8s_v3 instance type has nested virtualization feature
variable "worker_vm_size" {
  description = "Size of worker VM"
  default     = "Standard_D8s_v3"
}

variable "prefix" {
  description = "prefix"
  default     = "k8s-sm"
}

variable "service_principal_name" {
  description = "Name of service principal account"
  default     = "self-mged-k8s-sp"
}
