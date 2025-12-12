output "controller_instance_id" {
  description = "ID of the Boundary controller instance"
  value       = aws_instance.boundary_controller.id
}

output "controller_private_ip" {
  description = "Private IP of the Boundary controller"
  value       = aws_instance.boundary_controller.private_ip
}

output "controller_public_ip" {
  description = "Public IP of the Boundary controller"
  value       = aws_instance.boundary_controller.public_ip
}

output "controller_security_group_id" {
  description = "Security group ID for the Boundary controller"
  value       = aws_security_group.boundary_controller.id
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.boundary.endpoint
}

output "database_address" {
  description = "RDS database address"
  value       = aws_db_instance.boundary.address
}

output "api_url" {
  description = "Boundary API URL"
  value       = "https://${aws_instance.boundary_controller.public_ip}:9200"
}

output "cluster_url" {
  description = "Boundary cluster URL for workers"
  value       = "${var.cluster_name}.${var.dns_zone_name}:9201"
}

output "fqdn_url" {
  description = "Boundary FQDN URL"
  value       = "https://${var.cluster_name}.${var.dns_zone_name}:9200"
}
