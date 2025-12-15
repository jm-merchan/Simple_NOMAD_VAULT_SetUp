variable "transit_mount_path" {
  description = "Vault Transit mount path"
  type        = string
  default     = "transit"
}

variable "kms_key_worker" {
  description = "Vault Transit key name for worker-auth"
  type        = string
  default     = "boundary-worker-auth"
}

variable "boundary_version" {
  description = "Boundary version to install"
  type        = string
  default     = "0.18.1+ent"
}
