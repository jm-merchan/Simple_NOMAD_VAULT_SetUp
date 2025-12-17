output "export_vault_token_command" {
  description = "Command to export Vault token as environment variable"
  value       = "export VAULT_TOKEN=$(aws secretsmanager get-secret-value --secret-id initSecret-${random_string.random_name.result} --region ${var.region} --output text --query .value)"
  sensitive   = true
}
output "export_nomad_token_command" {
  description = "Command to export Nomad ACL bootstrap token as environment variable"
  value       = "export NOMAD_TOKEN=$(aws secretsmanager get-secret-value --secret-id nomad-acl-initSecret-${random_string.random_name.result} --region ${var.region} --output text --query .value)"
  sensitive   = true
}
output "export_vault_addr_command" {
  description = "Command to export Vault address as environment variable"
  value       = "export VAULT_ADDR=https://vault-${local.region_sanitized}-${random_string.random_name.result}.${local.domain}:8200"
}
output "export_nomad_addr_command" {
  description = "Command to export Nomad address as environment variable"
  value       = "export NOMAD_ADDR=https://nomad-${local.region_sanitized}-${random_string.random_name.result}.${local.domain}"
}



output "ssh_connection_commands" {
  description = "SSH commands to connect to each instance"
  value = {
    vault_server = "ssh -i ${path.module}/vault-private-key.pem ec2-user@${aws_eip.vault_server_eip.public_ip}"
    nomad_server = "ssh -i ${path.module}/vault-private-key.pem ec2-user@${aws_eip.nomad_server_eip.public_ip}"
    nomad_client = "ssh -i ${path.module}/vault-private-key.pem ec2-user@${aws_instance.nomad_client.public_ip}"
  }
}

output "service_urls" {
  description = "URLs to access vault and nomad services"
  value = {
    vault_server = {
      https_url = "https://${aws_eip.vault_server_eip.public_ip}:8200"
      fqdn_url  = "https://vault-${local.region_sanitized}-${random_string.random_name.result}.${local.domain}:8200"
    }
    nomad_server = {
      direct_https_url = "https://${aws_eip.nomad_server_eip.public_ip}:4646"
      alb_https_url    = "https://${aws_lb.nomad_alb.dns_name}"
      fqdn_url         = "https://nomad-${local.region_sanitized}-${random_string.random_name.result}.${local.domain}"
    }
  }
}

output "retrieve_vault_token" {
  description = "Command to retrieve Vault token from AWS Secret Manager"
  value       = "aws secretsmanager get-secret-value --secret-id initSecret-${random_string.random_name.result} --region ${var.region} --output text --query SecretString | jq -r .root_token"
}

output "retrieve_nomad_token" {
  description = "Command to retrieve Nomad ACL bootstrap token from AWS Secret Manager"
  value       = "aws secretsmanager get-secret-value --secret-id nomad-acl-initSecret-${random_string.random_name.result} --region ${var.region} --output text --query SecretString"
}