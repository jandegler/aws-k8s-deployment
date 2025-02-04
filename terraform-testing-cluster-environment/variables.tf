variable "aws_region" {
  description = "Specify the region where the VPC is to be deployed."
  type        = string
  nullable    = false
}

variable "use_existing_vpc_id" {
  description = "Specify a VPC ID to deploy into the corresponding VPC."
  type        = string
  nullable    = true
  default     = null
  validation {
    condition     = (
    !(var.use_existing_vpc_id == null && var.vpc_cidr_block == null)
    || !(var.use_existing_vpc_id != null && var.vpc_cidr_block != null)
    )
    error_message = "Either the use_existing_vpc_id or vpc_cidr_block variable must be set and also not both."
  }
}

variable "vpc_cidr_block" {
  description = "If specified, a new VPC with that CIDR block will be created."
  type        = string
  nullable    = true
  default     = null
}

variable "public_subnet_cidr_block" {
  description = "Specify the CIDR block for the public subnet."
  type        = string
  nullable    = false
}

variable "private_subnet_cidr_block" {
  description = "Specify the CIDR block for the private subnet."
  type        = string
  nullable    = false
}

variable "use_existing_internet_gateway_id" {
  description = "If this variable is not set, an internet gateway will be created."
  type        = string
  nullable    = true
  default     = null
}

variable "deploy_nat_gateway" {
  description = "Choose whether the NAT gateway should be deployed or not."
  type        = bool
  default     = true
}

variable "s3_bucket" {
  description = "Choose if a default bucket should be deployed and if so, the name prefix to use for it."
  type = object({
    deploy      = bool
    name_prefix = optional(string, null)
  })
  nullable = true
  default  = null
  validation {
    condition     = !(var.s3_bucket.deploy == true && (var.s3_bucket.name_prefix == null || var.s3_bucket.name_prefix == ""))
    error_message = "When the S3 bucket is to be deployed, the name must be specified."
  }
}

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
