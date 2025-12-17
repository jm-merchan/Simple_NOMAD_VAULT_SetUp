variable "nomad_server_address" {
  description = "Nomad server address for JWKS URL (automatically retrieved from remote state)"
  type        = string
  default     = ""
}

variable "region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}