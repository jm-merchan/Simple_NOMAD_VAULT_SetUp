variable "auth0_password" {
  type = string
}

variable "auth0_username" {
  type    = string
  default = "admin"
}

variable "auth0_name" {
  type    = string
  default = "admin"
}

variable "auth0_email" {
  type    = string
  default = "admin@vaultproject.io"
}

variable "auth0_users" {
  description = "Map of Auth0 users to create"
  type = map(object({
    name  = string
    email = string
    role  = string
  }))
  default = {}
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
  description = "Boundary password auth method ID. If empty, tries to read from remote state."
  type        = string
  default     = ""
}