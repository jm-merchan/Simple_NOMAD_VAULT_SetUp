
# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "vault_kms_policy_attachment" {
  role       = aws_iam_role.vault_role.name
  policy_arn = aws_iam_policy.vault_kms_policy.arn
}

# Instance profile for EC2 instances (following HashiCorp best practices)
resource "aws_iam_instance_profile" "vault_profile" {
  name = "vault-instance-profile-${random_string.random_name.result}"
  role = aws_iam_role.vault_role.name

  tags = {
    Name        = "vault-instance-profile-${random_string.random_name.result}"
    Environment = var.environment
    Purpose     = "vault-enterprise-instance-profile"
    Owner       = "vault-infrastructure"
    Application = "vault-enterprise"
    Terraform   = "true"
  }

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# IAM policy for Vault Secrets Manager access (following HashiCorp best practices)
resource "aws_iam_policy" "vault_secrets_policy" {
  name        = "VaultSecretsManagerPolicy-${random_string.random_name.result}"
  description = "IAM policy for HashiCorp Vault Enterprise to access AWS Secrets Manager for TLS certificates and license"
  path        = "/vault/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultTLSCertificateAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = [
          aws_secretsmanager_secret.vault_tls_certificate.arn,
          aws_secretsmanager_secret.vault_tls_private_key.arn,
          aws_secretsmanager_secret.vault_tls_ca_certificate.arn
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "VaultLicenseAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = aws_secretsmanager_secret.vault_license.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "NomadLicenseAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = aws_secretsmanager_secret.nomad_license.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })

  tags = {
    Name        = "VaultSecretsManagerPolicy-${random_string.random_name.result}"
    Environment = var.environment
    Purpose     = "vault-enterprise-secrets-access"
    Owner       = "vault-infrastructure"
    Application = "vault-enterprise"
    Terraform   = "true"
  }
}

# Attach the Secrets Manager policy to the role
resource "aws_iam_role_policy_attachment" "vault_secrets_policy_attachment" {
  role       = aws_iam_role.vault_role.name
  policy_arn = aws_iam_policy.vault_secrets_policy.arn
}

# IAM policy for Vault to manage its own initialization secrets
resource "aws_iam_policy" "vault_init_secrets_policy" {
  name        = "VaultInitSecretsManagementPolicy-${random_string.random_name.result}"
  description = "IAM policy for HashiCorp Vault Enterprise to create and manage initialization secrets"
  path        = "/vault/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultCreateInitSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:*:secret:initSecret-*",
          "arn:aws:secretsmanager:${var.region}:*:secret:nomad-acl-*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "VaultManageInitSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:*:secret:initSecret-*",
          "arn:aws:secretsmanager:${var.region}:*:secret:nomad-acl-*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "VaultListSecretsForInit"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })

  tags = {
    Name        = "VaultInitSecretsManagementPolicy-${random_string.random_name.result}"
    Environment = var.environment
    Purpose     = "vault-enterprise-init-secrets"
    Owner       = "vault-infrastructure"
    Application = "vault-enterprise"
    Terraform   = "true"
  }
}

# Attach the initialization secrets policy to the role
resource "aws_iam_role_policy_attachment" "vault_init_secrets_policy_attachment" {
  role       = aws_iam_role.vault_role.name
  policy_arn = aws_iam_policy.vault_init_secrets_policy.arn
}

# IAM policy for Vault to write benchmark results to SSM Parameter Store
resource "aws_iam_policy" "vault_ssm_policy" {
  name        = "VaultSSMParameterStorePolicy-${random_string.random_name.result}"
  description = "IAM policy for HashiCorp Vault Enterprise to write benchmark results to SSM Parameter Store"
  path        = "/vault/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultSSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DeleteParameter",
          "ssm:DescribeParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/benchmark-result-*",
          "arn:aws:ssm:${var.region}:*:parameter/vault-*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "VaultSSMParameterList"
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })

  tags = {
    Name        = "VaultSSMParameterStorePolicy-${random_string.random_name.result}"
    Environment = var.environment
    Purpose     = "vault-enterprise-ssm-access"
    Owner       = "vault-infrastructure"
    Application = "vault-enterprise"
    Terraform   = "true"
  }
}

# Attach the SSM Parameter Store policy to the role
resource "aws_iam_role_policy_attachment" "vault_ssm_policy_attachment" {
  role       = aws_iam_role.vault_role.name
  policy_arn = aws_iam_policy.vault_ssm_policy.arn
}