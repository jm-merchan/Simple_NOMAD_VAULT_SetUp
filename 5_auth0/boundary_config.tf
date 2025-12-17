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

# Configs for All Users (excluding admin)
# ---------------------------
resource "boundary_account_oidc" "users" {
  for_each = { for k, v in var.auth0_users : k => v if k != "admin" }

  name           = each.value.name
  description    = "${each.value.name} from Auth0"
  auth_method_id = boundary_auth_method_oidc.provider.id
  issuer         = "https://${data.auth0_tenant.tenant.domain}/"
  subject        = auth0_user.users[each.key].user_id
}

resource "boundary_user" "users" {
  for_each = { for k, v in var.auth0_users : k => v if k != "admin" }

  name        = each.value.name
  description = "${each.value.name} from Auth0"
  account_ids = [boundary_account_oidc.users[each.key].id]
  scope_id    = "global"
}

# Role assignments based on user role
resource "boundary_role" "admin_users_project" {
  for_each = { for k, v in var.auth0_users : k => v if v.role == "admin" && k != "admin" }

  name          = "${each.key}-project"
  description   = "Full Admin Permissions at Project level for ${each.value.name}"
  principal_ids = [boundary_user.users[each.key].id]
  grant_strings = ["ids=*;type=*;actions=*"]
  scope_id      = data.boundary_scope.project.id
}

resource "boundary_role" "admin_users_org" {
  for_each = { for k, v in var.auth0_users : k => v if v.role == "admin" && k != "admin" }

  name          = "${each.key}-org"
  description   = "Full Admin Permissions at Org level for ${each.value.name}"
  principal_ids = [boundary_user.users[each.key].id]
  grant_strings = ["ids=*;type=*;actions=*"]
  scope_id      = data.boundary_scope.org.id
}

resource "boundary_role" "admin_users_global" {
  for_each = { for k, v in var.auth0_users : k => v if v.role == "admin" && k != "admin" }

  name          = "${each.key}-global"
  description   = "Full Admin Permissions at Global level for ${each.value.name}"
  principal_ids = [boundary_user.users[each.key].id]
  grant_strings = ["ids=*;type=*;actions=*"]
  scope_id      = "global"
}

# Security role - read-only access
resource "boundary_role" "security_users_project" {
  for_each = { for k, v in var.auth0_users : k => v if v.role == "security" }

  name          = "${each.key}-project-readonly"
  description   = "Read-only access at Project level for ${each.value.name}"
  principal_ids = [boundary_user.users[each.key].id]
  grant_strings = ["ids=*;type=*;actions=read,list"]
  scope_id      = data.boundary_scope.project.id
}

resource "boundary_role" "security_users_org" {
  for_each = { for k, v in var.auth0_users : k => v if v.role == "security" }

  name          = "${each.key}-org-readonly"
  description   = "Read-only access at Org level for ${each.value.name}"
  principal_ids = [boundary_user.users[each.key].id]
  grant_strings = ["ids=*;type=*;actions=read,list"]
  scope_id      = data.boundary_scope.org.id
}
