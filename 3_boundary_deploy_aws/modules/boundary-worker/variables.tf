variable "vpc_id" {
  description = "VPC ID where Boundary worker will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for Boundary worker deployment"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Boundary worker"
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

variable "controller_address" {
  description = "Boundary controller cluster address (private IP)"
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

variable "kms_key_worker" {
  description = "Name of Vault transit key for worker-auth"
  type        = string
  default     = "boundary-worker-auth"
}

variable "worker_tags" {
  description = "Tags to apply to the worker for filtering"
  type        = map(string)
  default = {
    type = "worker"
  }
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
