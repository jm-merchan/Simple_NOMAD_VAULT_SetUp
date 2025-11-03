output "elastic_ips" {
  description = "Elastic IP addresses assigned to instances"
  value = {
    vault_server = {
      allocation_id = aws_eip.vault_server_eip.id
      public_ip     = aws_eip.vault_server_eip.public_ip
      instance_id   = aws_eip.vault_server_eip.instance
    }
    nomad_server = {
      allocation_id = aws_eip.nomad_server_eip.id
      public_ip     = aws_eip.nomad_server_eip.public_ip
      instance_id   = aws_eip.nomad_server_eip.instance
    }
  }
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each instance"
  value = {
    vault_server = "ssh -i ${path.module}/vault-private-key.pem ec2-user@${aws_eip.vault_server_eip.public_ip}"
    nomad_server = "ssh -i ${path.module}/vault-private-key.pem ec2-user@${aws_eip.nomad_server_eip.public_ip}"
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
      https_url = "https://${aws_eip.nomad_server_eip.public_ip}:4646"
      fqdn_url  = "https://nomad-${local.region_sanitized}-${random_string.random_name.result}.${local.domain}:4646"
    }
  }
}

output "retrieve_vault_token" {
  description = "Command to retrieve Vault token from AWS Secret Manager"
  value       = "aws secretsmanager get-secret-value --secret-id initSecret-${random_string.random_name.result} --region ${var.region} --output text --query SecretString | jq -r .root_token"
}

output "retrieve_nomad_token" {
  description = "Command to retrieve Nomad ACL bootstrap token from AWS Secret Manager"
  value       = "aws secretsmanager get-secret-value --secret-id nomad-acl-initSecret-${random_string.random_name.result} --region ${var.region} --output text --query SecretString | jq -r .SecretID"
}

output "nomad_address" {
  description = "Nomad server address and connection information"
  value = {
    public_ip    = aws_eip.nomad_server_eip.public_ip
    https_url    = "https://${aws_eip.nomad_server_eip.public_ip}:4646"
    fqdn         = aws_route53_record.nomad.fqdn
    fqdn_url     = "https://${aws_route53_record.nomad.fqdn}:4646"
    datacenter   = var.nomad_server.datacenter
    region       = var.nomad_server.datacenter
  }
}