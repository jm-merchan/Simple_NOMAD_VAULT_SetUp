
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

resource "auth0_user" "users" {
  for_each = var.auth0_users

  connection_name = "Username-Password-Authentication"
  name            = each.value.name
  email           = each.value.email
  email_verified  = true
  password        = var.auth0_password
  app_metadata    = jsonencode({ roles = { group1 = each.value.role } })
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