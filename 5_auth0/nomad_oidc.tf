resource "nomad_acl_auth_method" "oidc" {
  name           = "Auth0"
  type           = "OIDC"
  token_locality = "global"
  max_token_ttl  = "1h"

  config {
    oidc_discovery_url = "https://${data.auth0_tenant.tenant.domain}/"
    oidc_client_id     = data.auth0_client.nomad.id
    oidc_client_secret = data.auth0_client.nomad.client_secret
    bound_audiences    = [data.auth0_client.nomad.id]
    allowed_redirect_uris = [
      "${data.terraform_remote_state.clusters.outputs.service_urls.nomad_server.fqdn_url}/ui/settings/tokens",
      "http://localhost:4649/oidc/callback"
    ]
    list_claim_mappings = {
      "https://example.com/roles" = "roles"
    }
  }
}

resource "nomad_acl_binding_rule" "admin" {
  auth_method = nomad_acl_auth_method.oidc.name
  description = "Admin role from Auth0"
  selector    = "\"admin\" in list.roles"
  bind_type   = "management"
}

resource "nomad_acl_binding_rule" "readonly" {
  auth_method = nomad_acl_auth_method.oidc.name
  description = "Readonly role from Auth0"
  selector    = "\"audit\" in list.roles"
  bind_type   = "policy"
  bind_name   = "readonly"
}

resource "nomad_acl_policy" "readonly" {
  name        = "readonly"
  description = "Read only policy"
  rules_hcl   = <<EOT
namespace "*" {
  policy = "read"
}
node {
  policy = "read"
}
agent {
  policy = "read"
}
operator {
  policy = "read"
}
quota {
  policy = "read"
}
host_volume "*" {
  policy = "read"
}
EOT
}

resource "nomad_acl_policy" "operator" {
  name        = "operator"
  description = "Operator policy"
  rules_hcl   = <<EOT
namespace "*" {
  policy = "write"
}
node {
  policy = "read"
}
agent {
  policy = "read"
}
operator {
  policy = "read"
}
quota {
  policy = "read"
}
EOT
}

resource "nomad_acl_binding_rule" "operator" {
  auth_method = nomad_acl_auth_method.oidc.name
  description = "Operator role from Auth0"
  selector    = "\"security\" in list.roles"
  bind_type   = "policy"
  bind_name   = nomad_acl_policy.operator.name
}
