# Boundary Deployment on AWS

This Terraform module deploys HashiCorp Boundary on AWS with the following architecture:

- **1 Boundary Controller** - Manages Boundary infrastructure and policies
- **1 Boundary Worker** - Provides proxy access to targets
- **RDS PostgreSQL** - Backend database for Boundary state
- **Vault Transit** - KMS encryption using HashiCorp Vault instead of AWS KMS

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      AWS VPC                             │
│  ┌─────────────────┐        ┌──────────────────┐       │
│  │   Boundary      │◄──────►│  RDS PostgreSQL  │       │
│  │   Controller    │        │                  │       │
│  │                 │        └──────────────────┘       │
│  │  - API: 9200    │                                    │
│  │  - Cluster: 9201│        ┌──────────────────┐       │
│  │  - Ops: 9203    │◄──────►│  Vault Server    │       │
│  └────────┬────────┘        │  (Transit KMS)   │       │
│           │                  └──────────────────┘       │
│           │                                             │
│           │                                             │
│           ▼                                             │
│  ┌─────────────────┐                                   │
│  │   Boundary      │                                    │
│  │   Worker        │                                    │
│  │                 │                                    │
│  │  - Proxy: 9202  │                                    │
│  └─────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

## Key Features

✅ **Single Controller Instance** - Stateless controller deployment (no HA needed for demo)  
✅ **Dedicated Worker** - Separate EC2 instance for proxy connections  
✅ **Vault Transit KMS** - Uses Vault Transit engine instead of cloud KMS  
✅ **Same VPC as Vault/Nomad** - Deployed in existing infrastructure  
✅ **TLS with Let's Encrypt** - Automatic certificate generation  
✅ **Route53 DNS** - Automatic DNS configuration  

## Prerequisites

1. **Completed `1_create_clusters` deployment** with:
   - VPC and subnets
   - Vault server running and unsealed
   - Route53 DNS zone configured

2. **Vault Access**:
   - Vault root token or admin token
   - Vault server reachable from Boundary instances

3. **AWS Credentials** configured with appropriate permissions

4. **Domain Name** with Route53 hosted zone

## Vault Transit Setup

This module automatically configures Vault Transit engine with:

- Transit mount at `transit/`
- Four encryption keys:
  - `boundary-root` - Root encryption
  - `boundary-worker-auth` - Worker authentication
  - `boundary-recovery` - Recovery operations
  - `boundary-bsr` - Session recording

- Vault policy for Boundary access
- Long-lived periodic token (auto-renewing)

## Quick Start

### 1. Copy and Configure Variables

```bash
cd 5_boundary_deploy_aws
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and update:

```hcl
# Get these from 1_create_clusters outputs
key_pair_name = "vault-key-xxxx"  # From: terraform output -raw ssh_key_name
vault_addr    = "https://X.X.X.X:8200"  # From: terraform output -json service_urls

# Get Vault token
vault_token = "hvs.xxxxx"  # From AWS Secrets Manager or Vault initialization

# Your domain
dns_zone_name = "your-domain.com"
owner_email   = "admin@your-domain.com"

# Boundary license (Enterprise)
boundary_license = "02MV4UU43BK5..."

# Database password (change this!)
db_password = "YourSecurePassword123!"
```

### 2. Get Vault Token

```bash
# From 1_create_clusters directory
aws secretsmanager get-secret-value \
  --secret-id initSecret-XXXX \
  --region eu-west-2 \
  --query SecretString --output text | jq -r .root_token
```

### 3. Deploy Boundary

```bash
terraform init
terraform plan
terraform apply
```

### 4. Access Boundary

After deployment completes:

```bash
# Get the Boundary URL
terraform output boundary_url

# SSH to controller
terraform output -raw ssh_commands
```

## Configuration

### Instance Types

Default: `t3.medium` for both controller and worker

```hcl
controller_instance_type = "t3.medium"
worker_instance_type     = "t3.medium"
```

### Database Configuration

Default: `db.t3.micro` PostgreSQL 13

Configured in module variables:
```hcl
db_instance_class = "db.t3.micro"  # RDS instance type
db_name          = "boundary"
db_username      = "boundary"
db_password      = var.db_password
```

### Network Configuration

The module automatically discovers VPC and subnets from `1_create_clusters`:

```hcl
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["main-vpc"]
  }
}
```

Or specify explicitly:
```hcl
vpc_id     = "vpc-xxxxx"
subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
```

## Security Groups

### Controller Security Group

- **Port 22** (SSH) - From anywhere
- **Port 9200** (API) - From anywhere (HTTPS)
- **Port 9201** (Cluster) - From VPC only
- **Port 9203** (Ops) - From VPC only

### Worker Security Group

- **Port 22** (SSH) - From anywhere
- **Port 9202** (Proxy) - From anywhere

### Database Security Group

- **Port 5432** (PostgreSQL) - From controller only

## Vault Transit Configuration

The module creates a Vault policy that allows Boundary to:

```hcl
path "transit/encrypt/boundary-root" {
  capabilities = ["update"]
}

path "transit/decrypt/boundary-root" {
  capabilities = ["update"]
}

# ... similar for worker-auth, recovery, and bsr keys
```

The Boundary controller and worker configurations use:

```hcl
kms "transit" {
  purpose         = "root"
  address         = "https://vault-server:8200"
  token           = "hvs.xxxxx"
  mount_path      = "transit"
  key_name        = "boundary-root"
  disable_renewal = "false"
}
```

## Post-Deployment Steps

### 1. Initialize Boundary

SSH to the controller:

```bash
ssh -i ../1_create_clusters/vault-private-key.pem ec2-user@<controller-ip>
```

The database is already initialized, but you need to create the initial auth method:

```bash
# Set environment
export BOUNDARY_ADDR=https://127.0.0.1:9200
export BOUNDARY_TLS_INSECURE=true

# Authenticate and set up initial configuration
# Use the recovery KMS to generate a recovery token
boundary authenticate recovery -recovery-key <recovery-key>
```

### 2. Create Admin User

```bash
# Create password auth method
boundary auth-methods create password \
  -name="password" \
  -scope-id=global

# Create admin user
boundary accounts create password \
  -auth-method-id=<auth-method-id> \
  -login-name=admin \
  -password=YourAdminPassword
```

### 3. Verify Worker Connection

```bash
boundary workers list
```

You should see your worker registered and connected.

### 4. Configure Targets

Access the Boundary UI at `https://boundary.your-domain.com:9200` and configure:

- **Projects** - Organize resources
- **Host Catalogs** - Define hosts (EC2 instances, etc.)
- **Host Sets** - Group hosts
- **Targets** - Define connection targets
- **Credentials** - Store access credentials (optional)

## Outputs

```bash
# All outputs
terraform output

# Specific outputs
terraform output boundary_url
terraform output -json boundary_controller
terraform output -json vault_transit
```

## Troubleshooting

### Check Boundary Controller Logs

```bash
ssh -i ../1_create_clusters/vault-private-key.pem ec2-user@<controller-ip>
sudo journalctl -u boundary -f
```

### Check Boundary Worker Logs

```bash
ssh -i ../1_create_clusters/vault-private-key.pem ec2-user@<worker-ip>
sudo journalctl -u boundary -f
```

### Verify Database Connection

```bash
# From controller
psql "postgresql://boundary:password@<db-endpoint>:5432/boundary?sslmode=require"
```

### Test Vault Transit Access

```bash
# From controller or worker
export VAULT_ADDR=https://<vault-ip>:8200
export VAULT_TOKEN=hvs.xxxxx

vault write transit/encrypt/boundary-root plaintext=$(echo "test" | base64)
```

### Common Issues

1. **Boundary won't start**: Check Vault connectivity and transit keys
2. **Worker not connecting**: Verify controller cluster address and worker-auth KMS
3. **Database connection failed**: Check RDS security group and connection string
4. **TLS certificate issues**: Verify Route53 DNS and ACME challenge

## Differences from GCP Version

| Aspect | GCP Version | AWS Version |
|--------|-------------|-------------|
| Instances | 3 controllers (auto-scaling) | 1 controller (stateless) |
| Workers | Not included | 1 dedicated worker |
| KMS | Google Cloud KMS | Vault Transit |
| Database | Cloud SQL | RDS PostgreSQL |
| Load Balancer | Network Load Balancer | Direct EIP access |
| Networking | VPC Peering for DB | VPC with security groups |

## Cleanup

```bash
terraform destroy
```

This will remove:
- Boundary controller and worker instances
- RDS database
- Security groups
- Elastic IPs
- Route53 records
- Vault transit keys and policy

## References

- [Boundary Documentation](https://developer.hashicorp.com/boundary/docs)
- [Vault Transit KMS](https://developer.hashicorp.com/boundary/docs/configuration/kms/transit)
- [Boundary AWS Reference Architecture](https://developer.hashicorp.com/boundary/docs/install-boundary/architecture)

## License

Enterprise license required for Boundary Enterprise features.
