# HashiCorp Vault & Nomad Enterprise Deployment

This Terraform project deploys a complete HashiCorp infrastructure stack on AWS, including:
- **Vault Enterprise** - Secrets management and encryption
- **Nomad Enterprise** - Container orchestration and workload scheduling

## Architecture

### Infrastructure Components
- **VPC** with public subnet
- **Vault Server** - Single node with auto-unseal (AWS KMS)
- **Nomad Server** - Single node with Docker driver support
- **TLS Certificates** - Let's Encrypt for Vault, self-signed for Nomad
- **DNS** - Route53 records for both services
- **Security** - IAM roles, security groups, ACLs enabled

### Features
- ✅ Vault Enterprise with AWS KMS auto-unseal
- ✅ Nomad Enterprise with Docker task driver
- ✅ Automatic TLS/mTLS configuration
- ✅ ACL systems enabled and bootstrapped
- ✅ Secure credential storage in AWS Secrets Manager
- ✅ Bridge networking for container workloads
- ✅ Automated initialization and bootstrap

## Prerequisites

1. **Terraform** >= 1.0
2. **AWS Account** with appropriate permissions
3. **Domain** registered in Route53
4. **License Keys**:
   - Vault Enterprise license
   - Nomad Enterprise license

## Configuration

### Required Variables

Create a `terraform.tfvars` file:

```hcl
# AWS Configuration
region            = "eu-west-2"
dns_zone_name_ext = "example.com"
owner_email       = "admin@example.com"

# Vault Configuration
vault_server = {
  name           = "vault-server-1"
  license_key    = "02XCV4UU43BK..."  # Your Vault license
  instance_type  = "m5.large"
  environment    = "production"
  application    = "vault-app"
  vault_version  = "1.20.4+ent"
  volume_size    = 20
  custom_message = "HashiCorp Vault Enterprise"
  additional_tags = {
    Backup = "daily"
    Owner  = "platform-team"
  }
}

# Nomad Configuration
nomad_server = {
  name                        = "nomad-server-1"
  license_key                 = "02MV4UTC3BK..."  # Your Nomad license
  instance_type               = "m5.large"
  environment                 = "production"
  application                 = "nomad-app"
  nomad_version               = "1.8.4+ent"
  nomad_podman_driver_version = "0.6.0"
  datacenter                  = "dc1"
  volume_size                 = 20
  custom_message              = "HashiCorp Nomad Enterprise"
  additional_tags = {
    Backup = "daily"
    Owner  = "platform-team"
  }
}

# License Expiration (optional)
vault_license_expires = "2026-12-31"
nomad_license_expires = "2026-12-31"
```

## Deployment

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Plan Deployment

```bash
terraform plan
```

### 3. Apply Configuration

```bash
terraform apply
```

### 4. Retrieve Outputs

```bash
# Get all outputs
terraform output

# Specific outputs
terraform output nomad_address
terraform output service_urls
```

## Post-Deployment Access

### Vault Access

1. **Retrieve Root Token**:
```bash
terraform output -raw retrieve_vault_token | bash
```

2. **Access Vault UI**:
```bash
# Get URL from outputs
terraform output service_urls

# Example: https://vault-eu-west-2-xxxx.example.com:8200
```

3. **Configure CLI**:
```bash
export VAULT_ADDR="https://vault-eu-west-2-xxxx.example.com:8200"
export VAULT_TOKEN="s.xxxxxxxxxxxxxxxx"
vault status
```

### Nomad Access

1. **Retrieve Bootstrap Token**:
```bash
terraform output -raw retrieve_nomad_token | bash
```

2. **Access Nomad UI**:
```bash
# Get URL from outputs
terraform output nomad_address

# Example: https://nomad-eu-west-2-xxxx.example.com:4646
```

3. **Configure CLI**:
```bash
# SSH to Nomad server
terraform output -raw ssh_connection_commands | jq -r .nomad_server | bash

# Environment is already configured
export NOMAD_TOKEN="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
nomad status
```

## SSH Access

Connect to instances:

```bash
# Vault server
ssh -i vault-private-key.pem ec2-user@<vault-ip>

# Nomad server
ssh -i vault-private-key.pem ec2-user@<nomad-ip>
```

## Nomad Usage Examples

### Run a Simple Job

```bash
# Create a simple job
cat > example.nomad <<EOF
job "nginx" {
  datacenters = ["dc1"]
  type = "service"

  group "web" {
    count = 1

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }

    network {
      port "http" {
        static = 8080
      }
    }
  }
}
EOF

# Run the job
nomad job run example.nomad

# Check status
nomad job status nginx
```

## Security

### TLS/mTLS Configuration

- **Vault**: Uses Let's Encrypt certificates
- **Nomad**: Uses self-signed certificates with mTLS
- All communication is encrypted

### ACL Systems

Both Vault and Nomad have ACL systems enabled:

- Bootstrap tokens are stored in AWS Secrets Manager
- Create policies and tokens for team members
- Never use bootstrap tokens in production workloads

### IAM Permissions

The deployment creates minimal IAM roles with:
- Secrets Manager access for licenses and certificates
- KMS access for Vault auto-unseal
- SSM Parameter Store for benchmark results

## Monitoring & Logs

### Check Service Status

```bash
# Vault
ssh ec2-user@<vault-ip> 'sudo systemctl status vault'

# Nomad
ssh ec2-user@<nomad-ip> 'sudo systemctl status nomad'
```

### View Logs

```bash
# Installation logs
ssh ec2-user@<nomad-ip> 'cat /var/log/nomad-install.log'

# Service logs
ssh ec2-user@<nomad-ip> 'sudo journalctl -u nomad -f'
```

## Troubleshooting

### Vault Issues

1. **Vault Sealed**: Check KMS permissions
2. **TLS Errors**: Verify Let's Encrypt certificates in Secrets Manager
3. **Init Failed**: Check `/var/log/vault.log`

### Nomad Issues

1. **TLS Certificate Errors**: 
   - Verify region matches datacenter in config
   - Check certificates: `ls -la /opt/nomad/tls/`

2. **Docker Not Available**:
   ```bash
   sudo systemctl status docker
   sudo systemctl start docker
   ```

3. **ACL Bootstrap Failed**:
   ```bash
   # Re-run bootstrap script
   /home/ec2-user/bootstrap-nomad-acl.sh
   ```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note**: This will delete all resources including:
- EC2 instances
- Elastic IPs
- Secrets in Secrets Manager (after 7-day recovery window)
- Route53 records
- VPC and networking

## Architecture Decisions

### Why Single Node?

This deployment uses single-node setups for simplicity. For production:
- Deploy 3-5 Vault servers with Raft storage
- Deploy 3-5 Nomad servers for high availability
- Separate Nomad clients for workload execution

### Why Docker Instead of Podman?

Docker is readily available in Amazon Linux 2 repositories. Podman requires additional configuration and is not easily available.

### Why Root for Nomad?

Nomad clients require root privileges for:
- Creating mount points and namespaces
- Managing cgroups
- Bind-mounting volumes
- Container isolation

## License

This project is for demonstration purposes. Ensure you have valid HashiCorp Enterprise licenses for production use.

## References

- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Nomad Documentation](https://developer.hashicorp.com/nomad/docs)
- [Vault Production Deployment](https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-deployment-guide)
- [Nomad Production Deployment](https://developer.hashicorp.com/nomad/tutorials/enterprise/production-deployment-guide-vm-with-consul)
