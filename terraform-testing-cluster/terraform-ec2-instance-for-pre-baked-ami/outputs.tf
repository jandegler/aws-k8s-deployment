output "region" {
  value = var.aws_region
}

output "ec2_instance_id" {
  value = aws_instance.this.id
}
