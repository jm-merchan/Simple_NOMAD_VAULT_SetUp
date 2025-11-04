# KMS Key for Vault Auto-Unseal
resource "aws_kms_key" "vault_key" {
  description             = "KMS key for Vault auto-unseal in ${var.region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "vault-kms-key-${random_string.random_name.result}"
    Environment = var.vault_server.environment
    Purpose     = "vault-auto-unseal"
    Owner       = "vault-infrastructure"
  }
}

# KMS Key Alias for easier reference
resource "aws_kms_alias" "vault_key_alias" {
  name          = "alias/vault-key-${random_string.random_name.result}"
  target_key_id = aws_kms_key.vault_key.key_id
}

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# IAM policy for Vault to use KMS
data "aws_iam_policy_document" "vault_kms_policy" {
  # Allow the account root and current user to manage the key
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
        data.aws_caller_identity.current.arn
      ]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow Vault role to use the key
  statement {
    sid    = "VaultKMSAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.vault_role.arn]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant"
    ]

    resources = ["*"]
  }

  # Allow Vault instances to use KMS directly
  statement {
    sid    = "VaultInstanceKMSAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.vault_role.arn]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.${var.region}.amazonaws.com"]
    }
  }
}

# Apply the policy to the KMS key
resource "aws_kms_key_policy" "vault_key_policy" {
  key_id = aws_kms_key.vault_key.id
  policy = data.aws_iam_policy_document.vault_kms_policy.json
}

# IAM role for Vault instances (following HashiCorp best practices)
resource "aws_iam_role" "vault_role" {
  name               = "vault-role-${random_string.random_name.result}"
  assume_role_policy = templatefile("${path.module}/templates/vault-server-role.json.tpl", {})

  # Maximum session duration for assume role (12 hours)
  max_session_duration = 43200

  # Prevent deletion if policies are attached
  force_detach_policies = false

  tags = {
    Name        = "vault-role-${random_string.random_name.result}"
    Environment = var.environment
    Purpose     = "vault-enterprise-server"
    Owner       = "vault-infrastructure"
    Application = "vault-enterprise"
    Terraform   = "true"
  }
}

# IAM policy for Vault KMS access (following HashiCorp best practices)
resource "aws_iam_policy" "vault_kms_policy" {
  name        = "VaultKMSAutoUnsealPolicy-${random_string.random_name.result}"
  description = "IAM policy for HashiCorp Vault Enterprise to access AWS KMS for auto-unseal functionality"
  path        = "/vault/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultKMSUnsealAccess"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.vault_key.arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ec2.${var.region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "VaultKMSGrantManagement"
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = aws_kms_key.vault_key.arn
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
      {
        Sid    = "VaultKMSKeyInformation"
        Effect = "Allow"
        Action = [
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListAliases"
        ]
        Resource = "*"
      },
      {
        Sid    = "VaultEC2InstanceMetadata"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Region" = var.region
          }
        }
      }
    ]
  })

  tags = {
    Name        = "VaultKMSAutoUnsealPolicy-${random_string.random_name.result}"
    Environment = var.environment
    Purpose     = "vault-enterprise-kms-autounseal"
    Owner       = "vault-infrastructure"
    Application = "vault-enterprise"
    Terraform   = "true"
  }
}
