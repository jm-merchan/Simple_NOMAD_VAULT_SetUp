terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.4.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "2.5.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Remote state for 1_create_clusters
data "terraform_remote_state" "clusters" {
  backend = "local"

  config = {
    path = "../1_create_clusters/terraform.tfstate"
  }
}

# AWS Provider - extract region from vault URL (e.g., https://vault-eu-west-2-lxql.domain.com:8200)
provider "aws" {
  region = var.region
}

# Get Vault token from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "vault_token" {
  secret_id = data.terraform_remote_state.clusters.outputs.vault_token_secret_name
}

# Get Nomad token from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "nomad_token" {
  secret_id = data.terraform_remote_state.clusters.outputs.nomad_token_secret_name
}

locals {
  vault_token = jsondecode(data.aws_secretsmanager_secret_version.vault_token.secret_string).root_token
  nomad_token = trimspace(data.aws_secretsmanager_secret_version.nomad_token.secret_string)
  vault_addr  = data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url
  nomad_addr  = data.terraform_remote_state.clusters.outputs.service_urls.nomad_server.fqdn_url
}

provider "vault" {
  address = local.vault_addr
  token   = local.vault_token
}

provider "nomad" {
  address   = local.nomad_addr
  secret_id = local.nomad_token
}