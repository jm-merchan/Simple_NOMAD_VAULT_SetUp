#!/bin/bash
# Helper script to prepare Boundary deployment

set -e

echo "======================================"
echo "Boundary AWS Deployment Helper"
echo "======================================"
echo ""

# Check if running from correct directory
if [ ! -f "terraform.tf" ]; then
    echo "Error: Please run this script from the 5_boundary_deploy_aws directory"
    exit 1
fi

# Check if 1_create_clusters exists
if [ ! -d "../1_create_clusters" ]; then
    echo "Error: ../1_create_clusters directory not found"
    echo "Please deploy the infrastructure first"
    exit 1
fi

# Get values from 1_create_clusters
echo "🔍 Retrieving configuration from 1_create_clusters..."
cd ../1_create_clusters

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "Error: terraform.tfstate not found in 1_create_clusters"
    echo "Please deploy 1_create_clusters first"
    exit 1
fi

# Extract values from terraform outputs
VAULT_ADDR=$(terraform output -json service_urls 2>/dev/null | jq -r '.vault_server.fqdn_url' || echo "")

if [ -z "$VAULT_ADDR" ]; then
    echo "Error: Could not retrieve Vault address from terraform output"
    exit 1
fi

# Extract values from terraform.tfvars if it exists
if [ -f "terraform.tfvars" ]; then
    REGION=$(grep '^region' terraform.tfvars | awk -F'"' '{print $2}' || echo "eu-west-2")
    DNS_ZONE=$(grep '^dns_zone_name_ext' terraform.tfvars | awk -F'"' '{print $2}' || echo "")
    OWNER_EMAIL=$(grep '^owner_email' terraform.tfvars | awk -F'"' '{print $2}' || echo "")
else
    echo "Warning: terraform.tfvars not found, using defaults"
    REGION="eu-west-2"
    DNS_ZONE=""
    OWNER_EMAIL=""
fi

# Get the actual key pair name from Terraform state (it's dynamically generated)
KEY_PAIR_NAME=$(terraform state show 'aws_key_pair.vault_key_pair' 2>/dev/null | grep 'key_name' | awk '{print $3}' | tr -d '"' || echo "")

echo "✅ Found infrastructure:"
echo "   Vault Address: $VAULT_ADDR"
echo "   Key Pair: $KEY_PAIR_NAME"
echo "   Region: $REGION"
echo "   DNS Zone: $DNS_ZONE"
echo "   Owner Email: $OWNER_EMAIL"
echo ""

# Get Vault token
echo "🔑 Retrieving Vault root token..."
SECRET_NAME=$(terraform output -raw retrieve_vault_token 2>/dev/null | grep -o 'initSecret-[a-z0-9]*' || echo "")

if [ -z "$SECRET_NAME" ]; then
    echo "Error: Could not determine secret name"
    exit 1
fi

VAULT_TOKEN=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query SecretString --output text 2>/dev/null | jq -r .root_token || echo "")

if [ -z "$VAULT_TOKEN" ]; then
    echo "⚠️  Could not automatically retrieve Vault token"
    echo "   Please retrieve it manually:"
    echo "   aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $REGION --query SecretString --output text | jq -r .root_token"
    echo ""
    read -p "Enter Vault root token: " VAULT_TOKEN
fi

echo "✅ Vault token retrieved"
echo ""

# Go back to boundary directory
cd ../5_boundary_deploy_aws

# Check if terraform.tfvars exists
if [ -f "terraform.tfvars" ]; then
    echo "⚠️  terraform.tfvars already exists"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping terraform.tfvars creation"
        exit 0
    fi
fi

# Create terraform.tfvars
echo "📝 Creating terraform.tfvars..."
cat > terraform.tfvars <<EOF
# Auto-generated configuration
# Generated on: $(date)

# AWS Region
region = "$REGION"

# SSH Key (from 1_create_clusters)
key_pair_name = "$KEY_PAIR_NAME"

# DNS Configuration
dns_zone_name = "$DNS_ZONE"
owner_email   = "$OWNER_EMAIL"

# Boundary Configuration
boundary_version = "0.18.1+ent"
boundary_license = ""  # ⚠️  ADD YOUR LICENSE HERE
cluster_name     = "boundary"

# Database Configuration
db_username = "boundary"
db_password = "ChangeThisSecurePassword123!"  # ⚠️  CHANGE THIS!

# Vault Configuration (from 1_create_clusters)
vault_addr      = "$VAULT_ADDR"
vault_token     = "$VAULT_TOKEN"
vault_namespace = ""

# ACME/Let's Encrypt
acme_prod = false  # Set to true for production certificates

# Instance Types
controller_instance_type = "t3.medium"
worker_instance_type     = "t3.medium"

# Additional Tags
tags = {
  Terraform   = "true"
  Environment = "demo"
  Project     = "boundary"
  Owner       = "team-platform"
}
EOF

echo "✅ terraform.tfvars created"
echo ""
echo "======================================"
echo "⚠️  IMPORTANT: Update terraform.tfvars"
echo "======================================"
echo ""
echo "Please edit terraform.tfvars and update:"
echo "  1. boundary_license - Your Boundary Enterprise license"
echo "  2. db_password - A secure database password"
echo ""
echo "Then run:"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo ""
