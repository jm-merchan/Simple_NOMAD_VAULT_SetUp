# Auditor Policy for Auth0
resource "vault_policy" "audit" {
  name   = "audit"
  policy = file("policy/auditor-policy.hcl")
}

# Admin Policy for Auth0
resource "vault_policy" "super-root" {
  name   = "admin"
  policy = file("policy/super-root.hcl")
}


# Create Auth method
resource "vault_jwt_auth_backend" "oidc" {
  description        = "Integration with Auth0"
  path               = "oidc"
  type               = "oidc"
  oidc_discovery_url = "https://${data.auth0_tenant.tenant.domain}/"
  oidc_client_id     = data.auth0_client.vault.id
  oidc_client_secret = data.auth0_client.vault.client_secret
  bound_issuer       = "https://${data.auth0_tenant.tenant.domain}/"
  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "12h"
    max_lease_ttl      = "24h"
  }
  default_role = "default"
}

################Audit######################
# Create Role for audit role in Auth0
resource "vault_jwt_auth_backend_role" "audit" {
  backend        = vault_jwt_auth_backend.oidc.path
  role_name      = "audit"
  token_policies = ["default"]

  user_claim   = "https://example.com/email"
  groups_claim = "https://example.com/roles"
  role_type    = "oidc"
  allowed_redirect_uris = [
    "${data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

# Create an Identity Group in Vault and map policy to audit group
resource "vault_identity_group" "audit" {
  name = "audit"
  type = "external"
  # external_policies = true
  metadata = {
    responsability = "audit"
  }
}

resource "vault_identity_group_policies" "audit" {
  policies = [
    "default",
    "audit",
  ]
  # exclusive = true
  group_id = vault_identity_group.audit.id
}

resource "vault_identity_group_alias" "group-alias-audit" {
  name           = "audit"
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.audit.id
}

################Security######################
# Create Role for audit role in Auth0
resource "vault_jwt_auth_backend_role" "security" {
  backend        = vault_jwt_auth_backend.oidc.path
  role_name      = "security"
  token_policies = ["default"]

  user_claim   = "https://example.com/email"
  groups_claim = "https://example.com/roles"
  role_type    = "oidc"
  allowed_redirect_uris = [
    "${data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

# Create an Identity Group in Vault and map policy to security group
resource "vault_identity_group" "security" {
  name              = "security"
  type              = "external"
  external_policies = true
  metadata = {
    responsability = "security"
  }
}

resource "vault_identity_group_policies" "security" {
  policies = [
    "default",
    "security",
  ]
  exclusive = false
  group_id  = vault_identity_group.security.id
}

resource "vault_identity_group_alias" "group-alias-security" {
  name           = "security"
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.security.id
}

################Admin######################
# Create Role for audit role in Auth0
resource "vault_jwt_auth_backend_role" "admin" {
  backend        = vault_jwt_auth_backend.oidc.path
  role_name      = "admin"
  token_policies = ["default"]
  user_claim     = "https://example.com/email"
  groups_claim   = "https://example.com/roles"
  role_type      = "oidc"
  allowed_redirect_uris = [
    "${data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

# Create an Identity Group in Vault and map policy to admin group
resource "vault_identity_group" "admin" {
  name              = "admin"
  type              = "external"
  external_policies = true
  metadata = {
    responsability = "admin"
  }
}

resource "vault_identity_group_policies" "admin" {
  policies = [
    "admin"
  ]
  exclusive = true
  group_id  = vault_identity_group.admin.id
}

resource "vault_identity_group_alias" "group-alias-admin" {
  name           = "admin"
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.admin.id
}