output "boundary_controller" {
  description = "Boundary controller information"
  value = {
    instance_id = module.boundary_controller.controller_instance_id
    private_ip  = module.boundary_controller.controller_private_ip
    public_ip   = module.boundary_controller.controller_public_ip
    api_url     = module.boundary_controller.api_url
    fqdn_url    = module.boundary_controller.fqdn_url
  }
}

output "boundary_worker" {
  description = "Boundary worker information"
  value = {
    instance_id = module.boundary_worker.worker_instance_id
    private_ip  = module.boundary_worker.worker_private_ip
    public_ip   = module.boundary_worker.worker_public_ip
  }
}

output "database" {
  description = "Database connection information"
  value = {
    endpoint = module.boundary_controller.database_endpoint
    address  = module.boundary_controller.database_address
  }
  sensitive = true
}

output "vault_transit" {
  description = "Vault transit configuration"
  value = {
    mount_path = vault_mount.transit.path
    keys = {
      root        = vault_transit_secret_backend_key.boundary_root.name
      worker_auth = vault_transit_secret_backend_key.boundary_worker_auth.name
      recovery    = vault_transit_secret_backend_key.boundary_recovery.name
      bsr         = vault_transit_secret_backend_key.boundary_bsr.name
    }
    controller_policy = vault_policy.boundary_controller.name
    worker_policy     = vault_policy.boundary_worker.name
  }
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    controller = "ssh -i ../1_create_clusters/vault-private-key.pem ec2-user@${module.boundary_controller.controller_public_ip}"
    worker     = "ssh -i ../1_create_clusters/vault-private-key.pem ec2-user@${module.boundary_worker.worker_public_ip}"
  }
}

output "boundary_url" {
  description = "Boundary web UI URL"
  value       = "https://${aws_route53_record.boundary.fqdn}:9200"
}

output "ingress_worker_address" {
  description = "Ingress worker address for egress workers to connect to"
  value       = "${module.boundary_worker.worker_public_ip}:9201"
}

output "next_steps" {
  description = "Next steps to configure Boundary"
  value       = <<-EOT
    Boundary has been deployed successfully!
    
    1. Access Boundary UI: https://${aws_route53_record.boundary.fqdn}:9200
    
    2. SSH to controller to initialize Boundary:
       ssh -i ../1_create_clusters/vault-private-key.pem ec2-user@${module.boundary_controller.controller_public_ip}
    
    3. After SSH, authenticate with Boundary:
       boundary authenticate password -auth-method-id=<auth-method-id> -login-name=admin -password=<password>
    
    4. Configure Boundary targets, hosts, and credentials using the Boundary CLI or UI
    
    5. Verify worker connection:
       boundary workers list
    
    Note: Boundary is using Vault Transit for KMS encryption.
    Vault Transit mount: ${vault_mount.transit.path}
  EOT
}
