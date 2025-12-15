output "egress_worker_token" {
  description = "Vault token for the egress worker (sensitive)"
  value       = vault_token.boundary_egress_worker.client_token
  sensitive   = true
}

output "nomad_variable_path" {
  description = "Path to the Nomad variable containing worker configuration"
  value       = nomad_variable.boundary_egress_worker.path
}

output "nomad_job_id" {
  description = "ID of the deployed Nomad job"
  value       = nomad_job.boundary_egress_worker.id
}
