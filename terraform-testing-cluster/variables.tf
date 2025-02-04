variable "aws_region" {
  description = "The region to deploy into."
  type        = string
  nullable    = false
}

variable "cluster_node_ami_id" {
  description = <<-EOT
    The ID of the AMI used for the kubernetes nodes.

    Note that this requires a pre-baked AMI. It must be possible to call kubeadm init or kubeadm join immediately and
    the system must be configured to work with the network plugin Flannel. See the README.md for more information.
  EOT
  type        = string
  nullable    = false
}

variable "cluster_subnet_id" {
  description = <<-EOT
    Specify the subnet in which to deploy the cluster. Note that nodes need internet access, such as over a NAT gateway,
    to retrieve artifacts.
  EOT
  type        = string
  nullable    = false
}

variable "cluster_pod_network_cidr" {
  description = "The CIDR that is cluster-internally used by the pods of the cluster. Must not overlap with external CIDRs."
  type        = string
  default     = "192.168.0.0/16"
}

variable "cluster_control_plane_node_ec2_instance_type" {
  description = <<-EOT
    Choose the type of the EC2 instance to use for the control plane node.

    Note: Do not go below t3a.small.
    1. It has exactly 2 vCPUs and 2 GB RAM, which is the lowest that Kubernetes will accept when kubeadm init is called.
       It is possible to overrule this by explicitly ignoring preflight errors - this is intentionally not implemented
       in the control plane node user data script.
    2. Two short attempts of using a t2.micro instance both resulted in the cluster API server becoming unstable and
       shortly after unresponsive.
  EOT
  type        = string
  default     = "t3a.small"
}

variable "cluster_worker_nodes_ec2_instance_type" {
  description = <<-EOT
    Choose the type of the EC2 instance to use for the worker nodes.

    Note: t2.micro can work for very simple deployments. However, for anything slightly more demanding, such as the
    kube-prometheus-stack helm chart, the use of t2.micro instances can lead to errors.
  EOT
  type        = string
  default     = "t3a.small"
}

variable "cluster_worker_nodes_count" {
  description = <<-EOT
    Specify the number of worker nodes to launch.

    Additional Info: This variable sets the desired count, max count, and minimum count in the AWS ASG that manages the
    worker nodes. Scaling policies are not set up in this configuration.
  EOT
  type        = number
  default     = 2
}

variable "cluster_join_command_s3_uri" {
  description = <<-EOT
    Specify an S3 URI to which the join command will be saved when the control plane node is initialized and which is
    retrieved by the worker nodes to join the cluster.
    The token that is part of the join command is configured to never expire.
  EOT
  type        = string
  nullable    = false
}

variable "cluster_export_kubeconfig_s3_uri" {
  description = "Specify an S3 URI to which the cluster admin kubeconfig will be saved to after the cluster is initialized."
  type        = string
  nullable    = false
}

variable "cluster_nlb" {
  description = <<-EOT
    Specify a public subnet ID, the path under which to perform health checks, and the ports on which to send traffic to
    the worker nodes to.
  EOT
  type = object({
    subnet_id          = string
    health_checks_path = string
    http_nodeport      = number
    https_nodeport     = number
  })
}


#region FluxCD Variables

variable "flux_cd_config" {
  description = <<-EOT
    If this object is not defined, the automatic FluxCD bootstrapping will be skipped. If it is defined, then either the
    variables flux_cd_github_credentials_pat and flux_cd_github_credentials_user_name must be specified, or the
    "credentials" attribute in this object variable. If both are defined, the dedicated credentials variables take
    precedence over the S3 bucket.
    repository  - The GitHub repository name
    branch      - The repository branch FluxCD uses
    path        - The repository path FluxCD is bootstrapped to, i.e. where the flux-system directory resides or is
                  created in if it does not exist yet
    credentials - (Optional) Specify two S3 URIs with one pointing to a text file containing the GitHub PAT and the
                  other pointing to a file containing the corresponding user name.
  EOT
  type = object({
    github_repository = string
    branch            = optional(string, "main")
    path              = optional(string, "./clusters/testing")
    credentials = optional(object({
      pat_file_s3_uri       = string
      user_name_file_s3_uri = string
    }), null)
  })
  nullable = true
  default  = null
  validation {
    condition = (
      var.flux_cd_config != null &&
      ((var.flux_cd_github_credentials_pat != null && var.flux_cd_github_credentials_user_name != null) ||
      var.flux_cd_config.credentials != null)
    )
    error_message = <<-EOT
      If the flux_cd_config variable is defined either the two variables flux_cd_github_credentials_pat and
      flux_cd_github_credentials_user_name must be specified or the "credentials" attribute in the flux_cd_config
      variable.
      EOT
  }
}

variable "flux_cd_github_credentials_pat" {
  description = <<-EOT
    Specifies the PAT used by FluxCD to access the GitHub repository. Alternatively, use S3 URIs to store the
    credentials (the PAT and user name) in S3 buckets - see the variable flux_cd_config.

    The PAT needs the following permissions:
      - Administration -> Access: Read-only
      - Contents -> Access: Read and write
      - Metadata -> Access: Read-only
  EOT
  type        = string
  sensitive   = true
  nullable    = true
  default     = null
}

variable "flux_cd_github_credentials_user_name" {
  description = <<-EOT
    Specifies the user name of the PAT used by FluxCD to access the GitHub repository. Alternatively, use S3 URIs to
    store the credentials (PAT and user name) in S3 buckets - see the variable flux_cd_config.
  EOT
  type        = string
  sensitive   = true
  nullable    = true
  default     = null
}

#endregion


#region AWS myApplication

variable "use_existing_aws_my_application_app_id" {
  description = "Optionally specify the ID of an AWS myApplication app to associate all deployed resources to it."
  type        = string
  nullable    = true
  default     = null
  validation {
    condition     = !(var.use_existing_aws_my_application_app_id != null && var.aws_my_application_app_name != null)
    error_message = "Variables aws_my_application_app_id and aws_my_application_app_name cannot both be set."
  }
}

# Warning: The following is convenient, but hacky.
variable "aws_my_application_app_name" {
  description = <<-EOT
    Optionally specify the app name to set up an AWS myApplication app to which resources will be associated to.

    Warning:
    This implementation is hacky. It will require that 'terraform apply' is called two times when deploying from the
    ground up, because it creates the AWS myApplication app and then assigns the application_tag to the aws provider
    default_tags dynamically, i.e. during deployment. Terraform notices this provider configuration change and throws
    an error. Since the myApplication resource is already created at that point, running the terraform apply command
    again will work without issues and all resources will be associated with the AWS myApplication app.
  EOT
  type        = string
  nullable    = true
  default     = null
}

#endregion
