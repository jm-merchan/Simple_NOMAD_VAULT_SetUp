terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
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
  vault_addr  = data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url
  vault_token = jsondecode(data.aws_secretsmanager_secret_version.vault_root_token.secret_string).root_token
  nomad_addr  = data.terraform_remote_state.clusters.outputs.service_urls.nomad_server.fqdn_url
  nomad_token = trimspace(data.aws_secretsmanager_secret_version.nomad_bootstrap_token.secret_string)
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

# 1. Enable KMIP Secrets Engine
resource "vault_mount" "kmip" {
  path        = "kmip"
  type        = "kmip"
  description = "KMIP Secrets Engine"
}

# 1b. Configure KMIP CA (required before generating credentials)
resource "vault_generic_endpoint" "kmip_config" {
  path                 = "${vault_mount.kmip.path}/config"
  disable_read         = false
  disable_delete       = true
  data_json            = jsonencode({
    listen_addrs         = ["0.0.0.0:5696"]
    server_hostnames     = [replace(data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url, "https://", "")]
    server_ips           = []
    tls_ca_key_type      = "rsa"
    tls_ca_key_bits      = 2048
    default_tls_client_key_type = "rsa"
    default_tls_client_key_bits = 2048
    default_tls_client_ttl      = 86400
  })
  
  depends_on = [vault_mount.kmip]
}

# 2. Create KMIP Scope
resource "vault_kmip_secret_scope" "finance" {
  path  = vault_mount.kmip.path
  scope = "finance"
  force = true
  
  depends_on = [vault_generic_endpoint.kmip_config]
}

# 3. Create KMIP Role
resource "vault_kmip_secret_role" "admin" {
  path                     = vault_kmip_secret_scope.finance.path
  scope                    = vault_kmip_secret_scope.finance.scope
  role                     = "admin"
  tls_client_key_type      = "rsa"
  tls_client_key_bits      = 2048
  tls_client_ttl           = 86400
  operation_all            = true
}

# 4. Generate Credentials (Certificate & Key)
# Note: This endpoint is write-only. Need to remove from state first if it exists:
# terraform state rm vault_generic_endpoint.kmip_creds
resource "vault_generic_endpoint" "kmip_creds" {
  path                 = "${vault_mount.kmip.path}/scope/${vault_kmip_secret_scope.finance.scope}/role/${vault_kmip_secret_role.admin.role}/credential/generate"
  disable_read         = true
  disable_delete       = true
  data_json            = jsonencode({
    format = "pem"
  })
  
  write_fields = ["ca_chain", "certificate", "private_key", "serial_number"]
  
  # Prevent Terraform from trying to refresh this resource
  lifecycle {
    ignore_changes = all
  }
}

# 5. Store Credentials in Nomad Variables
resource "nomad_variable" "kmip_creds" {
  path      = "nomad/jobs/kmip-test"
  namespace = "default"

  items = {
    # KMIP credential generation returns: ca_chain (array), certificate, private_key, serial_number
    # ca_chain is a JSON array, so we need to decode and join it
    ca_pem          = join("\n", jsondecode(lookup(vault_generic_endpoint.kmip_creds.write_data, "ca_chain", "[]")))
    client_cert_pem = lookup(vault_generic_endpoint.kmip_creds.write_data, "certificate", "")
    client_key_pem  = lookup(vault_generic_endpoint.kmip_creds.write_data, "private_key", "")
    serial_number   = lookup(vault_generic_endpoint.kmip_creds.write_data, "serial_number", "")
    vault_addr      = data.terraform_remote_state.clusters.outputs.service_urls.vault_server.fqdn_url
  }
}

# 6. Nomad Job to Test KMIP
resource "nomad_job" "kmip_test" {
  jobspec = templatefile("${path.module}/kmip_test.hcl.tpl", {
    # We can pass variables here if needed, but the job will use Nomad Variables
  })
  
  depends_on = [nomad_variable.kmip_creds]
}
