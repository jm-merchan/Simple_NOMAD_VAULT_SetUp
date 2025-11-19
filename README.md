# HashiCorp Vault & Nomad Enterprise Deployment

This Terraform project deploys a complete HashiCorp infrastructure stack on AWS, including:
- **Vault Enterprise** - Secrets management and encryption
- **Nomad Enterprise** - Container orchestration and workload scheduling

## Architecture

### Infrastructure Components
- **VPC** with public subnets across 2 availability zones
- **Vault Server** - Single node with auto-unseal (AWS KMS)
- **Nomad Server** - Single node with Docker driver support
- **Nomad Client** - CoreOS-based client node for workload execution
- **Application Load Balancer (ALB)** - Layer 7 load balancer for Nomad with TLS termination
- **TLS Certificates** - Let's Encrypt (ACME) for both Vault and Nomad (via ALB)
- **DNS** - Route53 records for both services
- **Security** - IAM roles, security groups, ACLs enabled

### Features
- ✅ Vault Enterprise with AWS KMS auto-unseal
- ✅ Nomad Enterprise with Docker task driver
- ✅ Application Load Balancer with Let's Encrypt certificate for Nomad
- ✅ Automatic TLS/mTLS configuration
  - Vault: Let's Encrypt certificates (direct)
  - Nomad: Let's Encrypt on ALB, self-signed internally
- ✅ ACL systems enabled and bootstrapped
- ✅ Secure credential storage in AWS Secrets Manager
- ✅ Bridge networking for container workloads
- ✅ Automated initialization and bootstrap
- ✅ Nomad client with multiple drivers (Podman, QEMU, raw_exec)

### Network Architecture

```
Client → HTTPS (Let's Encrypt) → ALB:443 → HTTPS (self-signed) → Nomad:4646
                                ALB:4646 → HTTPS (self-signed) → Nomad:4646

Client → HTTPS (Let's Encrypt) → Vault:8200
```

**Nomad Access:**
- External clients connect to ALB using valid Let's Encrypt certificate
- ALB terminates TLS and re-encrypts to backend
- Nomad server uses self-signed certificates internally
- DNS: `nomad-region-xxxx.domain.com` → ALB → Nomad Server

## Prerequisites

1. **Terraform** >= 1.11
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

### 1. Authenticate against AWS via Doormat and Initialize Terraform

```bash
cd 1_create_clusters
doormat login -f
eval $(doormat aws -a <account_name> export)

terraform init
```

### 2. Plan Deployment

```bash
terraform plan -var-file=terraform.tfvars
```

### 3. Apply Configuration

```bash
terraform apply -auto-approve -var-file=terraform.tfvars
```

### 4. Retrieve Outputs

```bash
# Get all outputs
terraform output

# Nomad specific outputs
terraform output nomad_address
terraform output nomad_alb_info

# Certificate debug info
terraform output nomad_certificate_debug
```

## Post-Deployment Access

### Vault Access

1. **Retrieve Root Token**:
```bash
export VAULT_TOKEN=$(eval $(terraform output -raw retrieve_vault_token))
```

2. **Retrieve Vault URL***:
```bash
# Get URL from outputs
export VAULT_ADDR=$(terraform output -json | jq -r .service_urls.value.vault_server.fqdn_url)

# Example: https://vault-eu-west-2-xxxx.example.com:8200
```

3. **Verify**:
```bash
vault status
```


### Nomad Access

1. **Retrieve Nomad Bootstrap Token**:
```bash
export NOMAD_TOKEN=$(eval $(terraform output -raw retrieve_nomad_token))
```

2. **Retrieve Nomad URL**: 
```bash
# Get FQDN URL (via ALB with valid Let's Encrypt certificate)
export NOMAD_ADDR=$(terraform output -json | jq -r .service_urls.value.nomad_server.fqdn_url) 

# Create Terraform env for Nomad configuration in following step
export TF_VAR_nomad_server_address=$(echo $NOMAD_ADDR) 
```

3. **Verify**:
```bash
nomad status
```

#### Access Methods

**Via Application Load Balancer (Recommended)**
- URL: `https://nomad-region-xxxx.domain.com` (port 443 or 4646)
- Certificate: Valid Let's Encrypt certificate
- No certificate warnings in browser or CLI

**Direct to Server (Advanced)**
- URL: `https://<nomad-ip>:4646`
- Certificate: Self-signed (will show warnings)
- Requires accepting self-signed certificate or adding CA to trust store

### Nomad Client Access

The deployment includes a CoreOS-based Nomad client for workload execution:

1. **SSH to Nomad Client**:
```bash
# Get SSH command
terraform output -json ssh_connection_commands | jq -r .nomad_client

# Example: ssh -i vault-private-key.pem core@<client-public-ip>
```

2. **Check Client Status**:
```bash
# SSH to client and check status
nomad node status

# Check Podman (container runtime)
podman version
podman ps
```

3. **Client Configuration**:
- **OS**: Amazon Linux 2 (standard AWS Linux distribution)
- **Container Runtime**: Docker (standard container runtime)
- **Drivers**: 
  - Docker driver (containers)
  - QEMU driver (virtual machines)
  - raw_exec driver (direct command execution)
- **Networking**: Connected to Nomad server via private IP
- **QEMU Setup**: QEMU/KVM installed with libvirt for VM workloads

4. **Test Client Drivers**:
```bash
# SSH to client
terraform output -json ssh_connection_commands | jq -r .nomad_client

# Check available drivers
nomad node status -verbose | grep -A 10 Drivers

# Test Docker driver
docker version
docker ps

# Test QEMU driver
virsh version
qemu-system-x86_64 --version

# Test raw_exec driver (should be enabled by default)
nomad run - <<EOF
job "test-raw-exec" {
  datacenters = ["dc1"]
  type = "batch"
  
  group "test" {
    task "hello" {
      driver = "raw_exec"
      
      config {
        command = "echo"
        args = ["Hello from raw_exec driver!"]
      }
    }
  }
}
EOF
```

**Note**: The Nomad client is configured with mutual TLS authentication using certificates generated by the Nomad server. All Nomad CLI commands will automatically use the TLS certificates when you SSH to the client.

### 4. Create Workload Identity federation
This terraform configuration file:
* Configures Vault for JWT authentication with Nomad and creates a KVv2 engine with a secret.
* Deploy a Nomad Job that uses the default JWT Authentication with Vault and retrieves the secret from Vault

![enviromental variables in resulting job](image.png)

The execution is as follow

```bash
cd ../2_workload_identity
terraform init
terraform plan
terraform apply -auto-approve

```

## Security

### TLS/mTLS Configuration

#### Vault
- Uses Let's Encrypt (ACME) certificates
- Certificates stored in AWS Secrets Manager
- Direct TLS termination on Vault server

#### Nomad
- **External Access**: Let's Encrypt (ACME) certificate on Application Load Balancer
  - ALB performs TLS termination with valid public certificate
  - Certificate automatically imported to AWS Certificate Manager (ACM)
  - Accessible via HTTPS on port 443 and 4646
- **Internal Communication**: Self-signed certificates
  - Nomad server uses self-signed certs generated via `nomad tls` commands
  - mTLS between ALB and Nomad backend
  - Client certificates for CLI access

#### Certificate Storage
- **Vault Certificates**: AWS Secrets Manager
  - `vault-tls-certificate-*` - Public certificate
  - `vault-tls-private-key-*` - Private key
  - `vault-tls-ca-certificate-*` - CA chain
- **Nomad Certificates**: 
  - Let's Encrypt cert stored in AWS Secrets Manager and ACM
  - `nomad-tls-certificate-*` - Public certificate
  - `nomad-tls-private-key-*` - Private key  
  - `nomad-tls-ca-certificate-*` - CA chain
  - Self-signed certs stored locally on Nomad server (`/opt/nomad/tls/`)

### ACL Systems

Both Vault and Nomad have ACL systems enabled:

- Bootstrap tokens are stored in AWS Secrets Manager
- Create policies and tokens for team members
- Never use bootstrap tokens in production workloads

### IAM Permissions

The deployment creates minimal IAM roles with:
- Secrets Manager access for licenses and certificates
- KMS access for Vault auto-unseal

## Monitoring & Logs

### View Logs

```bash
# Installation logs
ssh ec2-user@<nomad-ip> 'cat /var/log/nomad-install.log'

# Service logs
ssh ec2-user@<nomad-ip> 'sudo journalctl -u nomad -f'
```

### Verify ALB Health

```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -json nomad_alb_info | jq -r .target_group_arn) \
  --region eu-west-2

# Check ALB listeners
aws elbv2 describe-listeners \
  --load-balancer-arn $(terraform output -json nomad_alb_info | jq -r .alb_arn) \
  --region eu-west-2

# Verify certificate in ACM
aws acm describe-certificate \
  --certificate-arn $(terraform output -json nomad_alb_info | jq -r .acm_cert_arn) \
  --region eu-west-2
```

## Troubleshooting

### Nomad Certificate Issues

**Problem**: Browser shows certificate warning when accessing Nomad

**Solution**: 
1. Ensure you're using the ALB URL (FQDN), not direct IP:
   ```bash
   terraform output nomad_address
   # Use fqdn_url, not direct_https_url
   ```

2. Check certificate status:
   ```bash
   terraform output nomad_certificate_debug
   terraform output nomad_alb_info
   ```

3. Verify DNS propagation:
   ```bash
   nslookup nomad-region-xxxx.domain.com
   # Should return ALB DNS name
   ```

4. Test certificate chain:
   ```bash
   openssl s_client -connect nomad-region-xxxx.domain.com:443 -showcerts
   ```

**Problem**: ALB target unhealthy

**Solution**:
1. Check Nomad server is running:
   ```bash
   ssh ec2-user@<nomad-ip> 'sudo systemctl status nomad'
   ```

2. Verify security groups allow ALB → Nomad communication on port 4646

3. Check Nomad is responding:
   ```bash
   ssh ec2-user@<nomad-ip> 'curl -k https://localhost:4646/v1/status/leader'
   ```


## References

- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Nomad Documentation](https://developer.hashicorp.com/nomad/docs)
- [Vault Production Deployment](https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-deployment-guide)
- [Nomad Production Deployment](https://developer.hashicorp.com/nomad/tutorials/enterprise/production-deployment-guide-vm-with-consul)
