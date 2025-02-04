#!/bin/bash

##### Prepares the environment to support the execution of kubernetes control plane nodes and worker nodes
    # The goal is that kubeadm init and join commands can be executed immediately on freshly started instances
    # to run a cluster using Flannel as the Kubernetes network plugin.
# Implemented for an Ubuntu 24.04 LTS server distribution that is provided as an AMI by AWS.
# Installs kubeadm, kubectl, kubelet, containerd, runc, FluxCD CLI, and AWS CLI.
# Configures the system to work for Kubernetes and the Kubernetes network plugin Flannel.
# The primitive CNI Plugins are not installed by this script as these came preinstalled with the Ubuntu AMI.

## How to use this script?
# Start an EC2 Instance that has internet access with the AWS AMI Ubuntu 24.04 (or higher) LTS server distribution.
# Run the script, either by passing it as a user data script or by running the command manually after using SSH to
# to connect to the instance. Once the script finished its execution, create an AMI from the EC2 instance.



#### Script Notes

# - For information on the allowed combinations of versions between containerd, runc, and kubernetes, see the containerd
#   GitHub repository. It provides a table on the allowed combinations.
# - Kubernetes worker nodes don't need kubectl or FluxCD installed. However, to keep it simple (generating a single AMI),
#   this script serves as the base for both master and worker nodes.
# - Many required tools for containers are not available via the apt package manager. Other distributions may offer more
#   in this regard, such as Alpine distributions that provide seemingly all relevant tools in the apk package manager.



#### Script Configuration and Variables


### Script Configuration
set -e # Exit immediately when a command exists with a non-zero status (usually implies an error).
set -u # Treat unset variables as an error during substitution.

### Variables
echo "Setting up variables"

## AWS CLI
AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" # Script expects a zip.

## Kubernetes
KUBERNETES_VERSION="1.31.4"

KUBERNETES_APT_REPOSITORY_KEY_URL="https://pkgs.k8s.io/core:/stable:/v$(echo $KUBERNETES_VERSION | cut -d'.' -f1-2)/deb/Release.key" # cut is used to extract the major.minor version part. cut is newer than awk and considered a bit more efficient. It is focussed on the "split" part of the awk functionalities.
KUBERNETES_APT_REPOSITORY_URL="https://pkgs.k8s.io/core:/stable:/v$(echo $KUBERNETES_VERSION | cut -d'.' -f1-2)/deb/" # Including a forward slash at the end is not necessary but considered good practice as it let's one know if a path is referring to a file or directory.
APT_KUBEADM_VERSION="$KUBERNETES_VERSION-1.1" # The version behind the kubernetes version variable stands for the apt-package revision version.
APT_KUBELET_VERSION="$KUBERNETES_VERSION-1.1"
APT_KUBECTL_VERSION="$KUBERNETES_VERSION-1.1"

## containerd
CONTAINERD_VERSION="2.0.1"
CONTAINERD_FILE_URL="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-$(dpkg --print-architecture).tar.gz"
CONTAINERD_CHECK_SUM_URL="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-$(dpkg --print-architecture).tar.gz.sha256sum"
# For running containerd via systemd, a configuration file must be installed as well.
CONTAINERD_SYSTEMD_CONFIGURATION_FILE_URL="https://raw.githubusercontent.com/containerd/containerd/main/containerd.service"

## runc
RUNC_VERSION="1.2.3"
RUNC_FILE_URL="https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.$(dpkg --print-architecture)"
RUNC_CHECK_SUM_URL="https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.sha256sum"

## FluxCD CLI
FLUXCD_CLI_VERSION="2.4.0"
FLUXCD_FILE_URL="https://github.com/fluxcd/flux2/releases/download/v${FLUXCD_CLI_VERSION}/flux_${FLUXCD_CLI_VERSION}_linux_$(dpkg --print-architecture).tar.gz"
FLUXCD_CHECK_SUM_URL="https://github.com/fluxcd/flux2/releases/download/v${FLUXCD_CLI_VERSION}/flux_${FLUXCD_CLI_VERSION}_checksums.txt"


#### General Environment Configuration - Linux


### IPv4 Traffic Forwarding

# Required for Kubernetes to redirect traffic between network interfaces.
# It is a Linux kernel feature that is often disabled by default in non-container-focussed distributions.

## Verification
# sysctl net.ipv4.ip_forward # If forwarding is enabled, it would return net.ipv4.ip_forward = 1.

echo "Enabling IP forwarding"
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
# Apply sysctl params without reboot
sysctl --system


### Disabling Swap
echo "Disabling swap"

## Verification
# cat /proc/swaps # Should return an empty list, indicating that no swap devices, i.e. filesystems, are mounted/used.

## Temporarily
swapoff -a

## Permanently
# Note: This permanent solution apparently may not always properly apply immediately even if mount -a is called, which
#       is why the temporary solution is kept in parallel.
sed -i '/swap/d' /etc/fstab
mount -a # Causes all the filesystems to be remounted to update the changes to /etc/fstab.



### Kernel Modules
# Enabling overlay for containerd and br_netfilter for Kubernetes networking (Flannel in this case)
echo "Enabling overlay and br_netfilter kernel modules"
tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter



#### Repository and Dependencies Installation


### General Tools
echo "Install general tooling via apt"
apt-get update
apt-get install -y ca-certificates curl unzip


### AWS CLI
echo "Install AWS CLI"
curl "$AWS_CLI_URL" -o "awscliv2.zip"
unzip awscliv2.zip
rm awscliv2.zip
./aws/install


### containerd and runc

## containerd
echo "Installing containerd"
curl -sL $CONTAINERD_FILE_URL -o containerd.tar.gz
curl -sL $CONTAINERD_CHECK_SUM_URL -o containerd.tar.gz.sha256sum

echo "$(cat containerd.tar.gz.sha256sum | cut -d ' ' -f 1 )  containerd.tar.gz" | sha256sum --check --status
if [ $? -ne 0 ]; then
    echo "Checksum verification failed for containerd!"
    exit 1
fi

tar -C /usr/local -xzf containerd.tar.gz
rm containerd.tar.gz containerd.tar.gz.sha256sum

# Both containerd and kubelet must use the same system resource manager, systemd in this case
echo "Configure containerd and kubelet for systemd"
mkdir /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i "/\[plugins\.'io.containerd.cri.v1.runtime'\.containerd\.runtimes\.runc\.options\]/a SystemdCgroup = true" /etc/containerd/config.toml

# Used to make an already running containerd daemon aware of the configuration change. In this case, the daemon isn't running yet.
# systemctl restart containerd

# Configure systemd to run the containerd daemon.
curl -sL $CONTAINERD_SYSTEMD_CONFIGURATION_FILE_URL -o /lib/systemd/system/containerd.service
systemctl daemon-reload # This reloads the systemd manager configuration.
systemctl enable --now containerd


## runc
echo "Installing runc"
curl -sL $RUNC_FILE_URL -o runc.$(dpkg --print-architecture)
curl -sL $RUNC_CHECK_SUM_URL -o runc.sha256sum

# grep is required due to runc.sha256sum containing multiple lines with hashes for various platforms.
echo "$(cat runc.sha256sum | grep "runc.$(dpkg --print-architecture)" | cut -d ' ' -f 1 )  runc.$(dpkg --print-architecture)" | sha256sum --check --status
if [ $? -ne 0 ]; then
    echo "Checksum verification failed for runc!"
    exit 1
fi

install -m 755 runc.$(dpkg --print-architecture) /usr/local/sbin/runc
rm runc.$(dpkg --print-architecture) runc.sha256sum

# runc --version # Optional for verifying version.



### Kubernetes
## Repository
echo "Add Kubernetes repository to apt"
curl -fsSL $KUBERNETES_APT_REPOSITORY_KEY_URL | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${KUBERNETES_APT_REPOSITORY_URL} /" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
## Installation
echo "Installing kubeadm, kubectl, kubelet"
# The kubernetes repository packages kubernetes-cni and cri-tools are installed implicitly as well since those are dependencies.
apt-get install -y kubeadm=$APT_KUBEADM_VERSION kubelet=$APT_KUBELET_VERSION kubectl=$APT_KUBECTL_VERSION
apt-mark hold kubelet kubeadm kubectl

## Pre-pull Images
# This reduces the load while initializing or joining a the cluster. Also convenient to set up Kubernetes nodes in
# air-gapped/private environments by not having to store these images locally.
kubeadm config images pull # The pulled images' versions will follow the kubeadm version.



### FluxCD
echo "Installing FluxCD"
curl -sL $FLUXCD_FILE_URL -o flux.tar.gz
curl -sL $FLUXCD_CHECK_SUM_URL -o flux_checksums.txt

echo "$(cat flux_checksums.txt | grep "flux.*linux.*$(dpkg --print-architecture)" | cut -d ' ' -f 1 )  flux.tar.gz" | sha256sum --check --status # Remove --status to show output.
if [ $? -ne 0 ]; then
    echo "Checksum verification failed for FluxCD!"
    exit 1
fi

tar -C /usr/local/bin -xzf flux.tar.gz

rm flux.tar.gz flux_checksums.txt
# flux --version # Optional for verifying version.




#### Cleanup
echo "Cleanup apt"
apt-get clean # Cleans up temporary files of apt.


echo "Pre-baked AMI setup script finished successfully."

