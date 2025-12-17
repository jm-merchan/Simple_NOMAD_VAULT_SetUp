terraform {
  required_providers {
    auth0 = {
      source  = "auth0/auth0"
      version = "~> 1.0"
    }
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

data "terraform_remote_state" "clusters" {
  backend = "local"
  config = {
    path = "${path.module}/../1_create_clusters/terraform.tfstate"
  }
}

data "terraform_remote_state" "boundary" {
  backend = "local"
  config = {
    path = "${path.module}/../3_boundary_deploy_aws/terraform.tfstate"
  }
}

data "terraform_remote_state" "init_boundary" {
  backend = "local"

  config = {
    path = "${path.module}/../3_boundary_deploy_aws/init_boundary/terraform.tfstate"
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
  vault_addr                       = data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url
  vault_token                      = jsondecode(data.aws_secretsmanager_secret_version.vault_root_token.secret_string).root_token
  nomad_addr                       = data.terraform_remote_state.clusters.outputs.service_urls.nomad_server.fqdn_url
  nomad_token                      = trimspace(data.aws_secretsmanager_secret_version.nomad_bootstrap_token.secret_string)
  boundary_password_auth_method_id = var.boundary_auth_method_id != "" ? var.boundary_auth_method_id : try(data.terraform_remote_state.init_boundary.outputs.password_auth_method_id, "")
}

provider "aws" {
  region = "eu-west-2"
}

provider "auth0" {
  # Uses AUTH0_DOMAIN, AUTH0_CLIENT_ID, AUTH0_CLIENT_SECRET env vars
}

provider "vault" {
  address = local.vault_addr
  token   = local.vault_token
}

provider "nomad" {
  address   = local.nomad_addr
  secret_id = local.nomad_token
}

provider "boundary" {
  # If not set, these are read from env vars (BOUNDARY_ADDR / BOUNDARY_TOKEN).
  addr = var.boundary_addr != "" ? var.boundary_addr : null

  # Preferred: authenticate via env var BOUNDARY_TOKEN.
  # Fallback: authenticate via password auth (created in init_boundary).
  auth_method_id         = local.boundary_password_auth_method_id != "" ? local.boundary_password_auth_method_id : null
  auth_method_login_name = var.boundary_user != "" ? var.boundary_user : null
  auth_method_password   = var.boundary_password != "" ? var.boundary_password : null
}
