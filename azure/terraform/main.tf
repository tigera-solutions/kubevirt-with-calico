# Create resouce group
resource "azurerm_resource_group" "resourcegroup" {
  name     = var.resourcegroup
  location = var.location
}

# Create service principal
module "serviceprincipal" {
  source            = "./modules/serviceprincipal"
  resourcegroup_id  = azurerm_resource_group.resourcegroup.id
  name              = var.service_principal_name
  depends_on        = [azurerm_resource_group.resourcegroup]
}

# Assign service principal a roll on the resource group
resource "azurerm_role_assignment" "sp_role_assignment" {
  scope                = azurerm_resource_group.resourcegroup.id
  role_definition_name = "Contributor"
  principal_id         = module.serviceprincipal.object_id
  depends_on = [module.serviceprincipal]
}

# Generate azure-cloud.conf
resource "local_file" "azure_cloud_file" {
  content  = <<EOF
{
  "cloud": "AzurePublicCloud",
  "tenantId": "${var.tenant_id}",
  "subscriptionId": "${var.azure_subscription_id}",
    "aadClientId": "${module.serviceprincipal.client_id}",
  "aadClientSecret": "${module.serviceprincipal.app_secret}",
  "resourceGroup": "${azurerm_resource_group.resourcegroup.name}",
  "location": "${var.location}",
  "vmType": "standard",
  "subnetName": "${azurerm_subnet.subnet.name}",
  "securityGroupName": "",
  "vnetName": "${azurerm_virtual_network.vnet.name}",
  "vnetResourceGroup": "${azurerm_resource_group.resourcegroup.name}",
  "routeTableName": "",
  "cloudProviderBackoff": false,
  "useManagedIdentityExtension": false,
  "userAssignedIdentityID": "",
  "useInstanceMetadata": true,
  "loadBalancerSku": "Basic",
  "disableOutboundSNAT": false,
  "excludeMasterFromStandardLB": false,
  "maximumLoadBalancerRuleCount": 250
}
  EOF

  filename = "${path.module}/ansible/azure-cloud.conf"
  depends_on = [
    module.serviceprincipal,
    azurerm_virtual_network.vnet,
    azurerm_subnet.subnet
  ]
}

# Create VNET with Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.resourcegroup.location
  resource_group_name = azurerm_resource_group.resourcegroup.name
  address_space       = ["172.10.0.0/16"]

  tags = {
    environment = "k8sdev"
  }
}

# Create subnet within VNET
resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.resourcegroup.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.10.1.0/24"]
}

module "masters" {
  source           = "./modules/compute"
  vm_names         = var.master_vm_name
  resourcegroup    = azurerm_resource_group.resourcegroup.name
  location         = azurerm_resource_group.resourcegroup.location
  subnet           = azurerm_subnet.subnet
  publickey        = file("${var.ssh_key_path}.pub")
  vmsize           = var.master_vm_size
  private_key_path = var.ssh_key_path
  prefix           = var.prefix
  image            = var.image
  depends_on       = [azurerm_subnet.subnet]
}

module "workers" {
  source           = "./modules/compute"
  vm_names         = var.worker_vm_name
  resourcegroup    = azurerm_resource_group.resourcegroup.name
  location         = azurerm_resource_group.resourcegroup.location
  subnet           = azurerm_subnet.subnet
  publickey        = file("${var.ssh_key_path}.pub")
  vmsize           = var.worker_vm_size
  private_key_path = var.ssh_key_path
  prefix           = var.prefix
  image            = var.image
  depends_on       = [azurerm_subnet.subnet]
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/ansible/inventory.tmpl",
    {
      master_public_ips = module.masters.public_ips,
      master_private_ip = module.masters.private_ips[0],
      worker_public_ips = module.workers.public_ips
    }
  )
  filename = "ansible/inventory"

  depends_on = [
    module.masters,
    module.workers
  ]
}
