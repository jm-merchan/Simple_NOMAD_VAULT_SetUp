
resource "auth0_client" "vault" {
  name        = "vault"
  description = "Vault Authentication"
  app_type    = "regular_web"
  callbacks = [
    "${data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]

  oidc_conformant = true

  jwt_configuration {
    alg = "RS256"
  }
}

resource "auth0_client" "nomad" {
  name        = "nomad"
  description = "Nomad Authentication"
  app_type    = "regular_web"
  callbacks = [
    "${data.terraform_remote_state.clusters.outputs.service_urls.nomad_server.fqdn_url}/ui/settings/tokens",
    "http://localhost:4649/oidc/callback"
  ]
  allowed_origins = [
    "${data.terraform_remote_state.clusters.outputs.service_urls.nomad_server.fqdn_url}"
  ]

  oidc_conformant = true

  jwt_configuration {
    alg = "RS256"
  }
}

resource "auth0_client" "boundary" {
  name        = "boundary"
  description = "Boundary Authentication"
  app_type    = "regular_web"
  callbacks = [
    "${data.terraform_remote_state.boundary.outputs.boundary_url}/v1/auth-methods/oidc:authenticate:callback",
    "http://localhost:9200/v1/auth-methods/oidc:authenticate:callback"
  ]

  oidc_conformant = true

  jwt_configuration {
    alg = "RS256"
  }
}

resource "auth0_user" "admin" {
  connection_name = "Username-Password-Authentication"
  name            = "Vault Admin"
  email           = "peter@vaultproject.io"
  email_verified  = true
  password        = var.auth0_password
  app_metadata    = "{\"roles\": {\"group1\":\"admin\"}}"
}

resource "auth0_user" "chechu" {
  connection_name = "Username-Password-Authentication"
  name            = "Chechu"
  email           = "chechu@nomad-test.io"
  email_verified  = true
  password        = var.auth0_password
  app_metadata    = "{\"roles\": {\"group1\":\"admin\"}}"
}

resource "auth0_user" "david" {
  connection_name = "Username-Password-Authentication"
  name            = "David"
  email           = "david@nomad-test.io"
  email_verified  = true
  password        = var.auth0_password
  app_metadata    = "{\"roles\": {\"group1\":\"admin\"}}"
}

resource "auth0_user" "nibrass" {
  connection_name = "Username-Password-Authentication"
  name            = "Nibrass"
  email           = "nibrass@nomad-test.io"
  email_verified  = true
  password        = var.auth0_password
  app_metadata    = "{\"roles\": {\"group1\":\"admin\"}}"
}

resource "auth0_user" "jose" {
  connection_name = "Username-Password-Authentication"
  name            = "Jose"
  email           = "jose@nomad-test.io"
  email_verified  = true
  password        = var.auth0_password
  app_metadata    = "{\"roles\": {\"group1\":\"admin\"}}"
}

resource "auth0_user" "security" {
  connection_name = "Username-Password-Authentication"
  name            = "Security User"
  email           = "test.security@vaultproject.io"
  email_verified  = true
  password        = var.auth0_password
  app_metadata    = "{\"roles\": {\"group1\":\"security\"}}"
}

# An Auth0 Client loaded using its ID.
data "auth0_client" "vault" {
  client_id = auth0_client.vault.client_id
}

data "auth0_client" "nomad" {
  client_id = auth0_client.nomad.client_id
}

data "auth0_client" "boundary" {
  client_id = auth0_client.boundary.client_id
}

data "auth0_tenant" "tenant" {}


resource "auth0_action" "user_role" {
  name   = "Set user role"
  code   = <<-EOT
          exports.onExecutePostLogin = async (event, api) => {
          if (event.authorization) {
            event.user.app_metadata = event.user.app_metadata || {};
            api.idToken.setCustomClaim("https://example.com/roles",event.user.app_metadata.roles.group1);
            api.idToken.setCustomClaim("https://example.com/email",event.user.email);
            }
          };
    EOT
  deploy = true

  supported_triggers {
    id      = "post-login"
    version = "v3"
  }
}

resource "auth0_trigger_action" "post_login_alert_action" {
  trigger   = "post-login"
  action_id = auth0_action.user_role.id
}