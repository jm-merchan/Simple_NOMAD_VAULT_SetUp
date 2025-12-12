output "worker_instance_id" {
  description = "ID of the Boundary worker instance"
  value       = aws_instance.boundary_worker.id
}

output "worker_private_ip" {
  description = "Private IP of the Boundary worker"
  value       = aws_instance.boundary_worker.private_ip
}

output "worker_public_ip" {
  description = "Public IP of the Boundary worker"
  value       = aws_instance.boundary_worker.public_ip
}

output "worker_security_group_id" {
  description = "Security group ID for the Boundary worker"
  value       = aws_security_group.boundary_worker.id
}
