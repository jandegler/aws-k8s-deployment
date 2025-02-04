# Kubernetes Cluster Deployment on AWS

This IaC and GitOps repository facilitates the deployment of a self-managed Kubernetes cluster on AWS with Terraform and
FluxCD. It is designed for experimentation and hands-on learning in a production-like environment, emphasizing
simplicity and cost efficiency over strict security and high availability.

**Disclaimer:** This repository is **not** suited for production use and deploying it will incur AWS costs.

## Repository Overview

- terraform-cluster-environment
  - Deploys VPC components that serve as the base for the terraform-cluster configuration.
- terraform-cluster
  - Deploys the cluster components and runs user data scripts on the EC2 instances to initialize the cluster, join
    worker nodes, and optionally bootstraps FluxCD.
- fluxcd-testing-repository
  - A simple FluxCD repository that can be used as a starting point for this deployment.
  - Configures the cluster to integrate with the example values provided for the input variables "cluster_nlb" and
    "flux_cd_config" in the terraform-cluster configuration. This means that health checks for HTTP and HTTPS
    of the Network Load Balancer (NLB) should succeed immediately and using a browser to navigate to the DNS name of the
    NLB should present the Grafana login page.
  - Includes ingress-nginx, cert-manager, Prometheus, Grafana, Alertmanager, and Podinfo
    - For convenience, path-based ingress is implemented for Prometheus, Grafana, Alertmanager, and Podinfo:  
      `/prometheus/`, `/alertmanager/`, `/podinfo/`, and `/` for Grafana.
      - The Grafana default username and password are "admin" and "prom-operator".
      - Consider moving Grafana into a dedicated domain or subdomain to avoid path collisions.

## terraform-cluster-environment

### Main Components

- VPC
  - Referenced by ID or newly created by specifying a CIDR.
- Public Subnet
- Private Subnet
- EC2 Instance Connect Endpoint
  - Used to connect to instances in the VPC via SSH. 
  - Its security group allows SSH egress traffic on port 22.
- S3 Gateway Endpoint
  - No IAM trust policy is set on the gateway. Therefore, any entity is allowed to access S3 resources over the gateway,
    if their IAM permissions suffice.
- Internet Gateway
  - Referenced by ID or newly created if no ID is specified.
- NAT Gateway (optional)
- S3 Bucket (optional)
- AWS myApplication (optional)
  - Referenced by ID or newly created by specifying a name.
  - All created resources will be associated to the app.

### Architecture Diagram

The following diagram represents the connectivity between the subnets and gateways defined by the routes of the route
tables.

![Alt cluster-environment-architecture-diagram](./cluster-environment-architecture-diagram.svg)

## terraform-cluster

### Main Components

- EC2 Instances
  - Control Plane and Worker Nodes
    - The number of worker nodes can be selected freely.
    - Only one control plane node is deployed.
  - Ingress and Egress
    - Egress internet traffic is possible over the NAT gateway.
    - Ingress internet traffic is possible over the NLB.
    - Ingress SSH traffic is possible over the EC2 Instance Connect endpoint.
    - The security groups on the nodes allow all ingress and egress of any protocol type.
      - For most cases TCP and UDP would suffice together with SSH ingress for troubleshooting the instances.
      - It would be possible to reduce the IP range to only the VPC CIDR by using the proxy protocol v2 in the NLB
        and the ingress-controller.
  - IAM Instance Profiles
    - While many other access control mechanisms are kept permissive the instance profiles must be kept restrictive, 
      because the blast radius of a security breach could otherwise affect the entire AWS account. Consider IRSA for
      cluster workloads that need AWS IAM permissions.
    - Worker nodes have s3:ListBucket and s3:GetObject permissions for all S3 resources. The control plane node
      additionally has the s3:PutObject permission. **These permissions are not restricted to specific S3 resources.**
      Consider restricting these permissions further.
  - User Data Scripts
    - These automate the initialization of the cluster, the joining of worker nodes to it, and optionally the
      bootstrapping of FluxCD.
  - AWS ASG
    - The worker nodes are deployed using an AWS ASG. However, no auto-scaling policies are set up.
- AWS NLB
  - Forwards traffic to the cluster's worker nodes. 
  - Ingress traffic for TCP on port 80 and on port 443 is allowed.
  - Egress TCP traffic to the worker nodes is allowed.
- AWS myApplication (optional)
  - Referenced by ID or newly created by specifying a name.
  - All created resources will be associated to the app.
  
### Architecture Diagram

The following diagram visualizes the terraform-cluster configuration in combination with the
terraform-cluster-environment configuration.

To reduce visual clutter, the connections between the EC2 Instance Connect endpoint and the EC2 instances are omitted.
Furthermore, while not included in the diagram, external DNS management to redirect traffic to the NLB's DNS name from
custom domains and their subdomains should be considered to enable hostname-based cluster ingress, such as by using
AWS Route 53.

![Alt cluster-architecture-diagram](./cluster-architecture-diagram.svg)

## Design Considerations

- S3
  - Used to share cluster data during initialization and joining of worker nodes.
    - The join command, admin kubeconfig, and optionally the PAT and username for the FluxCD Git-repository access are
      shared by specifying S3 URIs in the Terraform configuration.
  - S3 was chosen for simplicity and cost efficiency. Sharing sensitive information as those listed above typically
    require higher security in which case S3 should be replaced with a secrets manager, such as AWS Secrets Manager or
    AWS SSM, potentially in combination with an interface endpoint for private access.
- EC2 Instance Connect Endpoint
  - Used to avoid exposure of cluster nodes to direct ingress internet traffic. All traffic from outside the VPC CIDR
    must pass through the NLB or the EC2 Instance Connect endpoint.
  - Secures SSH access to instances with AWS IAM access control.
- NAT Gateway
  - Drastically simplifies the cluster setup and speeds up testing iterations by removing the need for private
    artifact repositories and a private Git repository.
- NLB
  - Why not use the AWS provided ingress controller to automate the deployment of LBs or use an AWS ALB?<br>
    - The NLB suffices the purpose of this deployment. The intention is to focus on Kubernetes and to keep the setup
      simple. For traffic control on the OSI layer 7 an ingress controller can be used.
    - The AWS ALB must be deployed into two subnets in two different AZs at a minimum. The AWS NLB does not have this
      restriction.
    - The AWS provided ingress controller would require changing the network plugin - Flannel is not supported.

## Getting Started

The following describes the steps required to fully deploy the cluster with terraform and FluxCD.

Note that this is not intended as an exhaustive guide that explains each step in detail. Knowledge about Git, Terraform,
and AWS is expected.

When deploying the following configurations, adjust the input variables in the terraform.tfvars files and read the
descriptions in the variables.tf files as needed. Furthermore, each configuration provides Terraform output that should
suffice to complete the deployment without needing to read out AWS resource information manually.

**Prerequisites**
- An AWS account and sufficient IAM permissions to deploy the resources.
- Terraform CLI
- AWS CLI

### 1. Download the Git repository

Clone the Git repository or download the latest version of it.

### 2. Deploying the terraform-cluster-environment configuration

Adjust the Terraform input variables as needed and deploy the configuration. Enable the NAT gateway and the S3 bucket to
use them for the following terraform-cluster deployment.

### 3. Deploying the terraform-cluster

This configuration expects a pre-baked AMI for the control plane and worker nodes to reduce unnecessary overhead when
starting up nodes. The nested Terraform configuration terraform-ec2-instance-for-pre-baked-ami can be used to create
such an AMI. However, any AMI that fulfills the following listed requirements can work.

#### AMI Requirements

- Testing and setup was performed on an Ubuntu 24.04 LTS server distribution. Any other distribution may require
  updating the user data scripts.
- The chosen distribution must be supported by EC2 Instance Connect to enable SSH access.
- The kubeadm init, kubeadm join, and flux bootstrap commands can be called immediately and the join command can be
  stored to and retrieved from S3.
  - Requires the tools kubeadm, kubectl, kubelet, containerd, runc, FluxCD CLI, and AWS CLI. **The versions for all
    these tools are determined by the used AMI.**
- The system is configured to function with containerd and the Kubernetes network plugin, i.e. Flannel.
  - IP forwarding and the Linux kernel modules br_netfilter and overlay must be enabled.

#### Creating the pre-baked AMI with the terraform-ec2-instance-for-pre-baked-ami configuration

Tools like HashiCorp Packer can be used to automate the process of creating pre-baked AMIs. However, the following
solution avoids the use of an additional tool at the cost of requiring manual steps.

The terraform configuration provided under `./terraform-cluster/terraform-ec2-instance-for-pre-baked-ami` can be
used to launch an EC2 instance that will execute a user data script to install all prerequisites on an Ubuntu 24.04 LTS
server distribution. An AMI can then be created from the running instance.<br>
The versions of the installed tools can be changed manually by updating the script under
`terraform-ec2-instance-for-pre-baked-ami/scripts`.

Adjust the variables of the Terraform configuration and use the following commands to create the pre-baked AMI.

```bash
# Initialize the Terraform configuration and deploy it
terraform init
terraform apply

# Use EC2 Instance Connect to access the EC2 instance via SSH either with the following command or by using the AWS
# console.
# Read the EC2 instance ID and region from the Terraform output.
aws ec2-instance-connect ssh \
    --instance-id "<EC2_INSTANCE_ID>" \
    --os-user root \
    --region "<REGION>" \
    --connection-type eice
# Check the cloud init output log. If the script ran to completion one of the lines at the end of the text file should
# read: "Pre-baked AMI setup script finished successfully."
nano /var/log/cloud-init-output.log

# Leave SSH and execute the following command to create an AMI from the running instance.
aws ec2 create-image \
    --instance-id "<EC2_INSTANCE_ID>" \
    --name cluster-node \
    --region "<REGION>" \
    --reboot \
    --tag-specifications "ResourceType=image,Tags=[{Key=Name,Value=cluster-node}]"
# Use the AMI ID output from the previous command to wait for the AMI to be available
# The following command will return once the AMI is ready - this can take around 5 or more minutes
aws ec2 wait image-available \
    --region "<REGION>" \
    --image-ids "<AMI_ID>"

# Destroy the Terraform configuration
terraform destroy
```

#### Deploying the terraform-cluster configuration

Many of the variables can be set using the output from the terraform-cluster-environment configuration.
Furthermore, when using the FluxCD repository that is part of this repository, the NodePorts that are used for
ingress into the cluster will be 30080 for HTTP and 30443 for HTTPS.

The control plane user data script expects a GitHub repository for bootstrapping FluxCD. If any other Git repository
provider is chosen, minor changes to the user data script and the Terraform configuration will be necessary.

To use the FluxCD repository, first initialize the desired GitHub repository with FluxCD by deploying the cluster at
least once. Then push the contents of the fluxcd-testing-repository folder to it.

The NLB DNS name can be used to access the cluster. It takes between 5 and 10 minutes for the EC2 instances to start up,
the cluster to be initialized, and FluxCD to reconcile the Git repository with the cluster.
