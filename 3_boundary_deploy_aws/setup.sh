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
# Disable terraform color output to avoid ANSI codes
export TF_CLI_ARGS="-no-color"
KEY_PAIR_NAME=$(terraform state show 'aws_key_pair.vault_key_pair' 2>/dev/null | grep -E '^\s+key_name\s+=' | awk '{print $3}' | tr -d '"' | sed 's/\x1b\[[0-9;]*m//g' || echo "")
unset TF_CLI_ARGS

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
cd ../3_boundary_deploy_aws

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

# Get db_password from existing terraform.tfvars or generate a random one
if [ -f "terraform.tfvars" ]; then
    DB_PASSWORD=$(grep '^db_password' terraform.tfvars | awk -F'"' '{print $2}' || echo "")
fi

if [ -z "$DB_PASSWORD" ]; then
    # Generate a random password
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)
    echo "ℹ️  Generated random database password"
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
boundary_version = "0.21.0+ent"
boundary_license = "02MV4UU43BK5HGYYTOJZWFQMTMNNEWU33JJVVECMCNNVITGWSXJV2E4VCWNBHFGMBRJZWUS6CMK5FGUTKHJV2FS6SFGRGUOSJQLJCGY3KZK5ITISLJO5UVSM2WPJSEOOLULJMEUZTBK5IWST3JJJVU6V2FGJNEIZDMJ5BTC3CPKRITGTCXKZUE6VCJORNFOTLXJZ4TANCNNVGTET2UIF4E22THPJMXURLJJRBUU4DCNZHDAWKXPBZVSWCSOBRDENLGMFLVC2KPNFEXCSLJO5UWCWCOPJSFOVTGMRDWY5C2KNETMSLKJF3U22SVORGVISLUJVKFMVKNIRVTMTL2IE3E2VDLOVHGUZZQJVKGG6SOIRITIV3JJFZUS3SOGBMVQSRQLAZVE4DCK5KWST3JJF4U2RCJGFGFIRLZJRKEKMKWIRAXOT3KIF3U62SBO5LWSSLTJFWVMNDDI5WHSWKYKJYGEMRVMZSEO3DULJJUSNSJNJEXOTLKLF2E2VCJORGVIUSVJVCECNSNIRATMTKEIJQUS2LXNFSEOVTZMJLWY5KZLBJHAYRSGVTGIR3MORNFGSJWJFVES52NNJMXITKUJF2E2VCSKVGUIQJWJVCECNSNIRBGCSLJO5UWGSCKOZNEQVTKMRBUSNSJNVFHMZCXGVVVSWCKGVEWS53JLJWXQ2C2GNGWST3OONUVUV2SOBSEO3DWMJUUSNSJNVLHKZCHKZ4WGSCKOBRTEVLJJRBUU6TBGNLHUSLKOBRES3SOGBMVONLLLFMEU22MLBMXQSLJO5UWGR3YGFRXSMJSJVJUUZDGLAYD2LTGNJLFGQLVGBCDA43NIRIGQYSSOJGW2M3LG5WTI3LJOFEDOVBZJIZGWY2KI5LFE4JLKVFXIOKKNNHTSNSUMRWTOSLIGZ3GW6KVMNBW2TSKM5UHQSKCI5HUESLPIR4EQ2LKKVGU4QZVGFSEC23DME2GIVRQGMZTQUDXNVLGYYLWJJIDI4CKPBEUSOKEGZKUMTCVMFLFA2TLK5FHIY2EGZYGC3BWN5HWMR3OJMZHUUCLJJJG2R2IKYZWKWTXOFDGKK3PG5VS64ZLIFKE42CQLJTVGL2LKZMWOL2LFNWEOUDXJQ3WUQTYJE3UOT3BNM3FKYLJMFEG6ZLLGBJFI3ZXGJCFCPJ5"  # ⚠️  ADD YOUR LICENSE HERE
cluster_name     = "boundary"

# Database Configuration
db_username = "boundary"
db_password = "$DB_PASSWORD"

# Vault Configuration (from 1_create_clusters)
vault_addr      = "$VAULT_ADDR"
vault_token     = "$VAULT_TOKEN"
vault_namespace = ""

# ACME/Let's Encrypt
acme_prod = true  # Set to true for production certificates

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
echo "Database password: $DB_PASSWORD"
echo ""
echo "Please edit terraform.tfvars and update:"
echo "  1. boundary_license - Your Boundary Enterprise license"
echo ""
echo "Then run:"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo ""
