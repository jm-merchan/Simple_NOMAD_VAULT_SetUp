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

# Get Vault root token from environment or terraform output
echo "Retrieving Vault root token..."
if [ -n "$VAULT_TOKEN" ]; then
    echo "Using VAULT_TOKEN from environment"
else
    echo "Retrieving from 1_create_clusters terraform output..."
    WORKSPACE_ROOT="$(cd "$PARENT_DIR/.." && pwd)"
    CLUSTERS_DIR="$WORKSPACE_ROOT/1_create_clusters"
    
    if [ -d "$CLUSTERS_DIR" ]; then
        TOKEN_COMMAND=$(cd "$CLUSTERS_DIR" && terraform output -raw retrieve_vault_token 2>/dev/null)
        if [ -n "$TOKEN_COMMAND" ]; then
            VAULT_TOKEN=$(eval "$TOKEN_COMMAND")
        else
            echo "ERROR: Could not retrieve vault token command from terraform output"
            exit 1
        fi
    else
        echo "ERROR: Could not find 1_create_clusters directory at $CLUSTERS_DIR"
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
