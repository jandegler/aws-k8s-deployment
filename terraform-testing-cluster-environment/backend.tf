# terraform {
#   # For a simple personal backend, an S3 bucket can be used. Furthermore, a DynamoDB database can be set up and used
#   # for a locking mechanism to enable collaboration on the infrastructure. See the Terraform documentation for more
#   # information.
#   backend "s3" {
#     region  = "<REGION>"
#     bucket  = "<BUCKET_NAME>"
#     key     = "<KEY>"
#     encrypt = true
#     # enable_versioning = true
#   }
# }
