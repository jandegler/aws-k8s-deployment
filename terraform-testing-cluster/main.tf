terraform {
  required_version = "~> 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.0"
    }
  }
}

#region Data

data "aws_servicecatalogappregistry_application" "use_existing" {
  count = var.use_existing_aws_my_application_app_id != null ? 1 : 0

  provider = aws.provider_for_aws_my_application_setup

  id = var.use_existing_aws_my_application_app_id
}

data "aws_subnet" "cluster_nodes" {
  id = var.cluster_subnet_id
}

data "aws_vpc" "this" {
  id = data.aws_subnet.cluster_nodes.vpc_id
}

data "local_file" "control-plane-node-user-script" {
  filename = "${path.module}/scripts/control-plane-node-user-data-script.sh"
}

data "local_file" "control-plane-node-user-script-with-flux-bootstrap" {
  filename = "${path.module}/scripts/control-plane-node-user-data-script-with-flux-bootstrap.sh"
}

data "local_file" "worker-node-user-script" {
  filename = "${path.module}/scripts/worker-node-user-data-script.sh"
}

#endregion


#region AWS myApplication

resource "aws_servicecatalogappregistry_application" "new_creation" {
  count = (var.aws_my_application_app_name != null && var.use_existing_aws_my_application_app_id == null) ? 1 : 0

  provider = aws.provider_for_aws_my_application_setup

  name        = var.aws_my_application_app_name
  description = "Includes the resources of the Kubernetes cluster deployment."
}

#endregion


#region Ingress - Network Load Balancer

resource "aws_lb" "nlb" {
  name_prefix                      = "cl-nlb"
  internal                         = false
  enable_cross_zone_load_balancing = false
  load_balancer_type               = "network"
  subnets                          = [var.cluster_nlb.subnet_id]
  security_groups                  = [aws_security_group.cl_nlb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.nlb.arn
  protocol          = "TCP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.worker_nodes_http.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.nlb.arn
  protocol          = "TCP"
  port              = 443

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.worker_nodes_https.arn
  }
}

#endregion


#region Control Plane Node

# Note: For now, only one control plane node is created. To increase the number, this configuration would have to be
# extended as well as the user data script in which the kubeadm configuration would have to be updated to enable a
# shared DNS for the control plane nodes.
resource "aws_instance" "control_plane_node" {
  subnet_id              = data.aws_subnet.cluster_nodes.id
  vpc_security_group_ids = [aws_security_group.worker_node.id]
  metadata_options {
    http_endpoint = "enabled"
    http_put_response_hop_limit = 2
    http_tokens   = "required"
  }

  user_data = (
    var.flux_cd_config != null
    ? base64encode(templatefile(data.local_file.control-plane-node-user-script-with-flux-bootstrap.filename, {
      TF_JOIN_COMMAND_S3_URI      = var.cluster_join_command_s3_uri
      TF_KUBECONFIG_S3_URI        = var.cluster_export_kubeconfig_s3_uri
      TF_CLUSTER_POD_NETWORK_CIDR = var.cluster_pod_network_cidr
      TF_GITHUB_REPOSITORY_NAME   = var.flux_cd_config.github_repository
      TF_GITHUB_BRANCH            = var.flux_cd_config.branch
      TF_GITHUB_DIRECTORY_PATH    = var.flux_cd_config.path
      TF_PAT_FILE_S3_URI = (
        (var.flux_cd_github_credentials_pat == null || var.flux_cd_github_credentials_user_name == null)
        ? var.flux_cd_config.credentials.pat_file_s3_uri
        : ""
      )
      TF_USER_NAME_FILE_S3_URI = (
        (var.flux_cd_github_credentials_pat == null || var.flux_cd_github_credentials_user_name == null)
        ? var.flux_cd_config.credentials.user_name_file_s3_uri
        : ""
      )
      TF_FLUX_CD_GITHUB_CREDENTIALS_PAT = (
        (var.flux_cd_github_credentials_pat != null && var.flux_cd_github_credentials_user_name != null)
        ? var.flux_cd_github_credentials_pat
        : ""
      )
      TF_FLUX_CD_GITHUB_CREDENTIALS_USER_NAME = (
        (var.flux_cd_github_credentials_pat != null && var.flux_cd_github_credentials_user_name != null)
        ? var.flux_cd_github_credentials_user_name
        : ""
      )
    }))
    : base64encode(templatefile(data.local_file.control-plane-node-user-script.filename, {
      TF_JOIN_COMMAND_S3_URI      = var.cluster_join_command_s3_uri
      TF_KUBECONFIG_S3_URI        = var.cluster_export_kubeconfig_s3_uri
      TF_CLUSTER_POD_NETWORK_CIDR = var.cluster_pod_network_cidr
    }))
  )

  tags = {
    Name = "control-plane-node"
  }

  launch_template {
    id = aws_launch_template.control_plane_node.id
  }
}

resource "aws_launch_template" "control_plane_node" {
  name_prefix   = "control-plane-node-launch-template"
  image_id      = var.cluster_node_ami_id
  instance_type = var.cluster_control_plane_node_ec2_instance_type
  credit_specification {
    cpu_credits = "standard" # This option is instance type dependent. T2 sets it to standard, T3 to unlimited.
  }
  iam_instance_profile {
    arn = aws_iam_instance_profile.control_plane_node.arn
  }

  instance_initiated_shutdown_behavior = "terminate"
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "control-plane-node"
    }
  }
}

#endregion


#region Worker Nodes - EC2 Autoscaling Group and Launch Template

resource "aws_autoscaling_group" "worker_nodes" {
  name_prefix               = "worker-nodes-autoscaling-group"
  desired_capacity          = var.cluster_worker_nodes_count
  max_size                  = var.cluster_worker_nodes_count
  min_size                  = var.cluster_worker_nodes_count
  health_check_grace_period = 60
  # While ELB health checks are more sophisticated and preferable when trying to keep the availability of services high,
  # they also may result in EC2 instances being terminated and replaced faster than one would like, which is why in this
  # configuration they are not used by default. The NLB will still correctly display if cluster ingress health check
  # endpoints work correctly or not, but the ASG will not take action unless the EC2 instances themselves are
  # unhealthy.
  # For example, the health check grace period may have to be adjusted depending on the chosen instance type if the
  # health check type is set to "ELB", because instances must not only run but also join the cluster, and set
  # up the ingress health check endpoints in time. Furthermore, when a health check on a node fails, it might be
  # valuable to SSH onto the instance for troubleshooting, which is difficult if the ASG is quick to replace such
  # instances.
  # health_check_type = "ELB" # defaults to "EC2"
  target_group_arns   = [aws_lb_target_group.worker_nodes_http.arn, aws_lb_target_group.worker_nodes_https.arn]
  vpc_zone_identifier = [data.aws_subnet.cluster_nodes.id]
  launch_template {
    id = aws_launch_template.worker_node.id
  }
}

resource "aws_launch_template" "worker_node" {
  name_prefix            = "worker-node-launch-template"
  image_id               = var.cluster_node_ami_id
  instance_type          = var.cluster_worker_nodes_ec2_instance_type
  vpc_security_group_ids = [aws_security_group.worker_node.id]
  credit_specification {
    cpu_credits = "standard"
  }
  iam_instance_profile {
    arn = aws_iam_instance_profile.worker_node.arn
  }
  user_data = base64encode(templatefile(data.local_file.worker-node-user-script.filename, {
    TF_JOIN_COMMAND_S3_URI = var.cluster_join_command_s3_uri
  }))

  metadata_options {
    http_endpoint = "enabled"
    http_put_response_hop_limit = 2
    http_tokens   = "required"
  }

  instance_initiated_shutdown_behavior = "terminate"
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "worker-node"
    }
  }
}

resource "aws_lb_target_group" "worker_nodes_http" {
  vpc_id      = data.aws_vpc.this.id
  name_prefix = "http"
  protocol    = "TCP"
  port        = var.cluster_nlb.http_nodeport

  health_check {
    path                = var.cluster_nlb.health_checks_path
    protocol            = "HTTP"
    matcher             = "200-299"
    timeout             = 5
    interval            = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  deregistration_delay = 20
}

resource "aws_lb_target_group" "worker_nodes_https" {
  vpc_id      = data.aws_vpc.this.id
  name_prefix = "https"
  protocol    = "TCP"
  port        = var.cluster_nlb.https_nodeport

  health_check {
    path                = var.cluster_nlb.health_checks_path
    # NLB health checks do not validate certificates. Therefore, even self-signed certificates are accepted.
    protocol            = "HTTPS"
    matcher             = "200-299"
    timeout             = 5
    interval            = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  deregistration_delay = 20
}

#endregion


#region Security Groups

resource "aws_security_group" "cl_nlb" {
  name_prefix = "cl-nlb"
  vpc_id      = data.aws_vpc.this.id

  tags = {
    Name = "cl-nlb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cl_nlb_http" {
  security_group_id = aws_security_group.cl_nlb.id

  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "cl_nlb_https" {
  security_group_id = aws_security_group.cl_nlb.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "cl_nlb_to_worker_nodes_tcp" {
  security_group_id = aws_security_group.cl_nlb.id

  referenced_security_group_id = aws_security_group.worker_node.id
  ip_protocol                  = "tcp"
  # The port range 30000 to 32767 would probably suffice even independent of the cluster configuration as that is the
  # port range for NodePorts in Kubernetes that are used for ingress.
  from_port = 0
  to_port   = 65535
}

resource "aws_security_group" "control_plane_node" {
  name_prefix = "control-plane-node-sg"
  vpc_id      = data.aws_vpc.this.id

  tags = {
    Name = "control-plane-node-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_node_all" {
  security_group_id = aws_security_group.control_plane_node.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "control_plane_node_all" {
  security_group_id = aws_security_group.control_plane_node.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "worker_node" {
  name_prefix = "worker-node-sg"
  vpc_id      = data.aws_vpc.this.id

  tags = {
    Name = "worker-node-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "worker_node_all_private" {
  security_group_id = aws_security_group.worker_node.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "worker_node_all" {
  security_group_id = aws_security_group.worker_node.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

#endregion


#region IAM EC2 Instance Profiles, Roles, and Policies

resource "aws_iam_instance_profile" "control_plane_node" {
  name_prefix = "control-plane-nodes"
  role        = aws_iam_role.control_plane_node_instance_profile_role.name
}

resource "aws_iam_role" "control_plane_node_instance_profile_role" {
  name_prefix = "control-plane-nodes"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "control_plane_node_instance_profile_policy" {
  name_prefix = "control-plane-nodes"
  role        = aws_iam_role.control_plane_node_instance_profile_role.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowListPutAndGetOfBucketsObjects",
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject"
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "worker_node" {
  name_prefix = "worker-nodes"
  role        = aws_iam_role.worker_node_instance_profile_role.name
}

resource "aws_iam_role" "worker_node_instance_profile_role" {
  name_prefix = "worker-nodes"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "worker_node_instance_profile_policy" {
  name_prefix = "worker-nodes"
  role        = aws_iam_role.worker_node_instance_profile_role.name

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowListAndGetBucketsObjects",
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetObject"
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}

#endregion