# Boundary Controller Module for AWS

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

# Random string for unique naming
resource "random_string" "boundary" {
  length  = 4
  special = false
  lower   = true
  upper   = false
}

# RDS PostgreSQL database for Boundary
resource "aws_db_subnet_group" "boundary" {
  name       = "boundary-db-subnet-${random_string.boundary.result}"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "Boundary DB subnet group"
  }
}

resource "aws_db_instance" "boundary" {
  identifier             = "boundary-db-${random_string.boundary.result}"
  engine                 = "postgres"
  engine_version         = "17.7"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.boundary.name
  vpc_security_group_ids = [aws_security_group.boundary_db.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  tags = {
    Name = "boundary-postgres-${random_string.boundary.result}"
  }
}

# Security group for RDS
resource "aws_security_group" "boundary_db" {
  name_prefix = "boundary-db-sg-"
  description = "Security group for Boundary PostgreSQL database"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from Boundary controller"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.boundary_controller.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "boundary-db-sg"
  }
}

# Security group for Boundary controller
resource "aws_security_group" "boundary_controller" {
  name_prefix = "boundary-controller-sg-"
  description = "Security group for Boundary controller"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Boundary API
  ingress {
    description = "Boundary API"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Boundary cluster port (for workers)
  ingress {
    description = "Boundary cluster communication from VPC"
    from_port   = 9201
    to_port     = 9201
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Boundary ops/health
  ingress {
    description = "Boundary ops"
    from_port   = 9203
    to_port     = 9203
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
    Name = "boundary-controller-sg"
  }
}

# IAM role for Boundary controller
resource "aws_iam_role" "boundary_controller" {
  name = "boundary-controller-role-${random_string.boundary.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "boundary-controller-role"
  }
}

# IAM policy for Secrets Manager access (for TLS certs)
resource "aws_iam_role_policy" "boundary_secrets" {
  name = "boundary-secrets-policy"
  role = aws_iam_role.boundary_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.boundary_tls.arn
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "boundary_controller" {
  name = "boundary-controller-profile-${random_string.boundary.result}"
  role = aws_iam_role.boundary_controller.name
}

# TLS certificates storage in Secrets Manager
resource "aws_secretsmanager_secret" "boundary_tls" {
  name_prefix             = "boundary-tls-${random_string.boundary.result}-"
  description             = "TLS certificates for Boundary"
  recovery_window_in_days = 0

  tags = {
    Name = "boundary-tls-certs"
  }
}

resource "aws_secretsmanager_secret_version" "boundary_tls" {
  secret_id = aws_secretsmanager_secret.boundary_tls.id
  secret_string = jsonencode({
    boundary_cert = var.tls_cert_pem
    boundary_key  = var.tls_key_pem
    boundary_ca   = var.tls_ca_pem
  })
}

# EC2 instance for Boundary controller
resource "aws_instance" "boundary_controller" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.boundary_controller.id]
  iam_instance_profile        = aws_iam_instance_profile.boundary_controller.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/../../templates/install_boundary_controller.sh.tpl", {
    boundary_version       = var.boundary_version
    boundary_license       = var.boundary_license
    db_username            = var.db_username
    db_password            = var.db_password
    db_name                = var.db_name
    db_address             = aws_db_instance.boundary.address
    vault_addr             = var.vault_addr
    vault_namespace        = var.vault_namespace
    vault_token            = var.vault_token
    transit_mount_path     = var.transit_mount_path
    kms_key_root           = var.kms_key_root
    kms_key_worker         = var.kms_key_worker
    kms_key_recovery       = var.kms_key_recovery
    kms_key_bsr            = var.kms_key_bsr
    cluster_name           = "${var.cluster_name}.${var.dns_zone_name}"
    tls_secret_id          = aws_secretsmanager_secret.boundary_tls.name
    region                 = var.region
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = var.disk_size
    encrypted   = true
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  tags = merge(
    {
      Name        = "boundary-controller-${random_string.boundary.result}"
      Application = "boundary"
      Role        = "controller"
    },
    var.tags
  )

  depends_on = [
    aws_db_instance.boundary,
    aws_secretsmanager_secret_version.boundary_tls
  ]
}
