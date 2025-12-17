terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.26.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

# Get Vault token from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "vault_token" {
  secret_id = data.terraform_remote_state.clusters.outputs.vault_token_secret_name
}

locals {
  vault_token = jsondecode(data.aws_secretsmanager_secret_version.vault_token.secret_string).root_token
  vault_addr  = data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url
}

provider "aws" {
  region = var.region
}

provider "acme" {
  server_url = var.acme_prod ? "https://acme-v02.api.letsencrypt.org/directory" : "https://acme-staging-v02.api.letsencrypt.org/directory"
}

provider "vault" {
  address   = local.vault_addr
  token     = local.vault_token
  namespace = var.vault_namespace
}
