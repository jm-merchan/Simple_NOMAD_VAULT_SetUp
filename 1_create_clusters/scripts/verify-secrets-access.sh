#!/bin/bash

# Vault AWS Secrets Manager Access Verification Script
# This script verifies that the Vault instance can access all required AWS Secrets Manager secrets

set -e

echo "=========================================="
echo "VAULT AWS SECRETS MANAGER ACCESS TEST"
echo "=========================================="

# Get region from instance metadata
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
echo "AWS Region: $REGION"

# Get instance ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: $INSTANCE_ID"

# Test IAM role
echo ""
echo "Testing IAM Role..."
aws sts get-caller-identity

echo ""
echo "=========================================="
echo "TESTING SECRETS MANAGER ACCESS"
echo "=========================================="

# Function to test secret access
test_secret_access() {
    local secret_name=$1
    local description=$2
    
    echo ""
    echo "Testing: $description"
    echo "Secret: $secret_name"
    
    # Test DescribeSecret
    if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$REGION" >/dev/null 2>&1; then
        echo "✅ DescribeSecret: SUCCESS"
    else
        echo "❌ DescribeSecret: FAILED"
        return 1
    fi
    
    # Test GetSecretValue
    if aws secretsmanager get-secret-value --secret-id "$secret_name" --region "$REGION" --query 'SecretString' --output text >/dev/null 2>&1; then
        echo "✅ GetSecretValue: SUCCESS"
    else
        echo "❌ GetSecretValue: FAILED"
        return 1
    fi
    
    # Test ListSecretVersionIds
    if aws secretsmanager list-secret-version-ids --secret-id "$secret_name" --region "$REGION" >/dev/null 2>&1; then
        echo "✅ ListSecretVersionIds: SUCCESS"
    else
        echo "❌ ListSecretVersionIds: FAILED"
        return 1
    fi
    
    echo "✅ All tests passed for: $description"
}

# Get all vault-related secrets
echo ""
echo "Discovering Vault secrets..."
VAULT_SECRETS=$(aws secretsmanager list-secrets --region "$REGION" --query 'SecretList[?contains(Name, `vault-`)].Name' --output text)

if [ -z "$VAULT_SECRETS" ]; then
    echo "❌ No vault secrets found!"
    exit 1
fi

echo "Found secrets:"
for secret in $VAULT_SECRETS; do
    echo "  - $secret"
done

# Test each secret
SUCCESS_COUNT=0
TOTAL_COUNT=0

for secret in $VAULT_SECRETS; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    
    case $secret in
        *tls-certificate*)
            if test_secret_access "$secret" "TLS Certificate"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
            ;;
        *tls-private-key*)
            if test_secret_access "$secret" "TLS Private Key"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
            ;;
        *tls-ca-certificate*)
            if test_secret_access "$secret" "TLS CA Certificate"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
            ;;
        *enterprise-license*)
            if test_secret_access "$secret" "Vault Enterprise License"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
            ;;
        *)
            echo ""
            echo "Testing: Unknown Secret Type"
            if test_secret_access "$secret" "Unknown Secret"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
            ;;
    esac
done

echo ""
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo "Total secrets tested: $TOTAL_COUNT"
echo "Successful tests: $SUCCESS_COUNT"
echo "Failed tests: $((TOTAL_COUNT - SUCCESS_COUNT))"

if [ $SUCCESS_COUNT -eq $TOTAL_COUNT ]; then
    echo "🎉 ALL TESTS PASSED!"
    echo "✅ Vault has proper access to AWS Secrets Manager"
    exit 0
else
    echo "❌ SOME TESTS FAILED!"
    echo "⚠️  Check IAM policies and secret permissions"
    exit 1
fi