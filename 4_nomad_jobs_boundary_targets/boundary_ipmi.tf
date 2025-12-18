# IPMI Server Access via Boundary with Vault-backed credentials

# Store IPMI credentials in Vault
resource "vault_kv_secret_v2" "ipmi_credentials" {
  mount = "secret"
  name  = "ipmi/server1"
  data_json = jsonencode({
    username = var.ipmi_username
    password = var.ipmi_password
  })
}

# Vault credential library for IPMI access (reuses existing credential store)
resource "boundary_credential_library_vault" "ipmi" {
  name                = "ipmi-credentials"
  description         = "IPMI credentials from Vault"
  credential_store_id = boundary_credential_store_vault.ssh_injection.id
  path                = "secret/data/ipmi/server1"
  http_method         = "GET"
  credential_type     = "username_password"
}

# Static host catalog for IPMI server
resource "boundary_host_catalog_static" "ipmi" {
  depends_on  = [nomad_job.boundary_egress_worker]
  name        = "ipmi-static-catalog"
  description = "Static host catalog for IPMI server"
  scope_id    = data.boundary_scope.project.id
}

resource "boundary_host_static" "ipmi_server" {
  name            = "ipmi-server1"
  description     = "IPMI interface for server"
  address         = "192.168.1.36"
  host_catalog_id = boundary_host_catalog_static.ipmi.id
}

resource "boundary_host_set_static" "ipmi" {
  name            = "ipmi-host-set"
  description     = "Host set containing IPMI server"
  host_catalog_id = boundary_host_catalog_static.ipmi.id
  host_ids        = [boundary_host_static.ipmi_server.id]
}

# IPMI access target (typically HTTPS/443 or HTTP/80 or SSH/22 depending on IPMI interface)
resource "boundary_target" "ipmi_web" {
  name                 = "ipmi-server1-web"
  description          = "Web access to IPMI interface"
  type                 = "tcp"
  scope_id             = data.boundary_scope.project.id
  egress_worker_filter = "\"ubuntu-remote\" in \"/tags/type\""

  default_port = 443  # IPMI web interface typically uses HTTPS
  host_source_ids = [
    boundary_host_set_static.ipmi.id,
  ]

  # Inject IPMI credentials from Vault
  brokered_credential_source_ids = [
    boundary_credential_library_vault.ipmi.id,
  ]
}

# Alias for IPMI web target
resource "boundary_alias_target" "ipmi_alias" {
  name                      = "ipmi.nomad.example"
  description               = "Alias for IPMI web interface"
  scope_id                  = "global"
  value                     = "ipmi.nomad.example"
  destination_id            = boundary_target.ipmi_web.id
  authorize_session_host_id = boundary_host_static.ipmi_server.id
}

# Optional: SSH access to IPMI if it supports SSH
resource "boundary_target" "ipmi_ssh" {
  name                 = "ipmi-server1-ssh"
  description          = "SSH access to IPMI interface"
  type                 = "tcp"
  scope_id             = data.boundary_scope.project.id
  egress_worker_filter = "\"ubuntu-remote\" in \"/tags/type\""

  default_port = 22
  host_source_ids = [
    boundary_host_set_static.ipmi.id,
  ]

  # Inject IPMI credentials from Vault
  brokered_credential_source_ids = [
    boundary_credential_library_vault.ipmi.id,
  ]
}
