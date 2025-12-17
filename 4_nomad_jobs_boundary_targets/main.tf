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
    boundary = {
      source  = "hashicorp/boundary"
      version = "1.4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get outputs from 1_create_clusters
data "terraform_remote_state" "clusters" {
  backend = "local"

  config = {
    path = "${path.module}/../1_create_clusters/terraform.tfstate"
  }
}

# Get Vault root token from AWS Secrets Manager
data "aws_secretsmanager_secret" "vault_root_token" {
  name = data.terraform_remote_state.clusters.outputs.vault_token_secret_name
}

data "aws_secretsmanager_secret_version" "vault_root_token" {
  secret_id = data.aws_secretsmanager_secret.vault_root_token.id
}

# Get Nomad bootstrap token from AWS Secrets Manager
data "aws_secretsmanager_secret" "nomad_bootstrap_token" {
  name = data.terraform_remote_state.clusters.outputs.nomad_token_secret_name
}

data "aws_secretsmanager_secret_version" "nomad_bootstrap_token" {
  secret_id = data.aws_secretsmanager_secret.nomad_bootstrap_token.id
}

# Local values from remote state
locals {
  vault_addr   = data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url
  vault_token  = jsondecode(data.aws_secretsmanager_secret_version.vault_root_token.secret_string).root_token
  nomad_addr   = data.terraform_remote_state.clusters.outputs.service_urls.nomad_server.fqdn_url
  nomad_token  = trimspace(data.aws_secretsmanager_secret_version.nomad_bootstrap_token.secret_string)
}

provider "aws" {
  region = "eu-west-2"
}

provider "vault" {
  address = local.vault_addr
  token   = local.vault_token
}

provider "nomad" {
  address   = local.nomad_addr
  secret_id = local.nomad_token
}

# Get boundary deployment outputs
data "terraform_remote_state" "boundary" {
  backend = "local"

  config = {
    path = "${path.module}/../3_boundary_deploy_aws/terraform.tfstate"
  }
}

# Create a static token for Boundary Egress Worker
resource "vault_token" "boundary_egress_worker" {
  policies = ["boundary-worker-transit-policy"]

  no_parent        = true
  renewable        = false
  ttl              = "0" # No expiration
  explicit_max_ttl = "0" # No maximum TTL

  metadata = {
    purpose = "boundary-egress-worker-kms"
  }
}

# Store the token in Nomad Variables
resource "nomad_variable" "boundary_egress_worker_ec2" {
  path      = "nomad/jobs/boundary-ec2-worker"
  namespace = "default"

  items = {
    vault_token        = vault_token.boundary_egress_worker.client_token
    transit_mount_path = var.transit_mount_path
    kms_key_worker     = var.kms_key_worker
    boundary_version   = var.boundary_version
  }
}

# Store the token in Nomad Variables
resource "nomad_variable" "boundary_egress_worker_ubuntu" {
  path      = "nomad/jobs/boundary-ubuntu-worker"
  namespace = "default"

  items = {
    vault_token        = vault_token.boundary_egress_worker.client_token
    transit_mount_path = var.transit_mount_path
    kms_key_worker     = var.kms_key_worker
    boundary_version   = var.boundary_version
  }
}

# Deploy the Nomad job in ubuntu_remote
resource "nomad_job" "boundary_egress_worker" {
  jobspec = templatefile("${path.module}/ubuntu_remote/11_boundary_worker_config.hcl", {
    ingress_worker_addr = data.terraform_remote_state.boundary.outputs.ingress_worker_address
    vault_addr          = local.vault_addr
  })

  # Ensure the variable is created first
  depends_on = [nomad_variable.boundary_egress_worker_ubuntu]
}

# Deploy the Nomad job in ec2_remote
resource "nomad_job" "boundary_egress_worker_ec2" {
  jobspec = templatefile("${path.module}/ec2/6_boundary_worker_config.hcl", {
    ingress_worker_addr = data.terraform_remote_state.boundary.outputs.ingress_worker_address
    vault_addr          = local.vault_addr
  })

  # Ensure the variable is created first
  depends_on = [nomad_variable.boundary_egress_worker_ec2]
}

