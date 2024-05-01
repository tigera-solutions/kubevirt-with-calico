# kubevirt-with-calico

## Kubevirt with Calico on Azure compute instances

This example uses Azure compute instances to create a `kubeadm` cluster and configure Kubevirt in it.

### provision Azure compute instances

The provided `terraform` scripts can help quickly provision a few compute instances that will be used to install `kubeadm` cluster.

>before running `terraform` commands, review and adjust variables in the `variables.tf` or use `terraform.tfvars` config file.

```bash
cd azure/terraform
terraform init
terraform plan
terraform apply -auto-approve
```

### create `kubeadm` cluster

>use either `provision_k8s-ubuntu.yaml` or `provision_k8s-centos.yaml` ansible playbook to create a `kubeadm` cluster either on Ubuntu instances or CentOS instances.

```bash
# set ansible env vars before running playbooks
export ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_CONFIG=ansible/ansible.cfg
# terraform provisioning will generate ansible/inventory file that ansible playbooks use
# create kubeadm cluster and join workers
SSH_KEY=/path/to/ssh_private_key # e.g. SSH_KEY=~/.ssh/az_id
ansible-playbook -u azureuser --private-key $SSH_KEY --timeout 60 -i ansible/inventory ansible/provision_k8s-ubuntu.yaml
# ansible-playbook -u azureuser --private-key $SSH_KEY --timeout 60 -i ansible/inventory ansible/provision_k8s-centos.yaml
```

### install Calico

>review and adjust variables in ansible playbooks before running them.

This repo provides 3 ansible playbooks to install Calico:

- `calico-os-provisioner.yaml` - installs Calico open source
- `calico-ent-min-provisioner.yaml` - installs minimal configuration of Calico Enterprise (i.e. no log storage, UI and related components)
- `calico-ent-provisioner.yaml` - installs full configuration of Calico Enterprise

>installation of Calico commercial versions is covered later in this guide.

Example to install Calico open source version

```bash
########################
## or install Calico OSS
########################
ansible-playbook -u azureuser --private-key $SSH_KEY --timeout 60 -i ansible/inventory ansible/calico-os-provisioner.yaml
```

### install Kubevirt

Review latest [Kubevirt docs](https://kubevirt.io/user-guide/) for most up to date installation and usage information.

```bash
# deploy Kubevirt resources
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo $VERSION
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/$VERSION/kubevirt-operator.yaml
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/$VERSION/kubevirt-cr.yaml

# monitor Kubevirt deployment status
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"
```

#### [Optional] configure `virtctl` if you want to use this CLI to manage Kubevirt VMs

```bash
VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.targetKubeVirtVersion}")
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/') || windows-amd64.exe
echo $ARCH $VERSION
curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/$VERSION/virtctl-$VERSION-$ARCH
chmod +x virtctl
sudo install virtctl /usr/local/bin
```

### deploy Kubevirt VM

Deploy a test pod and an Ubuntu VM and test connectivity between them.

>By default Ubuntu VM image doesn't provide a default user. You have to configure it. This example uses `cloud-init` to configure the default user and set SSH access to the VM. It is assumed that `rsa_id.pub` belongs to the SSH key pair that is used to access Kubernetes hosts.

```bash
# if you're in the terraform dir, get one level up
cd ..
# get ssh key
SSH_PUB_KEY=$(cat ~/.ssh/rsa_id.pub)
# set SSH_PUB_KEY value in the kubevirt/ubuntu/cloud-init file
# get base64 encoded text of the kubevirt/ubuntu/cloud-init file
export CLOUDINIT=$(sed -e "s,<INSERT_YOUR_PUBLIC_SSH_KEY_HERE>,$SSH_PUB_KEY,1" kubevirt/ubuntu/cloud-init | base64 -i -)

# deploy ubuntu VM
## NOTE: the manifest is configured to not create VM instance once you deploy it. You can use either virtctl or kubectl commands to start a VM instance.
sed -e "s/\${CLOUDINIT}/${CLOUDINIT}/1" kubevirt/ubuntu/ubuntu-vm.yaml | kubectl apply -f-

########################################
# example to start/stop VM using virtctl
########################################
# start VM
virtctl start ubuntu-vm
# stop VM
virtctl stop ubuntu-vm

########################################
# example to start/stop VM using kubectl
########################################
## start the virtual machine
kubectl patch virtualmachine ubuntu-vm --type merge -p '{"spec":{"running":true}}'
## stop the virtual machine
kubectl patch virtualmachine ubuntu-vm --type merge -p '{"spec":{"running":false}}'

# deploy test pods
kubectl apply -f apps/netshoot.yaml
kubectl apply -f apps/centos.yaml
```

### connect to the VM and test connectivity

The `kubevirt/ubuntu/ubuntu-vm.yaml` deploys a `NodePort` service that maps `30022` node port to a `22` port of the VM. You can use the `NodePort` to SSH into the VM.
Ubuntu VM should have Nginx service installed and running in it. Which can be used to test connectivity to the Nginx service inside of the VM.

```bash
# get public IP from one of the cluster nodes
NODE_IP=xx.xx.xx.xx
# ssh into ubuntu-vm
ssh -i $SSH_KEY $NODE_IP -p 30022 -l ubuntu
# curl external endpoint from within the VM
curl google.com

# test connectivity from netshoot pod and centos pod to nginx service inside of the Ubuntu VM
kubeclt exec -t netshoot -- sh -c 'curl -m2 ubuntu-nginx'
kubeclt -n dev exec -t centos -- sh -c 'curl -m2 ubuntu-nginx'
```

Apply policies to configure access controls to Ubuntu VM

```bash
# apply policy to allow access from pods in default namespace to port 80 of the Ubuntu VM that Nginx service uses
kubectl apply -f policies/k8s.ubuntu-nginx.yaml

# test access to the Nginx service from default/netshoot pod and from dev/centos pod
kubeclt exec -t netshoot -- sh -c 'curl -m2 ubuntu-nginx'
kubeclt -n dev exec -t centos -- sh -c 'curl -m2 ubuntu-nginx'

# apply policy to allow SSH access to the Ubuntu VM
kubectl apply -f policies/calico.ubuntu-ssh.yaml
```

### clean up Azure environment

```bash
terraform destroy -auto-approve
```
