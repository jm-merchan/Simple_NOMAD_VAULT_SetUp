
provider "boundary" {
  # If not set, these are read from env vars (BOUNDARY_ADDR / BOUNDARY_TOKEN).
  addr = var.boundary_addr != "" ? var.boundary_addr : null

  # Preferred: authenticate via env var BOUNDARY_TOKEN.
  # Fallback: authenticate via password auth (created in init_boundary).
  auth_method_id         = local.boundary_password_auth_method_id != "" ? local.boundary_password_auth_method_id : null
  auth_method_login_name = var.boundary_user != "" ? var.boundary_user : null
  auth_method_password   = var.boundary_password != "" ? var.boundary_password : null
}

data "terraform_remote_state" "init_boundary" {
  backend = "local"

  config = {
    path = "${path.module}/../3_boundary_deploy_aws/init_boundary/terraform.tfstate"
  }
}

locals {
  boundary_password_auth_method_id = var.boundary_auth_method_id != "" ? var.boundary_auth_method_id : try(data.terraform_remote_state.init_boundary.outputs.password_auth_method_id, "")
}

# Lookup scopes by name
data "boundary_scope" "org" {
  scope_id = "global"
  name     = "org"
}

data "boundary_scope" "project" {
  scope_id = data.boundary_scope.org.id
  name     = "project"
}

# Static host catalog for the Ubuntu host
resource "boundary_host_catalog_static" "ubuntu" {
  depends_on  = [nomad_job.boundary_egress_worker]
  name        = "ubuntu-static-catalog"
  description = "Static host catalog for ubuntu host"
  scope_id    = data.boundary_scope.project.id
}

resource "boundary_host_static" "ubuntu" {
  name            = "ubuntu"
  description     = "Ubuntu host"
  address         = var.ubuntu_host_address
  host_catalog_id = boundary_host_catalog_static.ubuntu.id
}

resource "boundary_host_set_static" "ubuntu" {
  name            = "ubuntu-host-set"
  description     = "Host set containing the ubuntu host"
  host_catalog_id = boundary_host_catalog_static.ubuntu.id
  host_ids        = [boundary_host_static.ubuntu.id]
}

# SSH access target (TCP/22) to the Ubuntu host
resource "boundary_target" "ubuntu_ssh" {
  name                 = "ubuntu-ssh"
  description          = "SSH access into the ubuntu host"
  type                 = "tcp"
  scope_id             = data.boundary_scope.project.id
  egress_worker_filter = "\"ubuntu-remote\" in \"/tags/type\""

  default_port = 22
  host_source_ids = [
    boundary_host_set_static.ubuntu.id,
  ]

  # Inject SSH credentials from static store
  brokered_credential_source_ids = [
    boundary_credential_username_password.ubuntu_ssh.id,
  ]
}

# Static host catalog for the EC2 host
resource "boundary_host_catalog_static" "ec2" {
  depends_on  = [nomad_job.boundary_egress_worker_ec2]
  name        = "ec2-static-catalog"
  description = "Static host catalog for EC2 host"
  scope_id    = data.boundary_scope.project.id
}

resource "boundary_host_static" "ec2" {
  name            = "ec2"
  description     = "EC2 host"
  address         = var.ec2_host_address
  host_catalog_id = boundary_host_catalog_static.ec2.id
}

resource "boundary_host_set_static" "ec2" {
  name            = "ec2-host-set"
  description     = "Host set containing the EC2 host"
  host_catalog_id = boundary_host_catalog_static.ec2.id
  host_ids        = [boundary_host_static.ec2.id]
}

# SSH access target (TCP/22) to the EC2 host
resource "boundary_target" "ec2_ssh" {
  name                 = "ec2-ssh"
  description          = "SSH access into the EC2 host"
  type                 = "tcp"
  scope_id             = data.boundary_scope.project.id
  egress_worker_filter = "\"ec2-remote\" in \"/tags/type\""

  default_port = 22
  host_source_ids = [
    boundary_host_set_static.ec2.id,
  ]

  # Inject SSH credentials from static store
  brokered_credential_source_ids = [
    boundary_credential_ssh_private_key.ec2_ssh.id,
  ]
}

# Static credential store for Boundary
resource "boundary_credential_store_static" "static" {
  name        = "static-credential-store"
  description = "Static credential store for SSH keys"
  scope_id    = data.boundary_scope.project.id
}

# Static SSH private key credential for EC2 instance
resource "boundary_credential_ssh_private_key" "ec2_ssh" {
  name                = "ec2-ssh-private-key"
  description         = "SSH private key for EC2 instance"
  credential_store_id = boundary_credential_store_static.static.id
  username            = var.ec2_ssh_user
  private_key         = file(var.ssh_private_key_path)
}

# Static username/password credential for Ubuntu instance
resource "boundary_credential_username_password" "ubuntu_ssh" {
  name                = "ubuntu-ssh-password"
  description         = "SSH username/password for Ubuntu instance"
  credential_store_id = boundary_credential_store_static.static.id
  username            = var.ubuntu_ssh_user
  password            = var.ubuntu_ssh_password
}
