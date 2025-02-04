output "vpc_id" {
  value = data.aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public_a.id
}

output "private_subnet_id" {
  value = aws_subnet.private_a.id
}

output "ec2_instance_connect_endpoint_id" {
  value = aws_ec2_instance_connect_endpoint.this.id
}

output "s3_bucket_id" {
  value = try(aws_s3_bucket.this[0].id, null)
}

output "s3_bucket_uri" {
  value = try("s3://${aws_s3_bucket.this[0].id}", null)
}

output "s3_gateway_endpoint_id" {
  value = aws_vpc_endpoint.s3_gateway_endpoint.id
}

output "internet_gateway_id" {
  value = data.aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  value = try(aws_nat_gateway.this[0].id, null)
}

output "aws_my_application_id" {
  value = (
    var.use_existing_aws_my_application_app_id != null
    ? data.aws_servicecatalogappregistry_application.use_existing[0].id
    : (var.aws_my_application_app_name != null ? aws_servicecatalogappregistry_application.new_creation[0].id : null)
  )
}

output "aws_my_application_name" {
  value = (
    var.use_existing_aws_my_application_app_id != null
    ? data.aws_servicecatalogappregistry_application.use_existing[0].name
    : (var.aws_my_application_app_name != null ? aws_servicecatalogappregistry_application.new_creation[0].name : null)
  )
}
