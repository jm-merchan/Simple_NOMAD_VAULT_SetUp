variable "nomad_server_address" {
  description = "Nomad server address for JWKS URL (set via TF_VAR_nomad_server_address env var)"
  type        = string
  
  validation {
    condition     = var.nomad_server_address != "" && var.nomad_server_address != "null"
    error_message = "nomad_server_address must be set. Export: TF_VAR_nomad_server_address=$NOMAD_ADDR"
  }
}
