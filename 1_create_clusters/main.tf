
provider "aws" {
  region = var.region
}

# Generate a private key
resource "tls_private_key" "vault_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create the key pair in AWS
resource "aws_key_pair" "vault_key_pair" {
  key_name   = "vault-key-${random_string.random_name.result}"
  public_key = tls_private_key.vault_key.public_key_openssh

  tags = {
    Name        = "vault-key-${random_string.random_name.result}"
    Environment = var.vault_server.environment
    Purpose     = "vault-ssh-access"
  }
}

# Save the private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.vault_key.private_key_pem
  filename        = "${path.module}/vault-private-key.pem"
  file_permission = "0600"

  provisioner "local-exec" {
    command = "chmod 600 ${path.module}/vault-private-key.pem"
  }
}

# Data source to get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Create first public subnet
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-az1"
  }
}

# Alias for backward compatibility
locals {
  public_subnet_id = aws_subnet.main.id
}

# Create a second subnet in a different AZ for ALB
resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-az2"
  }
}

# Create a route table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "main-route-table"
  }
}

# Associate the route table with the subnet
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Associate the route table with the second subnet
resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.main.id
}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name_prefix = "ec2-security-group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Vault API (HTTPS)"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Vault Cluster Communication"
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Nomad HTTP API"
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Nomad RPC"
    from_port   = 4647
    to_port     = 4647
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Vault KMIP"
    from_port   = 5696
    to_port     = 5696
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-security-group"
  }
}

# Local values for template variables
locals {
  vault_server_user_data = templatefile("${path.module}/templates/vault_server.sh.tpl", {
    hostname                  = var.vault_server.name
    environment               = var.vault_server.environment
    certificate_secret_arn    = aws_secretsmanager_secret.vault_tls_certificate.arn
    private_key_secret_arn    = aws_secretsmanager_secret.vault_tls_private_key.arn
    ca_certificate_secret_arn = aws_secretsmanager_secret.vault_tls_ca_certificate.arn
    pk_certifate_secret_arn   = aws_secretsmanager_secret.vault_tls_private_key.arn
    license_key_secret_arn    = aws_secretsmanager_secret.vault_license.arn
    vault_version             = var.vault_server.vault_version
    region                    = var.region
    kms_key_id                = aws_kms_key.vault_key.key_id
    vault_log_path            = var.vault_log_path
    initSecret                = "initSecret-${random_string.random_name.result}"
  })

  nomad_server_user_data = templatefile("${path.module}/templates/nomad_server.sh.tpl", {
    hostname                 = var.nomad_server.name
    environment              = var.nomad_server.environment
    region                   = var.region
    nomad_version            = var.nomad_server.nomad_version
    datacenter               = var.nomad_server.datacenter
    nomad_license_secret_arn = aws_secretsmanager_secret.nomad_license.arn
    vault_address            = aws_route53_record.vault.fqdn
    initSecret               = "initSecret-${random_string.random_name.result}"
  })
}

# Vault Server EC2 Instance
resource "aws_instance" "vault_server" {
  depends_on             = [aws_secretsmanager_secret.vault_tls_certificate]
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.vault_server.instance_type
  key_name               = aws_key_pair.vault_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.main.id
  iam_instance_profile   = aws_iam_instance_profile.vault_profile.name

  # Use vault server template for user data
  user_data = local.vault_server_user_data

  # Root block device configuration
  root_block_device {
    volume_type = "gp3"
    volume_size = var.vault_server.volume_size
    encrypted   = true
  }

  tags = merge(
    {
      Name         = var.vault_server.name
      Environment  = var.vault_server.environment
      Application  = var.vault_server.application
      ServerType   = "VaultServer"
      VaultCluster = "vault-cluster-${random_string.random_name.result}"
    },
    var.vault_server.additional_tags
  )
}

# Vault Benchmark EC2 Instance
resource "aws_instance" "nomad_server" {
  depends_on             = [aws_instance.vault_server]
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.nomad_server.instance_type
  key_name               = aws_key_pair.vault_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.main.id
  iam_instance_profile   = aws_iam_instance_profile.vault_profile.name

  # Use vault benchmark template for user data
  user_data = local.nomad_server_user_data

  # Root block device configuration
  root_block_device {
    volume_type = "gp3"
    volume_size = var.nomad_server.volume_size
    encrypted   = true
  }

  tags = merge(
    {
      Name        = var.nomad_server.name
      Environment = var.nomad_server.environment
      Application = var.nomad_server.application
      ServerType  = "NomadServer"
    },
    var.nomad_server.additional_tags
  )
}

# Elastic IP for vault server
resource "aws_eip" "vault_server_eip" {
  instance = aws_instance.vault_server.id
  domain   = "vpc"

  tags = {
    Name = "${var.vault_server.name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# Elastic IP for vault benchmark server
resource "aws_eip" "nomad_server_eip" {
  instance = aws_instance.nomad_server.id
  domain   = "vpc"

  tags = {
    Name = "${var.nomad_server.name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}