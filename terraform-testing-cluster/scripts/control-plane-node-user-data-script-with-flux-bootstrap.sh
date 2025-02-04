#!/bin/bash

#### Control Plane Node
# Kubernetes initialization, configuration, and S3 uploads/downloads (join command, admin.conf, GitHub credentials)


### Variables

echo "Setting up variables"

## User Data Script - Manual HOME and USER Environment Variables Setup
# The user data script is executed in a non-interactive shell by the cloud-init process. As a consequence, environment
# variables like HOME and USER are not set. Some tools use these variables to find configuration files that are by
# convention often placed in the HOME folder. To make these work it can be a simple solution to set those variables
# manually. By default, the user data script on EC2 instances is executed as root user. Therefore, setting HOME=/root
# and USER=root as environment variables suffices.
export HOME=/root
export USER=root

## Join command and admin kubeconfig S3 URIs
JOIN_COMMAND_S3_URI=${TF_JOIN_COMMAND_S3_URI}
ADMIN_KUBECONFIG_S3_URI=${TF_KUBECONFIG_S3_URI}

## Specify Pod Network CIDR
CLUSTER_POD_NETWORK_CIDR=${TF_CLUSTER_POD_NETWORK_CIDR}

## FluxCD GitHub Credentials, Repository, Path, and Branch
GITHUB_REPOSITORY_NAME=${TF_GITHUB_REPOSITORY_NAME}
GITHUB_BRANCH=${TF_GITHUB_BRANCH}
GITHUB_DIRECTORY_PATH=${TF_GITHUB_DIRECTORY_PATH}

# S3-stored credentials or directly passed credentials
PAT_FILE_S3_URI=${TF_PAT_FILE_S3_URI}
USER_NAME_FILE_S3_URI=${TF_USER_NAME_FILE_S3_URI}

FLUX_CD_GITHUB_CREDENTIALS_PAT=${TF_FLUX_CD_GITHUB_CREDENTIALS_PAT}
FLUX_CD_GITHUB_CREDENTIALS_USER_NAME=${TF_FLUX_CD_GITHUB_CREDENTIALS_USER_NAME}

if [ -n "$FLUX_CD_GITHUB_CREDENTIALS_PAT" ]; then
  GITHUB_TOKEN=$FLUX_CD_GITHUB_CREDENTIALS_PAT
  GITHUB_USER_NAME=$FLUX_CD_GITHUB_CREDENTIALS_USER_NAME
else
  echo "Fetching GitHub credentials from S3 URIs"
  GITHUB_TOKEN=$(aws s3 cp "$PAT_FILE_S3_URI" -)
  GITHUB_USER_NAME=$(aws s3 cp "$USER_NAME_FILE_S3_URI" -)
fi

export GITHUB_TOKEN
export GITHUB_USER_NAME

## Flannel
FLANNEL_VERSION="0.26.3"
FLANNEL_FILE_URL="https://github.com/flannel-io/flannel/releases/download/v$(echo "$FLANNEL_VERSION")/kube-flannel.yml"

## Retrieve IPs from Metadata Service
echo "Fetching private and public IP from AWS EC2 instance metadata service V2"
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
# If a public IP is set up on control plane nodes' EC2 instances and the certificate of the API server is to function
# correctly when accessed through that public IP, uncomment the following line and add the IP via the Variable to the
# certSANs array under apiServer in the kubeadm-config.yaml.
# PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)



### Cluster Initialization
## Notes
# 1. If more than a single control plane node is intended to be launched, the controlPlaneEndpoint has to be specified
# in the kubeadm-config.yaml. It can also be specified just in case to avoid having to restart the cluster later.
# 2. Worker nodes will wait/be stuck in the preflight check step of the joining procedure until the control plane node
# is up and running for around 4-5 minutes. This wasn't the case when this script was still using kubeadm init command
# options instead of the kubeadm-config.yaml approach. It probably is a default set by Kubernetes when opting for the
# more modern approach of using a kubeadm configuration file. If it represent an issue, consider checking the Kubernetes
# documentation on the configuration files.

## Creating kubeadm configuration
# The service subnet specified here is the default.
cat <<EOF >> kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "$CLUSTER_POD_NETWORK_CIDR"
apiServer:
  extraArgs:
  - name: "advertise-address"
    value: "$PRIVATE_IP"
EOF

## Running the initialization command
# The init command will warn about the sandbox image of containerd not being the same as the one used by Kubernetes.
# However, the warning seems outdated, checking the wrong section of the toml.config file which changed with containerd
# version 2 and higher.
echo "Initializing Kubernetes cluster"
sudo kubeadm init --config ./kubeadm-config.yaml
rm kubeadm-config.yaml


### Copy kubectl config to s3 credentials bucket
echo "Uploading kubectl admin config to S3"
aws s3 cp /etc/kubernetes/admin.conf "$ADMIN_KUBECONFIG_S3_URI"


### Local kubeconfig setup for root user
echo "Copying kubectl admin config to /root/.kube/config"
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config # Configures kubeconfig for root user.


### Network CNI Plugin Setup - Flannel
echo "Setting up Flannel"
curl -sL $FLANNEL_FILE_URL -o ./kube-flannel.yml
sed -i "s|10.244.0.0/16|$(echo "$CLUSTER_POD_NETWORK_CIDR")|g" ./kube-flannel.yml
kubectl apply -f ./kube-flannel.yml
rm ./kube-flannel.yml


### Sharing join command
echo "Uploading join command to S3"
kubeadm token create --ttl 0 --print-join-command > k8s-join-command
aws s3 cp k8s-join-command "$JOIN_COMMAND_S3_URI"


### FluxCD Setup
# Check/Wait until worker nodes have joined the cluster so that the Flux controllers will function for the bootstrap process
echo "Checking if non-control-plane nodes are available in the cluster and are in the 'Ready' state before bootstrapping FluxCD"
RETRY_INTERVAL=15  # seconds
while true; do
    NON_CONTROL_PLANE_NODES_COUNT=$(kubectl get nodes --no-headers | grep -v " control-plane " | grep -c " Ready ")
    if [[ $NON_CONTROL_PLANE_NODES_COUNT -ge 1  ]]; then
        echo "Non-control-plane nodes in 'Ready' state are available. Proceeding."
        break
    fi

    echo "No non-control-plane nodes in 'Ready' state are available. Retrying in $RETRY_INTERVAL seconds..."
    sleep $RETRY_INTERVAL
done

echo "Bootstrapping FluxCD"
flux bootstrap github \
  --token-auth \
  --owner="$GITHUB_USER_NAME" \
  --repository="$GITHUB_REPOSITORY_NAME" \
  --branch="$GITHUB_BRANCH" \
  --path="$GITHUB_DIRECTORY_PATH" \
  --personal

echo "Control plane node script with FLuxCD bootstrapping finished"

