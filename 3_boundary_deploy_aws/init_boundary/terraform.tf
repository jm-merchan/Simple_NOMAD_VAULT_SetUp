terraform {
  required_version = ">= 1.0"

  required_providers {
    boundary = {
      source  = "hashicorp/boundary"
      version = "~> 1.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Remote state from parent boundary deployment
data "terraform_remote_state" "boundary" {
  backend = "local"

  config = {
    path = "../terraform.tfstate"
  }
}

# Remote state from 1_create_clusters for Vault token
data "terraform_remote_state" "clusters" {
  backend = "local"

  config = {
    path = "../../1_create_clusters/terraform.tfstate"
  }
}

# Get Vault token from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "vault_token" {
  secret_id = data.terraform_remote_state.clusters.outputs.vault_token_secret_name
}

# Extract all needed values from remote states
locals {
  vault_addr         = data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url
  region             = var.region
  vault_token        = jsondecode(data.aws_secretsmanager_secret_version.vault_token.secret_string).root_token
  boundary_addr      = data.terraform_remote_state.boundary.outputs.boundary_url
  transit_mount_path = data.terraform_remote_state.boundary.outputs.vault_transit.mount_path
  kms_key_recovery   = data.terraform_remote_state.boundary.outputs.vault_transit.keys.recovery
}

# AWS Provider
provider "aws" {
  region = var.region
}

provider "boundary" {
  addr             = local.boundary_addr
  recovery_kms_hcl = <<EOT
kms "transit" {
  purpose            = "recovery"
  address            = "${local.vault_addr}"
  token              = "${local.vault_token}"
  disable_renewal    = false
  mount_path         = "${local.transit_mount_path}"
  key_name           = "${local.kms_key_recovery}"
}
EOT
}
