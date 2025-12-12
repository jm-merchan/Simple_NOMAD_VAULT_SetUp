# Data sources to get VPC and subnet information from 1_create_clusters
data "aws_vpc" "main" {
  id = var.vpc_id != "" ? var.vpc_id : data.aws_vpcs.default.ids[0]
}

data "aws_vpcs" "default" {
  filter {
    name   = "tag:Name"
    values = ["main-vpc"]
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create dedicated subnets for Boundary
resource "aws_subnet" "boundary_az1" {
  vpc_id                  = data.aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 10)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "boundary-subnet-az1"
  }
}

resource "aws_subnet" "boundary_az2" {
  vpc_id                  = data.aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 11)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "boundary-subnet-az2"
  }
}

# Create Internet Gateway for Boundary
resource "aws_internet_gateway" "boundary" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name = "boundary-igw"
  }
}

# Create route table for Boundary subnets
resource "aws_route_table" "boundary" {
  vpc_id = data.aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.boundary.id
  }

  tags = {
    Name = "boundary-route-table"
  }
}

# Route table associations for Boundary subnets
resource "aws_route_table_association" "boundary_az1" {
  subnet_id      = aws_subnet.boundary_az1.id
  route_table_id = aws_route_table.boundary.id
}

resource "aws_route_table_association" "boundary_az2" {
  subnet_id      = aws_subnet.boundary_az2.id
  route_table_id = aws_route_table.boundary.id
}

# Vault Transit Engine setup for Boundary KMS
resource "vault_mount" "transit" {
  path        = "transit"
  type        = "transit"
  description = "Transit engine for Boundary encryption"
}

# Create transit keys for Boundary
resource "vault_transit_secret_backend_key" "boundary_root" {
  backend = vault_mount.transit.path
  name    = "boundary-root"

  deletion_allowed = true
  exportable       = false
  type             = "aes256-gcm96"
}

resource "vault_transit_secret_backend_key" "boundary_worker_auth" {
  backend = vault_mount.transit.path
  name    = "boundary-worker-auth"

  deletion_allowed = true
  exportable       = false
  type             = "aes256-gcm96"
}

resource "vault_transit_secret_backend_key" "boundary_recovery" {
  backend = vault_mount.transit.path
  name    = "boundary-recovery"

  deletion_allowed = true
  exportable       = false
  type             = "aes256-gcm96"
}

resource "vault_transit_secret_backend_key" "boundary_bsr" {
  backend = vault_mount.transit.path
  name    = "boundary-bsr"

  deletion_allowed = true
  exportable       = false
  type             = "aes256-gcm96"
}

# Create Vault policy for Boundary Controller (needs all keys)
resource "vault_policy" "boundary_controller" {
  name = "boundary-controller-transit-policy"

  policy = <<EOT
# Allow Boundary Controller to use all transit encryption keys
path "${vault_mount.transit.path}/encrypt/${vault_transit_secret_backend_key.boundary_root.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/decrypt/${vault_transit_secret_backend_key.boundary_root.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/encrypt/${vault_transit_secret_backend_key.boundary_worker_auth.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/decrypt/${vault_transit_secret_backend_key.boundary_worker_auth.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/encrypt/${vault_transit_secret_backend_key.boundary_recovery.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/decrypt/${vault_transit_secret_backend_key.boundary_recovery.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/encrypt/${vault_transit_secret_backend_key.boundary_bsr.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/decrypt/${vault_transit_secret_backend_key.boundary_bsr.name}" {
  capabilities = ["update"]
}
EOT
}

# Create Vault policy for Boundary Worker (only needs worker-auth key)
resource "vault_policy" "boundary_worker" {
  name = "boundary-worker-transit-policy"

  policy = <<EOT
# Allow Boundary Worker to use worker-auth key only
path "${vault_mount.transit.path}/encrypt/${vault_transit_secret_backend_key.boundary_worker_auth.name}" {
  capabilities = ["update"]
}

path "${vault_mount.transit.path}/decrypt/${vault_transit_secret_backend_key.boundary_worker_auth.name}" {
  capabilities = ["update"]
}
EOT
}

# Create a static token for Boundary Controller with full access
resource "vault_token" "boundary_controller" {
  policies = [vault_policy.boundary_controller.name]

  no_parent        = true
  renewable        = false
  ttl              = "0"    # No expiration
  explicit_max_ttl = "0"    # No maximum TTL

  metadata = {
    purpose = "boundary-controller-kms"
  }
}

# Create a static token for Boundary Worker with limited access
resource "vault_token" "boundary_worker" {
  policies = [vault_policy.boundary_worker.name]

  no_parent        = true
  renewable        = false
  ttl              = "0"    # No expiration
  explicit_max_ttl = "0"    # No maximum TTL

  metadata = {
    purpose = "boundary-worker-kms"
  }
}

# ACME account for Let's Encrypt
resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "boundary" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.owner_email
}

# Generate TLS certificate for Boundary
resource "tls_private_key" "boundary" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "boundary" {
  private_key_pem = tls_private_key.boundary.private_key_pem

  subject {
    common_name  = "${var.cluster_name}.${var.dns_zone_name}"
    organization = "HashiCorp Boundary"
  }

  dns_names = [
    "${var.cluster_name}.${var.dns_zone_name}",
  ]
}

# Get Route53 zone
data "aws_route53_zone" "main" {
  name         = var.dns_zone_name
  private_zone = false
}

resource "acme_certificate" "boundary" {
  account_key_pem         = acme_registration.boundary.account_key_pem
  certificate_request_pem = tls_cert_request.boundary.cert_request_pem
  min_days_remaining      = 30

  dns_challenge {
    provider = "route53"
  }
}

# Deploy Boundary Controller
module "boundary_controller" {
  source = "./modules/boundary-controller"

  vpc_id        = data.aws_vpc.main.id
  vpc_cidr      = var.vpc_cidr
  subnet_ids    = [aws_subnet.boundary_az1.id, aws_subnet.boundary_az2.id]
  region        = var.region
  key_pair_name = var.key_pair_name

  instance_type    = var.controller_instance_type
  boundary_version = var.boundary_version
  boundary_license = var.boundary_license

  cluster_name  = var.cluster_name
  dns_zone_name = var.dns_zone_name

  db_username = var.db_username
  db_password = var.db_password

  # TLS configuration
  tls_cert_pem = base64encode(acme_certificate.boundary.certificate_pem)
  tls_key_pem  = base64encode(tls_private_key.boundary.private_key_pem)
  tls_ca_pem   = base64encode(acme_certificate.boundary.issuer_pem)

  # Vault Transit configuration
  vault_addr         = var.vault_addr
  vault_namespace    = var.vault_namespace
  vault_token        = vault_token.boundary_controller.client_token
  transit_mount_path = vault_mount.transit.path
  kms_key_root       = vault_transit_secret_backend_key.boundary_root.name
  kms_key_worker     = vault_transit_secret_backend_key.boundary_worker_auth.name
  kms_key_recovery   = vault_transit_secret_backend_key.boundary_recovery.name
  kms_key_bsr        = vault_transit_secret_backend_key.boundary_bsr.name

  tags = var.tags
}

# Deploy Boundary Worker
module "boundary_worker" {
  source = "./modules/boundary-worker"

  vpc_id        = data.aws_vpc.main.id
  subnet_id     = aws_subnet.boundary_az1.id
  key_pair_name = var.key_pair_name

  instance_type    = var.worker_instance_type
  boundary_version = var.boundary_version

  controller_address = module.boundary_controller.cluster_url

  # Vault Transit configuration
  vault_addr         = var.vault_addr
  vault_namespace    = var.vault_namespace
  vault_token        = vault_token.boundary_worker.client_token
  transit_mount_path = vault_mount.transit.path
  kms_key_worker     = vault_transit_secret_backend_key.boundary_worker_auth.name

  worker_tags = {
    type     = "worker"
    location = var.region
  }

  tags = var.tags

  depends_on = [module.boundary_controller]
}

# Create Route53 DNS record for Boundary
resource "aws_route53_record" "boundary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.cluster_name}.${var.dns_zone_name}"
  type    = "A"
  ttl     = 300
  records = [module.boundary_controller.controller_public_ip]
}
