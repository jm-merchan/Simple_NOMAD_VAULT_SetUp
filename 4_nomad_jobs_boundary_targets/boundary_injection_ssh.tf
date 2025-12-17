# Random string for unique credential store name
resource "random_string" "credential_store_suffix" {
  length  = 4
  special = false
  upper   = false
}

# Vault credential store for SSH injection (uses token with controller + ssh policies)
resource "boundary_credential_store_vault" "ssh_injection" {
  depends_on  = [nomad_job.configure_ssh_ca_ec2, nomad_job.configure_ssh_ca_ubuntu]
  name        = "vault-ssh-injection-store-${random_string.credential_store_suffix.result}"
  description = "Vault credential store for SSH certificate injection"
  scope_id    = data.boundary_scope.project.id
  address     = var.vault_addr
  token       = vault_token.boundary_token.client_token
  namespace   = ""
}

# SSH certificate library for EC2 instance
resource "boundary_credential_library_vault_ssh_certificate" "ec2_injection" {
  name                = "ec2-ssh-cert-injection"
  description         = "SSH certificate for EC2 instance via Vault"
  credential_store_id = boundary_credential_store_vault.ssh_injection.id
  path                = "${vault_mount.ssh.path}/sign/${vault_ssh_secret_backend_role.signer_ec2.name}"
  username            = var.ec2_ssh_user
  key_type            = "ecdsa"
  key_bits            = 521

  extensions = {
    permit-pty = ""
  }
}

# SSH certificate library for Ubuntu instance
resource "boundary_credential_library_vault_ssh_certificate" "ubuntu_injection" {
  name                = "ubuntu-ssh-cert-injection"
  description         = "SSH certificate for Ubuntu instance via Vault"
  credential_store_id = boundary_credential_store_vault.ssh_injection.id
  path                = "${vault_mount.ssh.path}/sign/${vault_ssh_secret_backend_role.signer_ubuntu.name}"
  username            = var.ubuntu_ssh_user
  key_type            = "ecdsa"
  key_bits            = 521

  extensions = {
    permit-pty = ""
  }
}

# EC2 SSH target with credential injection
resource "boundary_target" "ec2_ssh_injection" {
  type                     = "ssh"
  name                     = "ec2-ssh-injection"
  description              = "SSH access to EC2 with credential injection"
  scope_id                 = data.boundary_scope.project.id
  session_connection_limit = -1
  default_port             = 22
  egress_worker_filter     = "\"ec2-remote\" in \"/tags/type\""

  host_source_ids = [
    boundary_host_set_static.ec2.id
  ]

  injected_application_credential_source_ids = [
    boundary_credential_library_vault_ssh_certificate.ec2_injection.id
  ]
}

# Ubuntu SSH target with credential injection
resource "boundary_target" "ubuntu_ssh_injection" {
  type                     = "ssh"
  name                     = "ubuntu-ssh-injection"
  description              = "SSH access to Ubuntu with SSH certificate injection"
  scope_id                 = data.boundary_scope.project.id
  session_connection_limit = -1
  default_port             = 22
  egress_worker_filter     = "\"ubuntu-remote\" in \"/tags/type\""

  host_source_ids = [
    boundary_host_set_static.ubuntu.id
  ]

  injected_application_credential_source_ids = [
    boundary_credential_library_vault_ssh_certificate.ubuntu_injection.id
  ]
}

# Alias for EC2 SSH injection target
resource "boundary_alias_target" "ec2_ssh_injection_alias" {
  name           = "ec2-ssh-injection-alias"
  description    = "Alias for EC2 SSH injection target"
  scope_id       = "global"
  value          = "ec2.ssh.inject"
  destination_id = boundary_target.ec2_ssh_injection.id
}

# Alias for Ubuntu SSH injection target
resource "boundary_alias_target" "ubuntu_ssh_injection_alias" {
  name           = "ubuntu-ssh-injection-alias"
  description    = "Alias for Ubuntu SSH injection target"
  scope_id       = "global"
  value          = "ubuntu.ssh.inject"
  destination_id = boundary_target.ubuntu_ssh_injection.id
}