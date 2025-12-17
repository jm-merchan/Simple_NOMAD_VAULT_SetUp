# https://developer.hashicorp.com/boundary/docs/install-boundary/initialize#create-your-first-login-account
# Provider configuration is in terraform.tf

resource "boundary_scope" "org" {
  scope_id    = "global"
  name        = "org"
  description = "Organization scope"

  auto_create_admin_role   = false
  auto_create_default_role = false
}

resource "boundary_scope" "project" {
  name                     = "project"
  description              = "Computing at Edge Project"
  scope_id                 = boundary_scope.org.id
  auto_create_admin_role   = false
  auto_create_default_role = false
}

resource "boundary_auth_method" "password" {
  name        = "Password auth method"
  description = "Password auth method"
  type        = "password"
  scope_id    = boundary_scope.org.id
}

resource "boundary_account_password" "myuser" {
  name           = "admin"
  description    = "User account for admin"
  login_name     = var.boundary_user
  password       = var.boundary_password
  auth_method_id = boundary_auth_method.password.id
}

resource "boundary_user" "myuser" {
  name        = "admin"
  description = "Initial Admin User"
  account_ids = [boundary_account_password.myuser.id]
  scope_id    = boundary_scope.org.id
}

resource "boundary_role" "global_admin" {
  scope_id = "global"
  grant_strings = [
    "ids=*;type=*;actions=*"
  ]
  principal_ids = [boundary_user.myuser.id]
}

resource "boundary_role" "org_admin" {
  scope_id        = "global"
  grant_scope_ids = [boundary_scope.org.id]
  grant_strings = [
    "ids=*;type=*;actions=*"
  ]
  principal_ids = [boundary_user.myuser.id]
}

resource "boundary_role" "project_admin" {
  scope_id        = boundary_scope.org.id
  grant_scope_ids = [boundary_scope.project.id]
  grant_strings = [
    "ids=*;type=*;actions=*"
  ]
  principal_ids = [boundary_user.myuser.id]
}