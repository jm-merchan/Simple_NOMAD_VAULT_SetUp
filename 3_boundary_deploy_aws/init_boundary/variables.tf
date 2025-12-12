variable "boundary_addr" {
  description = "Boundary Controller API address"
  type        = string
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault token for recovery KMS"
  type        = string
  sensitive   = true
}

variable "transit_mount_path" {
  description = "Vault Transit mount path"
  type        = string
  default     = "transit"
}

variable "kms_key_recovery" {
  description = "Vault Transit key name for recovery"
  type        = string
  default     = "boundary-recovery"
}

variable "boundary_user" {
  description = "Initial Boundary Admin User"
  type        = string
  default     = "admin"
}

variable "boundary_password" {
  description = "Password for Boundary Admin"
  type        = string
  sensitive   = true
}
