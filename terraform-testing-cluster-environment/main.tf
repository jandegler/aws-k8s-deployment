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

data "aws_region" "current" {}

data "aws_vpc" "this" {
  id = var.use_existing_vpc_id != null ? var.use_existing_vpc_id : aws_vpc.new_creation[0].id
}

data "aws_internet_gateway" "this" {
  internet_gateway_id = var.use_existing_internet_gateway_id != null ? var.use_existing_internet_gateway_id : aws_internet_gateway.new_creation[0].id
}

# By default, if no policy is specified for an endpoint, such as the S3 gateway endpoint in this case, all entities will
# be allowed access. This data resource serves to make this explicit and enable easy customization if needed.
data "aws_iam_policy_document" "s3_gateway_endpoint" {
  source_policy_documents = [jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : "*",
        "Resource" : "*"
      }
    ]
  })]
}

#endregion


#region AWS myApplication

resource "aws_servicecatalogappregistry_application" "new_creation" {
  count = (var.aws_my_application_app_name != null && var.use_existing_aws_my_application_app_id == null) ? 1 : 0

  provider = aws.provider_for_aws_my_application_setup

  name        = var.aws_my_application_app_name
  description = "Includes the resources of the Kubernetes cluster environment deployment."
}

#endregion


#region VPC and Gateways

resource "aws_vpc" "new_creation" {
  count = (var.vpc_cidr_block != null && var.use_existing_vpc_id == null) ? 1 : 0

  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "kubernetes-cluster-environment"
  }
}

resource "aws_internet_gateway" "new_creation" {
  count = var.use_existing_internet_gateway_id == null ? 1 : 0

  vpc_id = data.aws_vpc.this.id

  tags = {
    Name = "internet-gateway"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.deploy_nat_gateway ? 1 : 0

  subnet_id     = aws_subnet.public_a.id
  allocation_id = aws_eip.nat[0].id

  tags = {
    Name = "nat-gateway"
  }

  depends_on = [data.aws_internet_gateway.this]
}

resource "aws_eip" "nat" {
  count = var.deploy_nat_gateway ? 1 : 0

  domain = "vpc"

  depends_on = [data.aws_internet_gateway.this]
}

resource "aws_vpc_endpoint" "s3_gateway_endpoint" {
  vpc_endpoint_type = "Gateway"
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids   = [aws_route_table.private.id, aws_route_table.public.id]
  policy            = data.aws_iam_policy_document.s3_gateway_endpoint.json

  tags = {
    Name = "s3-gateway-endpoint"
  }
}

#endregion


#region Subnets and Route Tables

resource "aws_subnet" "public_a" {
  vpc_id                  = data.aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr_block
  availability_zone       = "${data.aws_region.current.name}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-a"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = data.aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr_block
  availability_zone = "${data.aws_region.current.name}a"

  tags = {
    Name = "private-a"
  }
}

resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.this.id

  tags = {
    Name = "public-with-s3-gateway-endpoint-ips"
  }
}

resource "aws_route" "internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_a.id
}

resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.this.id

  tags = {
    Name = "private-with-nat-gateway-and-s3-gateway-endpoint-ips"
  }
}

resource "aws_route" "nat_gateway" {
  count = var.deploy_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private_a.id
}

#endregion


#region EC2 Instance Connect

resource "aws_ec2_instance_connect_endpoint" "this" {
  subnet_id          = aws_subnet.private_a.id
  security_group_ids = [aws_security_group.ssh_private_egress.id]
  preserve_client_ip = false

  tags = {
    Name = "ec2-instance-connect-az-a"
  }
}

resource "aws_security_group" "ssh_private_egress" {
  name_prefix = "ssh-private-egress"
  vpc_id      = data.aws_vpc.this.id

  tags = {
    Name = "ssh-private-egress"
  }
}

resource "aws_vpc_security_group_egress_rule" "ssh_private" {
  security_group_id = aws_security_group.ssh_private_egress.id

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_ipv4   = data.aws_vpc.this.cidr_block
}

#endregion


#region S3 Bucket

resource "aws_s3_bucket" "this" {
  count = var.s3_bucket.deploy ? 1 : 0

  bucket_prefix = var.s3_bucket.name_prefix

  tags = {
    Name = var.s3_bucket.name_prefix
  }
}

#endregion