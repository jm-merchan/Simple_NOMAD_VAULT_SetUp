output "org_scope_id" {
  description = "ID of the org scope created by init_boundary"
  value       = boundary_scope.org.id
}

output "project_scope_id" {
  description = "ID of the project scope created by init_boundary"
  value       = boundary_scope.project.id
}

output "password_auth_method_id" {
  description = "ID of the password auth method created in the org scope"
  value       = boundary_auth_method.password.id
}

output "boundary_authenticate_command" {
  description = "Command to authenticate with Boundary using password auth"
  value       = "boundary authenticate password -auth-method-id=${boundary_auth_method.password.id} -login-name=${var.boundary_user} -password=${var.boundary_password}"
  sensitive   = true
}
