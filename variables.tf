variable "region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}

# DNS zone name for TFE (optional - for Let's Encrypt certificates)
variable "dns_zone_name_ext" {
  type        = string
  description = "Name of the DNS zone (e.g., example.com)"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
  default     = ""
}

variable "vault_server" {
  description = "Vault server configuration"
  type = object({
    name            = string
    license_key     = string
    instance_type   = string
    environment     = string
    application     = string
    volume_size     = number
    custom_message  = string
    additional_tags = map(string)
    vault_version   = string
  })
  default = {
    name           = "vault-server-1"
    license_key    = ""
    instance_type  = "m5.large"
    environment    = "development"
    application    = "vault-app"
    vault_version  = "1.20.4+ent"
    volume_size    = 20
    custom_message = "Welcome to Vault Server 1 - HashiCorp Vault Service"
    additional_tags = {
      Backup = "daily"
      Owner  = "team-security"
      Role   = "vaultserver"
    }
  }
}

variable "vault_benchmark" {
  description = "Vault benchmark server configuration"
  type = object({
    name            = string
    instance_type   = string
    environment     = string
    application     = string
    volume_size     = number
    custom_message  = string
    additional_tags = map(string)
  })
  default = {
    name           = "vault-benchmark-1"
    instance_type  = "t3.xlarge"
    environment    = "development"
    application    = "vault-benchmark"
    volume_size    = 30
    custom_message = "Welcome to Vault Benchmark Server 1 - Performance Testing Suite"
    additional_tags = {
      Backup = "hourly"
      Owner  = "team-performance"
      Role   = "benchmarkserver"
    }
  }
}

variable "vault_token" {
  description = "Vault root token for authentication"
  type        = string
  default     = "dev-only-token"
  sensitive   = true
}

variable "owner_email" {
  description = "Email address for Let's Encrypt account registration"
  type        = string
  default     = ""

}

variable "vault_log_path" {
  description = "Path to store Vault logs. Logrotate and Ops Agent are configured to operate with logs in this path"
  type        = string
  default     = "/var/log/vault.log"
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "development"
}

variable "vault_license" {
  description = "HashiCorp Vault Enterprise license key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_license_expires" {
  description = "Vault Enterprise license expiration date (optional)"
  type        = string
  default     = ""
}

variable "nomad_server" {
  description = "Nomad server configuration"
  type = object({
    name                        = string
    license_key                 = string
    instance_type               = string
    environment                 = string
    application                 = string
    volume_size                 = number
    custom_message              = string
    additional_tags             = map(string)
    nomad_version               = string
    datacenter                  = string
  })
  default = {
    name                        = "nomad-server-1"
    license_key                 = ""
    instance_type               = "m5.large"
    environment                 = "development"
    application                 = "nomad-app"
    nomad_version               = "1.8.4+ent"
    datacenter                  = "dc1"
    volume_size                 = 20
    custom_message              = "Welcome to Nomad Server 1 - HashiCorp Nomad Service"
    additional_tags = {
      Backup = "daily"
      Owner  = "team-platform"
      Role   = "nomadserver"
    }
  }
}

variable "nomad_license" {
  description = "HashiCorp Nomad Enterprise license key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "nomad_license_expires" {
  description = "Nomad Enterprise license expiration date (optional)"
  type        = string
  default     = ""
}