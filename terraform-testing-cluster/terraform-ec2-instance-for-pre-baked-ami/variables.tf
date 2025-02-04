variable "aws_region" {
  description = "The region to deploy into."
  type        = string
  nullable    = false
}

variable "subnet_id" {
  description = "Specify the subnet in which to deploy the instance. Note that internet access is needed for running the script."
  type        = string
  nullable    = false
}

variable "ami_id" {
  description = "The AMI ID to use to start up the instance."
  type        = string
  nullable    = false
  # ami-07eef52105e8a2059 (Ubuntu Server 24.04 LTS) is the original AMI that was used for testing when creating the
  # pre-baked-ami-setup-script.sh script.
  default     = "ami-07eef52105e8a2059"
}

variable "ec2_instance_type" {
  description = "Specify the EC2 instance type to use. Since this configuration is only for running a script, t2.micro should suffice."
  type        = string
  nullable    = false
  default     = "t2.micro"
}
