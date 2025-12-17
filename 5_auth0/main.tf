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
  }
}

provider "auth0" {
  # Uses AUTH0_DOMAIN, AUTH0_CLIENT_ID, AUTH0_CLIENT_SECRET env vars
}

provider "vault" {
  # Uses VAULT_ADDR and VAULT_TOKEN env vars
}

provider "nomad" {
  # Uses NOMAD_ADDR and NOMAD_TOKEN env vars
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

locals {
  boundary_password_auth_method_id = var.boundary_auth_method_id != "" ? var.boundary_auth_method_id : try(data.terraform_remote_state.init_boundary.outputs.password_auth_method_id, "")
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
