aws_region = "<REGION>"                                                   # Example: eu-central-1
# use_existing_aws_my_application_app_id = "<AWS_MY_APPLICATION_APP_ID>"

use_existing_vpc_id       = "<VPC_ID>"                                    # Or use vpc_cidr_block to create a new VPC
# vpc_cidr_block          = "<VPC_CIDR_BLOCK>"                            # Example: "10.0.0.0/16"
private_subnet_cidr_block = "<PRIVATE_SUBNET_CIDR>"                       # Example: "10.0.0.0/24"
public_subnet_cidr_block  = "<PUBLIC_SUBNET_CIDR>"                        # Example: "10.0.1.0/24"

# use_existing_internet_gateway_id = "<INTERNET_GATEWAY_ID>"              # If unset, a new internet gateway is created
deploy_nat_gateway = true

s3_bucket = {
  deploy      = true
  name_prefix = "<BUCKET_NAME_PREFIX>"                                    # Example: "k8s-cluster-bucket-"
}
