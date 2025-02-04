terraform {
  required_version = "~> 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.0"
    }
  }
}

data "aws_subnet" "this" {
  id = var.subnet_id
}

data "aws_vpc" "this" {
  id = data.aws_subnet.this.vpc_id
}

data "local_file" "pre-baked-ami-setup-script" {
  filename = "${path.module}/scripts/pre-baked-ami-setup-script.sh"
}

resource "aws_instance" "this" {
  subnet_id              = var.subnet_id
  ami                    = var.ami_id
  instance_type          = var.ec2_instance_type
  vpc_security_group_ids = [aws_security_group.ssh_ingress_all_egress.id]
  user_data              = data.local_file.pre-baked-ami-setup-script.content_base64

  tags = {
    Name = "ec2-instance-for-creating-pre-baked-ami"
  }
}

resource "aws_security_group" "ssh_ingress_all_egress" {
  name_prefix = "ssh-ingress-all-egress"
  vpc_id      = data.aws_vpc.this.id

  tags = {
    Name = "ssh-ingress-all-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ssh_ingress_all_egress.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = data.aws_vpc.this.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ssh_ingress_all_egress.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
