terraform {
  required_version = ">= 1.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
    }
  }
}

provider "vault" {
  # Uses VAULT_ADDR and VAULT_TOKEN environment variables
}

provider "nomad" {
  # Uses NOMAD_ADDR and NOMAD_TOKEN environment variables
}

# Get boundary deployment outputs
data "terraform_remote_state" "boundary" {
  backend = "local"

  config = {
    path = "${path.module}/../3_boundary_deploy_aws/terraform.tfstate"
  }
}

# Get existing Vault Transit mount
data "vault_mount" "transit" {
  path = var.transit_mount_path
}

# Get existing worker-auth key
data "vault_transit_secret_backend_key" "boundary_worker_auth" {
  backend = data.vault_mount.transit.path
  name    = var.kms_key_worker
}

# Create a static token for Boundary Egress Worker
resource "vault_token" "boundary_egress_worker" {
  policies = ["boundary-worker-transit-policy"]

  no_parent        = true
  renewable        = false
  ttl              = "0"    # No expiration
  explicit_max_ttl = "0"    # No maximum TTL

  metadata = {
    purpose = "boundary-egress-worker-kms"
  }
}

# Store the token in Nomad Variables
resource "nomad_variable" "boundary_egress_worker" {
  path      = "nomad/jobs/boundary-egress-worker"
  namespace = "default"

  items = {
    vault_token        = vault_token.boundary_egress_worker.client_token
    transit_mount_path = var.transit_mount_path
    kms_key_worker     = var.kms_key_worker
  }
}

# Deploy the Nomad job
resource "nomad_job" "boundary_egress_worker" {
  jobspec = templatefile("${path.module}/ubuntu_remote/11_boundary_worker_config.hcl", {
    boundary_version    = var.boundary_version
    ingress_worker_addr = data.terraform_remote_state.boundary.outputs.ingress_worker_address
  })

  # Ensure the variable is created first
  depends_on = [nomad_variable.boundary_egress_worker]
}
