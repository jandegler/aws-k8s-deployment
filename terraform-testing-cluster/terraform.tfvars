aws_region = "<REGION>"
# use_existing_aws_my_application_app_id = "<AWS_MY_APPLICATION_APP_ID>"

cluster_node_ami_id                          = "<AMI_ID>"       # Requires a pre-baked AMI
cluster_subnet_id                            = "<SUBNET_ID>"    # Such as a private subnet with NAT gateway route.
cluster_pod_network_cidr                     = "<CIDR>"         # Example: "192.168.0.0/16"
cluster_join_command_s3_uri                  = "<S3_URI>"       # Example: "s3://<BUCKET_ID>/cluster-join-command"
cluster_export_kubeconfig_s3_uri             = "<S3_URI>"       # Example: "s3://<BUCKET_ID>/cluster-admin-kubeconfig"
cluster_control_plane_node_ec2_instance_type = "t3a.small"
cluster_worker_nodes_ec2_instance_type       = "t3a.small"
cluster_worker_nodes_count                   = 3

cluster_nlb = {
  subnet_id          = "<SUBNET_ID>"
  health_checks_path = "/healthz"       # /healthz is the default for the Kubernetes ingress controller ingress-nginx.
  http_nodeport      = 30080
  https_nodeport     = 30443
}

flux_cd_config = {
  github_repository = "<REPOSITORY_NAME>"
  branch            = "main"
  path              = "./clusters/testing" # The path in which the flux-system folder is located or placed.
  # Instead of the following, it is also possible to pass the PAT and user name directly through setting environment
  # variables using the flux_cd_github_credentials_pat and flux_cd_github_credentials_user_name variables, i.e. using
  # `export TF_VAR_flux_cd_github_credentials_pat=<PAT>` and
  # `export TF_VAR_flux_cd_github_credentials_user_name=<USER_NAME>` to specify them before calling terraform apply.
  # credentials = {
  #   pat_file_s3_uri       = "s3://<BUCKET_ID>/github-pat"
  #   user_name_file_s3_uri = "s3://<BUCKET_ID>/github-user-name"
  # }
}
