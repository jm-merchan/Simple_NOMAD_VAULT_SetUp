# All configuration automatically retrieved from terraform state
# Only user credentials need to be configured

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

variable "region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}