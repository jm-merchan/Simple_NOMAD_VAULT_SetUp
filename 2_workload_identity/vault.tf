
resource "vault_jwt_auth_backend" "jwt-nomad" {
  path               = "jwt-nomad"
  jwks_url           = "${var.nomad_server_address}/.well-known/jwks.json"
  jwt_supported_algs = ["RS256", "EdDSA"]
  default_role       = "nomad-workloads"
}

resource "vault_jwt_auth_backend_role" "jwt-nomad-role" {
  backend        = vault_jwt_auth_backend.jwt-nomad.path
  role_name      = "nomad-workloads"
  token_policies = ["nomad-workloads"]

  bound_audiences = ["vault.io"]

  user_claim              = "/nomad_job_id"
  user_claim_json_pointer = true
  claim_mappings = {
    "nomad_namespace" = "nomad_namespace"
    "nomad_job_id"    = "nomad_job_id"
    "nomad_task"      = "nomad_task"
  }
  role_type              = "jwt"
  token_type             = "service"
  token_period           = "300"
  token_explicit_max_ttl = 0

  depends_on = [vault_jwt_auth_backend.jwt-nomad]
}
resource "vault_policy" "nomad-workloads" {
  name = "nomad-workloads"

  policy = <<EOT
# Allow reading all secrets under kv (for testing - tighten this in production)
path "kv/data/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}

# Templated policy for job-specific access
# Replace AUTH_METHOD_ACCESSOR with the actual accessor after creating the auth method
# path "kv/data/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}/*" {
#   capabilities = ["read"]
# }
EOT
  
  depends_on = [vault_jwt_auth_backend.jwt-nomad]
}


resource "vault_mount" "kv" {
  path    = "kv"
  type    = "kv"
  options = { version = "2" }
}

resource "vault_kv_secret_v2" "secret_example" {
  mount = vault_mount.kv.path
  name  = "default/mongo/config"
  data_json_wo = jsonencode(
    {
      root_password = "secret-password"
    }
  )
  data_json_wo_version = 1
}

ephemeral "vault_kv_secret_v2" "db_secret" {
  mount    = vault_mount.kv.path
  mount_id = vault_mount.kv.id
  name     = vault_kv_secret_v2.secret_example.name
}