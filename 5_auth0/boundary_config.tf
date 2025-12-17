data "boundary_scope" "org" {
  name     = "org"
  scope_id = "global"
}

data "boundary_scope" "project" {
  name     = "project"
  scope_id = data.boundary_scope.org.id
}

resource "boundary_auth_method_oidc" "provider" {
  name                 = "Auth0"
  description          = "OIDC auth method for Auth0"
  scope_id             = "global" #data.boundary_scope.org.id
  issuer               = "https://${data.auth0_tenant.tenant.domain}/"
  client_id            = data.auth0_client.boundary.id
  client_secret        = data.auth0_client.boundary.client_secret
  signing_algorithms   = ["RS256"]
  api_url_prefix       = data.terraform_remote_state.boundary.outputs.boundary_url
  is_primary_for_scope = true
  state                = "active-public"
  max_age              = 0
}

# Configs for Admin User
# ---------------------------
# ---------------------------
resource "boundary_account_oidc" "admin" {
  name           = auth0_user.users["admin"].name
  description    = "Admin user from Auth0"
  auth_method_id = boundary_auth_method_oidc.provider.id
  issuer         = "https://${data.auth0_tenant.tenant.domain}/"
  subject        = auth0_user.users["admin"].user_id
}

resource "boundary_user" "admin" {
  name        = boundary_account_oidc.admin.name
  description = "Admin user from Auth0"
  account_ids = [boundary_account_oidc.admin.id]
  scope_id    = "global" #data.boundary_scope.org.id
}

resource "boundary_role" "admin_project" {
  # All Permissions for Admin at Project Scope
  name          = "admin-project"
  description   = "Full Admin Permisions at Project level"
  principal_ids = [boundary_user.admin.id]
  grant_strings = ["ids=*;type=*;actions=*"]
  scope_id      = data.boundary_scope.project.id
}

resource "boundary_role" "admin_org" {
  name          = "admin-org"
  description   = "Full Admin Permissions at Org level"
  principal_ids = [boundary_user.admin.id]
  grant_strings = ["ids=*;type=*;actions=*"]
  scope_id      = data.boundary_scope.org.id
}

resource "boundary_role" "admin_global" {
  name          = "admin-global"
  description   = "Full Admin Permissions at Global level"
  principal_ids = [boundary_user.admin.id]
  grant_strings = ["ids=*;type=*;actions=*"]
  scope_id      = "global"
}
