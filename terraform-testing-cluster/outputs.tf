output "control_plane_node_id" {
  value = aws_instance.control_plane_node.id
}

output "nlb_id" {
  value = aws_lb.nlb.id
}

output "nlb_dns_name" {
  value = aws_lb.nlb.dns_name
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
