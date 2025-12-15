output "egress_worker_token" {
  description = "Vault token for the egress worker (sensitive)"
  value       = vault_token.boundary_egress_worker.client_token
  sensitive   = true
}

output "nomad_variable_paths" {
  description = "Paths to the Nomad variables containing worker configuration"
  value = {
    ubuntu = nomad_variable.boundary_egress_worker_ubuntu.path
    ec2    = nomad_variable.boundary_egress_worker_ec2.path
  }
}

output "nomad_job_id" {
  description = "ID of the deployed Nomad job"
  value       = nomad_job.boundary_egress_worker.id
}

output "boundary_authenticate_command" {
  description = "Command to authenticate with Boundary using password auth"
  value       = "boundary authenticate password -auth-method-id=${local.boundary_password_auth_method_id} -login-name=${var.boundary_user} -password=${var.boundary_password}"
  sensitive   = true
}

output "connect_ubuntu_command" {
  description = "Boundary connect command to reach the Ubuntu host via SSH"
  value       = "boundary connect ssh -target-id ${boundary_target.ubuntu_ssh.id}"
}

output "connect_ec2_command" {
  description = "Boundary connect command to reach the EC2 host via SSH"
  value       = "boundary connect ssh -target-id ${boundary_target.ec2_ssh.id}"
}

output "boundary_targets" {
  description = "Boundary target IDs for SSH access"
  value = {
    ubuntu_ssh = boundary_target.ubuntu_ssh.id
    ec2_ssh    = boundary_target.ec2_ssh.id
  }
}