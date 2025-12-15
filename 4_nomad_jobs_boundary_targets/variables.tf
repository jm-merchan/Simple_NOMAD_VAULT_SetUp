variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = ""
}

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

variable "ubuntu_host_address" {
  description = "IP or DNS name of the Ubuntu host to reach via Boundary (port 22)"
  type        = string
  default     = "127.0.0.1"
}

variable "boundary_addr" {
  description = "Boundary server address"
  type        = string
  default     = ""
}

variable "boundary_user" {
  description = "Boundary username (password auth). Prefer env vars in production."
  type        = string
  default     = ""
}

variable "boundary_password" {
  description = "Boundary password (password auth). Prefer env vars in production."
  type        = string
  sensitive   = true
  default     = ""
}

variable "boundary_auth_method_id" {
  description = "Boundary password auth method ID (ampw_...). Use output from 3_boundary_deploy_aws/init_boundary when not using BOUNDARY_TOKEN."
  type        = string
  default     = ""
}

variable "ec2_host_address" {
  description = "IP or DNS name of the EC2 host to reach via Boundary (port 22)"
  type        = string
  default     = "127.0.0.1"
}

variable "ec2_ssh_user" {
  description = "SSH username for EC2 instance (typically ec2-user for Amazon Linux)"
  type        = string
  default     = "ec2-user"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key file (vault-private-key.pem)"
  type        = string
  default     = "../1_create_clusters/vault-private-key.pem"
}

variable "ubuntu_ssh_user" {
  description = "SSH username for Ubuntu instance"
  type        = string
}

variable "ubuntu_ssh_password" {
  description = "SSH password for Ubuntu instance"
  type        = string
  sensitive   = true
}

variable "windows_user" {
  description = "Username for Windows 11"
  type        = string
  default     = "admin"
}

variable "windows_password" {
  description = "Password for Windows 11"
  type        = string
  sensitive   = true
}