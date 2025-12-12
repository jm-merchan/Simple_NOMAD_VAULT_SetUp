#!/bin/bash
set -e

echo "Generating variables.tfvars from parent deployment..."

# Get the parent directory
PARENT_DIR="$(cd .. && pwd)"

# Extract values from parent terraform
cd "$PARENT_DIR"

BOUNDARY_ADDR="$(terraform output -raw boundary_url 2>/dev/null || echo 'boundary.jose-merchan.sbx.hashidemos.io:9200')"
VAULT_ADDR=$(grep vault_addr terraform.tfvars | cut -d'"' -f2)
REGION=$(grep region terraform.tfvars | grep -v '#' | head -1 | cut -d'"' -f2)

# Get Vault root token from environment or AWS Secrets Manager
echo "Retrieving Vault root token..."
if [ -n "$VAULT_TOKEN" ]; then
    echo "Using VAULT_TOKEN from environment"
else
    echo "Retrieving from AWS Secrets Manager..."
    VAULT_SECRET_ID=$(aws secretsmanager list-secrets --region "$REGION" --query "SecretList[?contains(Name, 'vault') && contains(Name, 'token')].Name" --output text | head -1)
    if [ -n "$VAULT_SECRET_ID" ]; then
        VAULT_TOKEN=$(aws secretsmanager get-secret-value --secret-id "$VAULT_SECRET_ID" --region "$REGION" --query SecretString --output text | jq -r '.root_token // .token // .')
    else
        echo "ERROR: Could not find Vault token in environment or AWS Secrets Manager"
        exit 1
    fi
fi

cd init_boundary

# Create variables.tfvars
cat > variables.tfvars <<EOF
# Boundary Controller
boundary_addr = "$BOUNDARY_ADDR"

# Vault Configuration
vault_addr          = "$VAULT_ADDR"
vault_token         = "$VAULT_TOKEN"
transit_mount_path  = "transit"
kms_key_recovery    = "boundary-recovery"

# Admin User
boundary_user     = "admin"
boundary_password = "ChangeMe123!"
EOF

echo "✓ variables.tfvars created"
echo ""
echo "Please edit variables.tfvars and set a secure password for boundary_password"
echo "Then run:"
echo "  terraform init"
echo "  terraform apply"
