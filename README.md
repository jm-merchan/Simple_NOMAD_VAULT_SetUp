# HashiCorp Infrastructure Deployment

This repository contains Terraform configurations for deploying a HashiCorp stack on AWS, including Vault, Nomad, and Boundary with Auth0 OIDC integration.

## Architecture Overview

The infrastructure is deployed in multiple stages with dependencies:

```
1_create_clusters (AWS Infrastructure)
    ↓
    ├── 2_workload_identity (Vault/Nomad Workload Identity)
    ├── 3_boundary_deploy_aws (Boundary Infrastructure)
    │       ↓
    │       └── init_boundary (Boundary Initialization)
    ├── 4_nomad_jobs_boundary_targets (Nomad Jobs & Boundary Workers)
    ├── 5_auth0 (Auth0 OIDC Integration)
    └── 6_kmip_test (KMIP Testing)
```

## Prerequisites

### Required Tools
- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- SSH key pair for EC2 instances (created by Terraform Code)
- Auth0 account (for OIDC integration)

### AWS Requirements
- **Route53 Public Hosted Zone**: A public DNS zone must exist before deployment for ACME/Let's Encrypt certificate generation
  - Example: `example.com` or `subdomain.example.com`
  - Must be publicly resolvable
  - Required for automated TLS certificate generation for Vault, Nomad, and Boundary services
- Valid AWS credentials with permissions to create:
  - VPC, Subnets, Security Groups, Internet Gateways
  - EC2 instances, EIPs, ALBs
  - Route53 DNS records (within existing hosted zone)
  - Secrets Manager secrets
  - KMS keys
  - IAM roles and policies

### Environment Variables
- AWS Credentials
- Auth0 Credentials

#### AWS Configuration
```bash
export AWS_REGION="eu-west-2"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

#### Auth0 Configuration (for workspace 5_auth0)
```bash
export AUTH0_DOMAIN="your-tenant.auth0.com"
export AUTH0_CLIENT_ID="your-management-api-client-id"
export AUTH0_CLIENT_SECRET="your-management-api-client-secret"
```

**Note**: All Vault and Nomad credentials are automatically retrieved from AWS Secrets Manager via Terraform remote state. No manual environment variable configuration needed for VAULT_ADDR, VAULT_TOKEN, NOMAD_ADDR, or NOMAD_TOKEN.

## Deployment Steps

### 1. Create Core Infrastructure (`1_create_clusters`)

This workspace creates the base AWS infrastructure with Vault and Nomad clusters.

**What it creates:**
- VPC with public/private subnets
- Vault server with Transit encryption engine
- Nomad server and client instances
- AWS Secrets Manager secrets for root tokens
- Route53 DNS records
- TLS certificates via ACME

**Prerequisites:**
- Route53 public hosted zone must already exist in your AWS account
- DNS zone must be publicly resolvable for ACME certificate validation

**Steps:**
```bash
cd 1_create_clusters

# Copy and edit terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
# - region: AWS region (e.g., "eu-west-2")
# - vpc_cidr: VPC CIDR block (e.g., "10.0.0.0/16")
# - dns_zone_name: Your existing Route53 public hosted zone (e.g., "example.com")
# - owner_email: Email for Let's Encrypt notifications
# - key_pair_name: Name for the SSH key pair (will be created)

# Deploy
terraform init
terraform plan -var-file=variables.tfvars
terraform apply -auto-approve -var-file=variables.tfvars

# Note the outputs - other workspaces will read from this state
```

**Important Outputs:**
- `vault_token_secret_name` - AWS Secret name for Vault root token
- `nomad_token_secret_name` - AWS Secret name for Nomad bootstrap token
- `service_urls` - URLs for Vault and Nomad services
- `ssh_connection_commands` - SSH commands to access instances using a generated RSA key

---

### 2. Configure Workload Identity (`2_workload_identity`)

Configures Vault and Nomad workload identity integration.

**Dependencies:** Requires `1_create_clusters` to be deployed.

**What it configures:**
- Vault policies and roles
- Nomad workload identity
- JWT authentication

**Steps:**
```bash
cd 2_workload_identity

# Copy and edit variables
cp terraform.tfvars.example variables.tfvars
# Edit variables.tfvars if needed

# Deploy
terraform init
terraform plan -var-file=variables.tfvars
terraform apply -auto-approve -var-file=variables.tfvars
```

**No environment variables required** - automatically reads Vault/Nomad configuration from `1_create_clusters` remote state.

---

### 3. Deploy Boundary (`3_boundary_deploy_aws`)

Deploys Boundary controllers and workers with Vault Transit KMS integration.

**Dependencies:** Requires `1_create_clusters` to be deployed.

**What it creates:**
- Boundary controller cluster with PostgreSQL
- Boundary ingress worker
- ALB for Boundary
- Vault Transit keys for Boundary KMS
- Route53 DNS for Boundary

**Steps:**
```bash
cd 3_boundary_deploy_aws

# Copy and edit terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
# - region
# - key_pair_name
# - dns_zone_name
# - owner_email
# - db_username
# - db_password

# Deploy
terraform init
terraform plan -var-file=variables.tfvars
terraform apply -auto-approve -var-file=variables.tfvars
```

**No environment variables required** - automatically reads Vault configuration from `1_create_clusters` remote state.

#### 3a. Initialize Boundary (`3_boundary_deploy_aws/init_boundary`)

Initializes Boundary with scopes, auth methods, and users.

**Dependencies:** Requires `3_boundary_deploy_aws` to be deployed.

**What it creates:**
- Boundary organization and project scopes
- Password auth method
- Initial admin user
- Host catalogs and targets

**Steps:**
```bash
cd 3_boundary_deploy_aws/init_boundary

# Copy and edit variables
cp variables.tfvars.example variables.tfvars
# Edit variables.tfvars:
# - region
# - boundary_user (admin username)
# - boundary_password (admin password)

# Deploy
terraform init
terraform plan -var-file=variables.tfvars
terraform apply -auto-approve -var-file=variables.tfvars
```

**No environment variables required** - automatically reads all configuration from parent workspace and `1_create_clusters` remote state.

---

### 4. Deploy Nomad Jobs & Boundary Targets (`4_nomad_jobs_boundary_targets`)

Deploys Nomad jobs and configures Boundary egress workers and targets.

**Dependencies:** Requires `1_create_clusters` and `3_boundary_deploy_aws` to be deployed.

**What it creates:**
- Vault policies and SSH CA configuration
- Vault tokens for Boundary
- Nomad variables with credentials
- Boundary egress workers (via Nomad jobs)
- Boundary targets for SSH access

**Steps:**
```bash
cd 4_nomad_jobs_boundary_targets

# Copy and edit variables
cp terraform.tfvars.example variables.tfvars
# Edit variables.tfvars with your values:
# - boundary_addr
# - boundary_user
# - boundary_password
# - ubuntu_host_address
# - ec2_host_address
# - ubuntu_ssh_user
# - ubuntu_ssh_password
# - windows_user
# - windows_password

# Deploy
terraform init
terraform plan -var-file=variables.tfvars
terraform apply -auto-approve -var-file=variables.tfvars
```

**No environment variables required** - automatically reads Vault/Nomad configuration from `1_create_clusters` remote state.

**Note:** Boundary egress workers are deployed as Nomad jobs on EC2 and Ubuntu hosts.

---

### 5. Configure Auth0 OIDC (`5_auth0`)

Configures Auth0 OIDC authentication for Vault, Nomad, and Boundary.

**Dependencies:** Requires `1_create_clusters`, `3_boundary_deploy_aws`, and `init_boundary` to be deployed.

**Prerequisites:**
- Auth0 account
- Auth0 Management API credentials

**What it creates:**
- Auth0 applications for Vault, Nomad, and Boundary
- Auth0 users (dynamically from variable)
- Vault OIDC auth method and policies
- Nomad OIDC auth method and ACL bindings
- Boundary OIDC auth method and users
- Identity groups and role assignments

**Steps:**
```bash
cd 5_auth0

# Set Auth0 environment variables
export AUTH0_DOMAIN="your-tenant.auth0.com"
export AUTH0_CLIENT_ID="your-management-api-client-id"
export AUTH0_CLIENT_SECRET="your-management-api-client-secret"

# Edit variables.tfvars
# Configure:
# - auth0_password (password for all users)
# - auth0_users (map of users with name/email/role)
# - boundary_addr
# - boundary_user
# - boundary_password

# Deploy
terraform init
terraform plan -var-file=variables.tfvars
terraform apply -auto-approve -var-file=variables.tfvars
```

**Environment variables required:**
- `AUTH0_DOMAIN`
- `AUTH0_CLIENT_ID`
- `AUTH0_CLIENT_SECRET`

**Note:** All users defined in `auth0_users` variable will be created in Auth0 and configured in Vault, Nomad, and Boundary (except "admin" user in Boundary).

---

### 6. Test KMIP Functionality (`6_kmip_test`)

Tests Vault KMIP secrets engine with a Nomad job.

**Dependencies:** Requires `1_create_clusters` to be deployed.

**What it creates:**
- Vault KMIP secrets engine mount
- KMIP scope and role
- KMIP credentials
- Nomad variables with KMIP credentials
- Nomad job to test KMIP

**Steps:**
```bash
cd 6_kmip_test

# Deploy
terraform init
terraform plan -var-file=variables.tfvars
terraform apply -auto-approve -var-file=variables.tfvars
```

**No environment variables required** - automatically reads Vault/Nomad configuration from `1_create_clusters` remote state.

---

## Remote State Architecture

All workspaces use Terraform local backend but read outputs from other workspaces via `terraform_remote_state` data sources. This eliminates the need for manual environment variable configuration.

### Remote State Flow
```
1_create_clusters/terraform.tfstate
    ├── Stores: Vault/Nomad URLs and AWS Secret names
    ├── Read by: All other workspaces
    └── Used for: Automatic credential retrieval from AWS Secrets Manager

AWS Secrets Manager
    ├── Vault root token (JSON with root_token field)
    └── Nomad bootstrap token (plaintext)
```

---

## Important Notes

### Credentials Management
- **Vault root token**: Stored in AWS Secrets Manager as JSON `{"root_token": "..."}`
- **Nomad bootstrap token**: Stored in AWS Secrets Manager as plaintext
- All workspaces automatically retrieve credentials via remote state

### Network Architecture
- Vault: HTTPS on port 8200 with ACME TLS certificates
- Nomad: HTTPS on port 4646 (ALB) / 4646 (direct) with ACME TLS certificate
- Boundary: HTTPS on port 9200 (controllers) with ACME TLS, 9201 for worker to controller, 9202 (workers)

### Boundary Worker Architecture
- **Ingress Worker**: Runs on AWS EC2, connects to controllers
- **Egress Workers**: Run as Nomad jobs, connect to ingress worker for multi-hop
- **Worker Tags**: Used for target filtering (type, location)

### Auth0 User Roles
- **admin**: Full permissions in Vault, Nomad, and Boundary
- **security**: Read-only access in Nomad and Boundary

### SSH Access
- EC2 instances use key-based SSH authentication
- Private key: `1_create_clusters/vault-private-key.pem`
- Connection commands available in terraform outputs

---

## Cleanup

To destroy all infrastructure, run in reverse order:

```bash
# 1. Destroy Auth0 configuration
cd 5_auth0
terraform destroy -var-file=variables.tfvars -auto-approve

# 2. Destroy KMIP test
cd ../6_kmip_test
terraform destroy

# 3. Destroy Nomad jobs and Boundary targets
cd ../4_nomad_jobs_boundary_targets
terraform destroy -var-file=variables.tfvars -auto-approve

# 4. Destroy Boundary initialization
cd ../3_boundary_deploy_aws/init_boundary
terraform destroy -var-file=variables.tfvars -auto-approve

# 5. Destroy Boundary infrastructure
cd ..
terraform destroy -var-file=variables.tfvars -auto-approve

# 6. Destroy workload identity
cd ../2_workload_identity
terraform destroy -var-file=variables.tfvars -auto-approve

# 7. Destroy core infrastructure
cd ../1_create_clusters
terraform destroy -var-file=variables.tfvars -auto-approve
```

## License

This project is for demonstration purposes.
