output "jwt_auth_accessor" {
  description = "JWT auth method accessor for use in templated policies"
  value       = vault_jwt_auth_backend.jwt-nomad.accessor
}

output "jwt_auth_path" {
  description = "JWT auth method path"
  value       = vault_jwt_auth_backend.jwt-nomad.path
}

output "vault_policy_update_command" {
  description = "Command to update the Vault policy with the correct accessor"
  value       = "Replace AUTH_METHOD_ACCESSOR in the policy with: ${vault_jwt_auth_backend.jwt-nomad.accessor}"
}
