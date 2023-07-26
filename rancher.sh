#!/bin/bash

#######################################
# Print a message in a given color.
# Arguments:
#   Color. eg: green, red
#######################################
function print_color(){
  NC='\033[0m' # No Color

  case $1 in
    "green") COLOR='\033[0;32m' ;;
    "red") COLOR='\033[0;31m' ;;
    "blue") COLOR='\033[0;34m' ;;
    "*") COLOR='\033[0m' ;;
  esac

  echo -e "${COLOR} $2 ${NC}"
}

#######################################
# Check the status of a given service. If not active exit script
# Arguments:
#   Service Name. eg: nfs-server, chrony
#######################################
function check_service_status(){
  service_is_active=$(sudo systemctl is-active $1)

  if [ $service_is_active = "active" ]
  then
    print_color "green" "$1 is active and running"
  else
    print_color "red" "$1 is not active/running"
    exit 1
  fi
}

echo "---------------- Setup Rancher Server ------------------"

# Update OS Pathch
print_color "green" "Update OS Patch.. "
apt update -y && apt upgrade -y
print_color "green" "Update Succed"

# Set timezone to Bangkok
print_color "green" "Set Timezone to Bangkok.. "
timedatectl set-timezone Asia/Bangkok

# Install chorony service for synctime
print_color "green" "Installing Chrony service.. "
apt install chrony -y
sed -i 's/pool/#pool/g'  /etc/chrony/chrony.conf
sed -i 's/#pool 2.ubuntu.#pool.ntp.org iburst maxsources 2/server clock.inet.co.th/g'  /etc/chrony/chrony.conf
systemctl restart chrony

check_service_status chrony

# Disable swap
print_color "green" "Disable swap.. "
sudo swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab


# Install nfs server
print_color "green" "Installing nfs-server service.. "
apt install nfs-kernel-server -y
systemctl enable nfs-server
systemctl start nfs-server

check_service_status nfs-server

# Install RKE2 service
print_color "green" "Installing RKE2 service.. "
sudo bash -c 'curl -sfL https://get.rke2.io | \
  INSTALL_RKE2_CHANNEL="v1.24" \
  sh -'

sudo mkdir -p /etc/rancher/rke2
sudo bash -c 'echo "write-kubeconfig-mode: \"0644\"" > /etc/rancher/rke2/config.yaml'


sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

check_service_status rke2-server


# Install Kubectl command
print_color "green" "Installing kubectl command.. "
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Create directory for kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


# Test Kubectl command
node_ready=$(kubectl get nodes --no-headers | awk '{print $2}')
while true
do
    if [ "$node_ready" != "Ready" ]
    then
        print_color "red" "Node isn't ready yet"
        sleep 5
        continue
    else
        print_color "green" "Node is Ready"
        break
    fi
done

echo "---------------- Wait POD RUNNING.. ------------------"
sleep 15
kubectl get pods --all-namespaces
sleep 2

# Install Helm3
print_color "green" "Installing Helm3 service.. "
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 \
  | bash

version_of_helm=$(helm version --client)
print_color "green" "$version_of_helm"

helm ls --all-namespaces
sleep 5

# Add Cert-manager repo to helm
helm repo add jetstack https://charts.jetstack.io

# Install Cert-manager
print_color "green" "Installing Cert-manager.. "
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.11.0 \
  --set installCRDs=true \
  --create-namespace
sleep 10
# Check Status Certi-manager
kubectl -n cert-manager rollout status deploy/cert-manager
sleep 2

kubectl -n cert-manager rollout status deploy/cert-manager-webhook
sleep 2

# Add Rancher repo to helm
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

# Install rancher
print_color "green" "Installing Rancher service.. "
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.local \
  --set replicas=1 \
  --version 2.7.4 \
  --create-namespace
sleep 5
# Check rancher status
while true
do 
  curl -kv https://rancher.local 2>&1 | grep -q "dynamiclistener-ca"
    if [ $? != 0 ]
        then print_color "red" "Rancher isn't ready yet"
        sleep 5
        continue
    else
        print_color "green" "Rancher is Ready"
        break
    fi
done




