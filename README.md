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

>by default Ubuntu VM image doesn't provide a default user. You have to configure it. This example uses `cloud-init` to configure the default user and set SSH access to the VM. It is assumed that `rsa_id.pub` belongs to the SSH key pair that is used to access Kubernetes hosts.

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

### install Calico Enterprise or Calico Cloud

Calico commercial versions such as Calico Enterprise and Calico Cloud offer additional capabilities such as visibility & observability tools, troubleshooting tools, and advanced security features.
In this section we'll use a multi-interface support to configure a Kubevirt VM with multiple interfaces.

Calico Enterprise requires a license key and a pull-secret. If you want to try it, contact [Tigera](https://tigera.io/contact).
Alternatively, you can use a [Calico Cloud trial account](https://www.tigera.io/tigera-products/calico-cloud/) to try out Calico commercial features.

Example to install Calico Enterprise version using ansible script

```bash
###################################################################
## Calico Enterprise requires licence key and pull-secret resources
###################################################################
# copy Tigera license and pull secret into the ansible/ folder
LICENSE_PATH=/path/to/license.yaml
PULL_SECRET_PATH=/path/to/pull-secret.json
cp $LICENSE_PATH ansible/license.yaml
cp $PULL_SECRET_PATH ansible/pull-secret.json

############################
## install Calico Enterprise
############################
ansible-playbook -u azureuser --private-key $SSH_KEY --timeout 60 -i ansible/inventory ansible/calico-ent-provisioner.yaml

#####################################################
## install minimal configuration of Calico Enterprise
#####################################################
# ansible-playbook -u azureuser --private-key $SSH_KEY --timeout 60 -i ansible/inventory ansible/calico-ent-min-provisioner.yaml
```

### configure multiple networks per pod

>this is a commercial feature and requires either Calico Enterprise or Calico Cloud version of Calico CNI.

This feature requires [Multus](https://github.com/intel/multus-cni/) meta-CNI.

#### install Multus

Download [Multus manifest](https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml) and increase memory limits from default `50Mi` to `300Mi` for `kube-multus` container and from `15Mi` to `50Mi` for `install-multus-binary` init container.

```bash
# download Multus manifest
curl -O https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
```

Example of increased memory limits

```yaml
.....
      containers:
        - name: kube-multus
          image: ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick
          command: [ "/usr/src/multus-cni/bin/multus-daemon" ]
          resources:
            requests:
              cpu: "100m"
              memory: "50Mi"
            limits:
              cpu: "100m"
              memory: "300Mi"
.....
      initContainers:
        - name: install-multus-binary
          image: ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick
          command:
            - "cp"
            - "/usr/src/multus-cni/bin/multus-shim"
            - "/host/opt/cni/bin/multus-shim"
          resources:
            requests:
              cpu: "10m"
              memory: "50Mi"
.....
```

Deploy Multus CNI

```bash
kubectl apply -f multus-daemonset-thick.yml
```

#### enable multiple networks support in Calico

Enable multiple networks per pod support in Calico.

```bash
# enable Multus mode in Calico Installation resource
kubectl patch installations default --type merge --patch='{"spec": {"calicoNetwork": {"multiInterfaceMode": "Multus"}}}'

# view multiInterfaceMode configuration
kubectl get installations default -ojsonpath='{.spec.calicoNetwork.multiInterfaceMode}'
```

Configure several Calico IPPool resources that will be used to configure different networks in a VM/pod.

>use [calicoctl](https://docs.tigera.io/calico-enterprise/latest/operations/clis/calicoctl/install) CLI to run the commands below as modifying IPPool resource in the existing cluster requires validation that `calicoctl` provides.

```bash
# delete existing default IPPool
calicoctl delete ippool default-ipv4-ippool
# apply new ippools configuration
calicoctl apply -f calico/ippools.yaml
# cycle all pods to get new IPs
kubectl delete pod --all -A
```

Deploy network attachment resources that will be used to create multiple interfaces in a VM/pod.

```bash
kubectl apply -f calico/network-attachments.yaml
```

#### deploy Kubevirt VM with multiple networks

Deploy a Kubevirt VM with multiple networks and test connectivity.

>note, that in order for the Kubevirt VM to use additional network interfaces, they need to be initialized when VM boots up. In the example VM this task is delegated to the `cloud-init-multi-nic` file that contains commands to initialize additional interfaces in the VM.

```bash
# get ssh key
SSH_PUB_KEY=$(cat ~/.ssh/rsa_id.pub)
# set SSH_PUB_KEY value in the kubevirt/ubuntu/cloud-init file
# get base64 encoded text of the kubevirt/ubuntu/cloud-init file
export CLOUDINIT=$(sed -e "s,<INSERT_YOUR_PUBLIC_SSH_KEY_HERE>,$SSH_PUB_KEY,1" kubevirt/ubuntu/cloud-init-multi-nic | base64 -i -)

# deploy ubuntu VM
## NOTE: the manifest is configured to not create VM instance once you deploy it. You can use either virtctl or kubectl commands to start a VM instance.
sed -e "s/\${CLOUDINIT}/${CLOUDINIT}/1" kubevirt/ubuntu/ubuntu-vm-multi-nic.yaml | kubectl apply -f-
```

Connect to the VM and test connectivity using available network interfaces

```bash
# get public IP from one of the cluster nodes
NODE_IP=xx.xx.xx.xx
# ssh into ubuntu-vm-multi-nic
ssh -i $SSH_KEY $NODE_IP -p 30122 -l ubuntu

# list all interfaces and review assigned IPs
ip a

# view route table in the VM
ip route

# test connectivity to an endpoint using each interface
# NOTE: interface name may differ depending on what infrastructure you use for your cluster
ping -I enp1s0 -c1 -W2 8.8.8.8
ping -I enp2s0 -c1 -W2 8.8.8.8
ping -I enp3s0 -c1 -W2 8.8.8.8
```

### clean up Azure environment

```bash
cd terraform
terraform destroy -auto-approve
```
