provider "aws" {
  alias = "provider_for_aws_my_application_setup"

  region = var.aws_region
}

provider "aws" {
  region = var.aws_region

  # This following conditional logic is not a good practice. It was left in for convenience, because it enables the
  # packaging of all resources into an AWS myApplication app that can itself be created as part of the configuration.
  # For any deployment beyond personal testing purposes the "new_creation" trinary operator section should be deleted
  # and the AWS myApplication app resource creation be placed in a separate Terraform configuration. Right now, this
  # conditional logic causes the provider to have a dependency on a resource that this configuration may itself create.
  # This will sometimes result in dynamic provider changes during deployments that lead to errors as they are neither
  # intended nor supported by Terraform.
  default_tags {
    tags = (
      var.use_existing_aws_my_application_app_id != null
      ? data.aws_servicecatalogappregistry_application.use_existing[0].application_tag
      : (var.aws_my_application_app_name != null ? try(aws_servicecatalogappregistry_application.new_creation[0].application_tag, null) : null)
    )
  }
}
