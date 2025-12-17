variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_id" {
  description = "VPC ID from 1_create_clusters (use data source to retrieve)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_ids" {
  description = "List of subnet IDs for Boundary deployment (use data source to retrieve)"
  type        = list(string)
  default     = []
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "dns_zone_name" {
  description = "DNS zone name for Boundary (e.g., example.com)"
  type        = string
}

# Boundary configuration
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

# Database configuration
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

# Vault configuration (automatically retrieved from 1_create_clusters)
variable "vault_namespace" {
  description = "Vault namespace (optional)"
  type        = string
  default     = ""
}

# ACME/Let's Encrypt
variable "owner_email" {
  description = "Email address for Let's Encrypt account"
  type        = string
}

variable "acme_prod" {
  description = "Use ACME production environment"
  type        = bool
  default     = false
}

# Instance configuration
variable "controller_instance_type" {
  description = "Instance type for Boundary controller"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for Boundary worker"
  type        = string
  default     = "t3.medium"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Environment = "demo"
    Project     = "boundary"
  }
}
