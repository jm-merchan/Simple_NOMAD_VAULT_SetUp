variable "vpc_id" {
  description = "VPC ID where Boundary will be deployed"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for Boundary deployment"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Boundary controller"
  type        = string
  default     = "t3.medium"
}

variable "disk_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 20
}

variable "boundary_version" {
  description = "Boundary version to install"
  type        = string
  default     = "0.18.1+ent"
}

variable "boundary_license" {
  description = "Boundary Enterprise license"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the Boundary cluster"
  type        = string
  default     = "boundary"
}

variable "dns_zone_name" {
  description = "DNS zone name for Boundary"
  type        = string
}

# Database configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "boundary"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "boundary"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# TLS configuration
variable "tls_cert_pem" {
  description = "TLS certificate in PEM format"
  type        = string
}

variable "tls_key_pem" {
  description = "TLS private key in PEM format"
  type        = string
  sensitive   = true
}

variable "tls_ca_pem" {
  description = "TLS CA certificate in PEM format"
  type        = string
}

# Vault Transit configuration
variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

variable "vault_namespace" {
  description = "Vault namespace (optional)"
  type        = string
  default     = ""
}

variable "vault_token" {
  description = "Vault token for transit access"
  type        = string
  sensitive   = true
}

variable "transit_mount_path" {
  description = "Vault transit mount path"
  type        = string
  default     = "transit"
}

variable "kms_key_root" {
  description = "Name of Vault transit key for root encryption"
  type        = string
  default     = "boundary-root"
}

variable "kms_key_worker" {
  description = "Name of Vault transit key for worker-auth"
  type        = string
  default     = "boundary-worker-auth"
}

variable "kms_key_recovery" {
  description = "Name of Vault transit key for recovery"
  type        = string
  default     = "boundary-recovery"
}

variable "kms_key_bsr" {
  description = "Name of Vault transit key for BSR (session recording)"
  type        = string
  default     = "boundary-bsr"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
