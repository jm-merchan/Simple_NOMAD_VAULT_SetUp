# Boundary Worker Module for AWS

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
resource "random_string" "worker" {
  length  = 4
  special = false
  lower   = true
  upper   = false
}

# Security group for Boundary worker
resource "aws_security_group" "boundary_worker" {
  name_prefix = "boundary-worker-sg-"
  description = "Security group for Boundary worker"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Worker proxy port (for client connections)
  ingress {
    description = "Boundary worker proxy"
    from_port   = 9202
    to_port     = 9202
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "boundary-worker-sg"
  }
}

# IAM role for Boundary worker
resource "aws_iam_role" "boundary_worker" {
  name = "boundary-worker-role-${random_string.worker.result}"

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
    Name = "boundary-worker-role"
  }
}

# IAM instance profile
resource "aws_iam_instance_profile" "boundary_worker" {
  name = "boundary-worker-profile-${random_string.worker.result}"
  role = aws_iam_role.boundary_worker.name
}

# User data template for Boundary worker
locals {
  boundary_user_data = templatefile("${path.module}/../../templates/install_boundary_worker.sh.tpl", {
    boundary_version       = var.boundary_version
    controller_address     = var.controller_address
    vault_addr             = var.vault_addr
    vault_namespace        = var.vault_namespace
    vault_token            = var.vault_token
    transit_mount_path     = var.transit_mount_path
    kms_key_worker         = var.kms_key_worker
    worker_tags            = jsonencode(var.worker_tags)
  })
}

# EC2 instance for Boundary worker
resource "aws_instance" "boundary_worker" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.boundary_worker.id]
  iam_instance_profile        = aws_iam_instance_profile.boundary_worker.name
  associate_public_ip_address = true

  user_data = local.boundary_user_data

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
      Name        = "boundary-worker-${random_string.worker.result}"
      Application = "boundary"
      Role        = "worker"
    },
    var.tags
  )
}
