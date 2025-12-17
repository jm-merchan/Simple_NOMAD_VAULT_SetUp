output "jwt_auth_accessor" {
  description = "JWT auth method accessor for use in templated policies"
  value       = vault_jwt_auth_backend.jwt-nomad.accessor
}

output "jwt_auth_path" {
  description = "JWT auth method path"
  value       = vault_jwt_auth_backend.jwt-nomad.path
}