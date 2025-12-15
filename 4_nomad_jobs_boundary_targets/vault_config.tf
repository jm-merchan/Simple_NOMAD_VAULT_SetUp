
resource "vault_policy" "ssh_signer" {
  name = "ssh"

  policy = file("policy/ssh_policy.hcl")
}

resource "vault_policy" "boundary_controller" {
  name = "boundary-controller"

  policy = file("policy/boundary-controller-policy.hcl")
}

resource "vault_policy" "windows_secret_read" {
  name = "windows-secret-read"

  policy = file("policy/windows-secret-read.hcl")
}

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine"
}

resource "vault_kv_secret_v2" "windows11" {
  mount               = vault_mount.kv.path
  name                = "windows11"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      username = var.windows_user,
      password = var.windows_password
    }
  )
}

resource "vault_mount" "ssh" {
  path        = "ssh-client-signer"
  type        = "ssh"
  description = "This is an example SSH Engine"

  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
}

resource "vault_ssh_secret_backend_ca" "boundary" {
  backend              = vault_mount.ssh.path
  generate_signing_key = true
}


resource "vault_token" "boundary_token" {
  no_default_policy = true
  period            = "24h"
  policies          = ["boundary-controller", "ssh", "windows-secret-read"]
  no_parent         = true
  renewable         = true


  renew_min_lease = 43200
  renew_increment = 86400

  metadata = {
    "purpose" = "service-account-boundary"
  }
}


resource "vault_ssh_secret_backend_role" "signer_ubuntu" {
  backend                 = vault_mount.ssh.path
  name                    = "boundary-client-ubuntu"
  key_type                = "ca"
  allow_user_certificates = true
  default_user            = "ubuntu"
  default_extensions = {
    "permit-pty" : ""
  }
  allowed_users      = "*"
  allowed_extensions = "*"
}

resource "vault_ssh_secret_backend_role" "signer_ec2" {
  backend                 = vault_mount.ssh.path
  name                    = "boundary-client-ec2"
  key_type                = "ca"
  allow_user_certificates = true
  default_user            = "ec2-user"
  default_extensions = {
    "permit-pty" : ""
  }
  allowed_users      = "*"
  allowed_extensions = "*"
}
