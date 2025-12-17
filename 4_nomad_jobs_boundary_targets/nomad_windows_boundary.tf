# HTTP Server Job (deployed first on Ubuntu instance)
resource "nomad_job" "http_server" {
  jobspec = file("${path.module}/ubuntu_remote/0_http_server.hcl")
}

# Windows 11 V4 Job
resource "nomad_job" "windows11_v4" {
  jobspec = file("${path.module}/ubuntu_remote/8_windows11_v4.hcl")
  
  depends_on = [nomad_job.http_server]
}

# Vault Credential Library for Windows 11
resource "boundary_credential_library_vault" "windows11" {
  name                = "windows11-credentials"
  description         = "Windows 11 Credentials from Vault KV"
  credential_store_id = boundary_credential_store_vault.ssh_injection.id
  path                = "secret/data/windows11" # KV v2 path
  http_method         = "GET"
  credential_type     = "username_password"
}

# Boundary Target for Windows 11 RDP (Port 3392)
resource "boundary_target" "windows11_rdp" {
  name         = "windows11-rdp"
  description  = "Windows 11 RDP Access"
  type         = "rdp"
  #type         = "tcp"
  default_port = 3392
  scope_id     = data.boundary_scope.project.id
  egress_worker_filter = "\"ubuntu-remote\" in \"/tags/type\""
  host_source_ids = [
    boundary_host_set_static.ubuntu.id
  ]
  injected_application_credential_source_ids = [
    boundary_credential_library_vault.windows11.id
  ]

}

# Boundary Target for Windows 11 VNC (Port 5907)
resource "boundary_target" "windows11_vnc" {
  name         = "windows11-vnc"
  description  = "Windows 11 VNC Access"
  type         = "tcp"
  default_port = 5907
  scope_id     = data.boundary_scope.project.id
  egress_worker_filter = "\"ubuntu-remote\" in \"/tags/type\""
  host_source_ids = [
    boundary_host_set_static.ubuntu.id
  ]


  brokered_credential_source_ids = [
    boundary_credential_library_vault.windows11.id
  ]

}
