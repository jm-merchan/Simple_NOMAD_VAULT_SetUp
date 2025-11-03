#!/usr/bin/env bash

# Update the system
sudo yum update -y

# Get AWS instance metadata
export instance_id="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
export local_ipv4="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"

# Set hostname
sudo hostnamectl set-hostname ${hostname}

# Install required packages
sudo yum install -y wget unzip jq logrotate

# Remove old AWS CLI if present
sudo yum remove -y awscli

# Install AWS CLI v2
echo "Installing AWS CLI v2..."
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update

# Create symlink for system-wide access
sudo ln -sf /usr/local/bin/aws /usr/bin/aws

# Verify AWS CLI installation
echo "AWS CLI version:"
/usr/local/bin/aws --version

# Update PATH for current session
export PATH="/usr/local/bin:$PATH"

# Verify AWS CLI is accessible
which aws
aws --version

# Clean up AWS CLI installation files
rm -rf awscliv2.zip aws/

# Download and install Vault Enterprise
echo "Downloading Vault Enterprise ${vault_version}"
cd /tmp

# Extract version number from the vault_version variable (e.g., "1.15.2+ent" -> "1.15.2")
VAULT_VERSION=$(echo "${vault_version}" | sed 's/+ent//')

# Download Vault Enterprise binary
wget -q "https://releases.hashicorp.com/vault/$${VAULT_VERSION}+ent/vault_$${VAULT_VERSION}+ent_linux_amd64.zip" -O vault_enterprise.zip

# Verify download was successful
if [ ! -f vault_enterprise.zip ]; then
    echo "Failed to download Vault Enterprise. Trying alternative URL..."
    wget -q "https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_linux_amd64.zip" -O vault_enterprise.zip
fi

# Unzip and install Vault Enterprise
sudo unzip -q vault_enterprise.zip
sudo mv vault /usr/local/bin/vault
sudo chmod +x /usr/local/bin/vault

# Create symlink for system-wide access
sudo ln -sf /usr/local/bin/vault /usr/bin/vault

# Verify installation
vault version

# Clean up
rm -f vault_enterprise.zip

echo "Vault Enterprise installation completed"

echo "Configuring system time"
sudo timedatectl set-timezone UTC

# Create vault user and group first
if ! getent group vault > /dev/null; then
    sudo groupadd vault
fi

if ! getent passwd vault > /dev/null; then
    sudo useradd -g vault -d /opt/vault -s /bin/false vault
fi

# Create vault directories and config directory
sudo mkdir -p /opt/vault/tls
sudo mkdir -p /opt/vault/data
sudo mkdir -p /opt/vault/logs
sudo mkdir -p /etc/vault.d

# removing any default installation files from /opt/vault/tls/
sudo rm -rf /opt/vault/tls/*

# /opt/vault/tls should be readable by all users of the system
sudo chmod 0755 /opt/vault/tls

# vault-key.pem should be readable by the vault group only
sudo touch /opt/vault/tls/vault-key.pem
sudo chown root:vault /opt/vault/tls/vault-key.pem
sudo chmod 0640 /opt/vault/tls/vault-key.pem

# Write TLS certificates and keys
# Get files from AWS Secrets Manager with retry logic
echo "Retrieving TLS certificates from AWS Secrets Manager..."

# Function to wait for and retrieve AWS Secrets Manager secrets with retry logic
wait_and_retrieve_secret() {
    local secret_id="$1"
    local jq_filter="$2"
    local output_file="$3"
    local description="$4"
    local max_attempts=30  # 15 minutes maximum (30 attempts x 30 seconds)
    local attempt=1
    local wait_time=30

    echo "Waiting for $description to be available..."
    echo "Secret ID: $secret_id"
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: Checking if $description exists..."
        
        # First check if the secret exists
        if aws secretsmanager describe-secret --secret-id "$secret_id" --region ${region} >/dev/null 2>&1; then
            echo "✅ Secret found: $description"
            
            # Try to retrieve the secret value
            if aws secretsmanager get-secret-value --secret-id "$secret_id" --region ${region} --output json 2>/dev/null | jq -r ".SecretString | fromjson | $jq_filter" > "$output_file" 2>/dev/null; then
                
                # Verify the file was created and is not empty
                if [ -s "$output_file" ]; then
                    echo "✅ Successfully retrieved $description"
                    return 0
                else
                    echo "⚠️  $description retrieved but file is empty"
                fi
            else
                echo "⚠️  $description exists but failed to retrieve content"
            fi
        else
            echo "⏳ $description not yet available..."
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo "❌ TIMEOUT: Failed to retrieve $description after $max_attempts attempts ($(($max_attempts * $wait_time / 60)) minutes)"
            return 1
        fi
        
        echo "⏳ Waiting $wait_time seconds before retry..."
        sleep $wait_time
        attempt=$((attempt + 1))
        
        # Increase wait time gradually (backoff strategy)
        if [ $attempt -gt 10 ]; then
            wait_time=60  # 1 minute after 10 attempts
        elif [ $attempt -gt 20 ]; then
            wait_time=120 # 2 minutes after 20 attempts
        fi
    done
    
    return 1
}

echo "=========================================="
echo "WAITING FOR CERTIFICATES TO BE READY"
echo "=========================================="
echo "This may take several minutes while Let's Encrypt generates certificates..."
echo "Certificate generation typically takes 2-5 minutes"
echo "Maximum wait time: 15 minutes"
echo ""

# Retrieve TLS certificate
wait_and_retrieve_secret "${certificate_secret_arn}" ".certificate" "/opt/vault/tls/vault-cert.pem" "TLS Certificate"
if [ $? -ne 0 ]; then
    echo "FATAL: Could not retrieve TLS certificate"
    exit 1
fi

# Retrieve private key
wait_and_retrieve_secret "${private_key_secret_arn}" ".private_key" "/opt/vault/tls/vault-key.pem" "TLS Private Key"
if [ $? -ne 0 ]; then
    echo "FATAL: Could not retrieve TLS private key"
    exit 1
fi

# Retrieve CA certificate
wait_and_retrieve_secret "${ca_certificate_secret_arn}" ".ca_certificate" "/opt/vault/tls/vault-ca.pem" "TLS CA Certificate"
if [ $? -ne 0 ]; then
    echo "FATAL: Could not retrieve TLS CA certificate"
    exit 1
fi

# Retrieve Vault license
wait_and_retrieve_secret "${license_key_secret_arn}" ".license" "/opt/vault/vault.hclic" "Vault Enterprise License"
if [ $? -ne 0 ]; then
    echo "FATAL: Could not retrieve Vault Enterprise license"
    exit 1
fi

echo ""
echo "=========================================="
echo "ALL CERTIFICATES RETRIEVED SUCCESSFULLY"
echo "=========================================="

# Add proper spacing and concatenate CA certificate
sudo printf "\n" >> /opt/vault/tls/vault-cert.pem
sudo cat /opt/vault/tls/vault-ca.pem >> /opt/vault/tls/vault-cert.pem

echo "TLS certificate chain created successfully"

# vault.hclic should be readable by the vault group only
sudo chown root:vault /opt/vault/vault.hclic
sudo chmod 0640 /opt/vault/vault.hclic

sudo cat << EOF > /etc/vault.d/vault.hcl
ui = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "$instance_id"
}

cluster_addr = "https://$local_ipv4:8201"
api_addr = "https://$local_ipv4:8200"

listener "tcp" {
  address                           = "0.0.0.0:8200"
  tls_disable                       = false
  tls_cert_file                     = "/opt/vault/tls/vault-cert.pem"
  tls_key_file                      = "/opt/vault/tls/vault-key.pem"
  tls_client_ca_file                = "/opt/vault/tls/vault-ca.pem"
  x_forwarded_for_authorized_addrs  = "0.0.0.0/0"
  tls_disable_client_certs          = true
  }

seal "awskms" {
  region     = "${region}"
  kms_key_id = "${kms_key_id}"
}

license_path = "/opt/vault/vault.hclic"

EOF

# vault.hcl should be readable by the vault group only
sudo chown root:root /etc/vault.d
sudo chown root:vault /etc/vault.d/vault.hcl
sudo chmod 640 /etc/vault.d/vault.hcl

# Set permissions for vault directories (user and group already created above)
sudo chown -R vault:vault /opt/vault/data
sudo chown -R vault:vault /opt/vault/logs
sudo chmod -R 750 /opt/vault/data
sudo chmod -R 750 /opt/vault/logs

# Create systemd service for Vault Enterprise
sudo cat << 'VAULTSERVICE' > /etc/systemd/system/vault.service
[Unit]
Description=HashiCorp Vault Enterprise
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
VAULTSERVICE

# Reload systemd and enable vault service
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

# Wait for Vault to start
sleep 10

# Check Vault status
sudo systemctl status vault

echo "Setup Vault profile"
cat <<PROFILE | sudo tee /etc/profile.d/vault.sh
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY="true"
PROFILE

# Create log rotate configuration
sudo cat << EOF > /etc/logrotate.d/vault
${vault_log_path} {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

EOF

# Add permissions to vault user to write logs
sudo touch /var/log/vault.log
sudo chown vault:vault /var/log/vault.log

# Create Vault secrets access verification script
cat > /home/ec2-user/verify-secrets-access.sh << 'SECRETSTEST'
#!/bin/bash
# Vault AWS Secrets Manager Access Verification Script
set -e

echo "=========================================="
echo "VAULT AWS SECRETS MANAGER ACCESS TEST"
echo "=========================================="

# Get region from instance metadata
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
echo "AWS Region: $REGION"

# Test the specific secrets used by this Vault deployment
SECRETS=("${certificate_secret_arn}" "${private_key_secret_arn}" "${ca_certificate_secret_arn}" "${license_key_secret_arn}")
SECRET_NAMES=("TLS Certificate" "TLS Private Key" "TLS CA Certificate" "Vault License")

echo ""
echo "Testing access to Vault secrets..."

SUCCESS=0
TOTAL=4

for i in $${!SECRETS[@]}; do
    secret_arn=$${SECRETS[i]}
    secret_name=$${SECRET_NAMES[i]}
    
    echo ""
    echo "Testing: $secret_name"
    echo "ARN: $secret_arn"
    
    if aws secretsmanager get-secret-value --secret-id "$secret_arn" --region "$REGION" >/dev/null 2>&1; then
        echo "✅ SUCCESS: Can access $secret_name"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "❌ FAILED: Cannot access $secret_name"
    fi
done

echo ""
echo "=========================================="
echo "Results: $SUCCESS/$TOTAL secrets accessible"
if [ $SUCCESS -eq $TOTAL ]; then
    echo "🎉 ALL SECRETS ACCESSIBLE!"
else
    echo "⚠️  Some secrets are not accessible"
fi
echo "=========================================="
SECRETSTEST

chmod +x /home/ec2-user/verify-secrets-access.sh
chown ec2-user:ec2-user /home/ec2-user/verify-secrets-access.sh

# Run the secrets verification test
echo "Running secrets access verification..."
/home/ec2-user/verify-secrets-access.sh

# Log completion
echo "Vault server user data script completed at $(date)" >> /var/log/user-data.log
echo "Vault server ${hostname} configured successfully" >> /var/log/user-data.log
echo "Secrets access verification completed" >> /var/log/user-data.log


# Create Vault initialization helper script
cat > /home/ec2-user/save-vault-init.sh << 'SAVEINIT'
#!/bin/bash
# Vault Initialization Keys Saver Script

INSTANCE_ID=${initSecret}
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY="true"

echo "=========================================="
echo "VAULT INITIALIZATION KEYS SAVER"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo ""

# Check if Vault is initialized
if vault status 2>/dev/null | grep -q "Initialized.*true"; then
    echo "⚠️  Vault is already initialized!"
    echo "Checking if keys are already saved..."
    
    if aws secretsmanager describe-secret --secret-id "$INSTANCE_ID" --region "$REGION" >/dev/null 2>&1; then
        echo "✅ Initialization keys are already saved in Secrets Manager"
        echo "Secret name: $INSTANCE_ID"
        exit 0
    else
        echo "❌ Vault is initialized but keys are not saved!"
        echo "Manual recovery may be needed."
        exit 1
    fi
fi

# Initialize Vault and save keys
echo "🚀 Initializing Vault..."
if ! vault operator init -format=json > /home/ec2-user/vault-init.json; then
    echo "❌ Failed to initialize Vault"
    exit 1
fi

echo "✅ Vault initialized successfully"

# Create secret with initialization keys
echo "💾 Saving initialization keys to AWS Secrets Manager..."
if aws secretsmanager create-secret \
    --name "$INSTANCE_ID" \
    --description "Vault initialization keys for instance $INSTANCE_ID" \
    --secret-string file:///home/ec2-user/vault-init.json \
    --region "$REGION" \
    --tags Key=VaultInstance,Value=$INSTANCE_ID Key=Purpose,Value=vault-init-keys Key=Environment,Value=${environment} >/dev/null; then
    
    echo "✅ Initialization keys saved successfully"
    echo "🔑 ROOT TOKEN (save this securely):"
    jq -r '.root_token' /home/ec2-user/vault-init.json
    echo ""
    echo "⚠️  IMPORTANT: The root token above is your only way to access Vault initially."
    echo ""
    echo "To retrieve keys later:"
    echo "aws secretsmanager get-secret-value --secret-id $INSTANCE_ID --region $REGION"
    
else
    echo "❌ Failed to save initialization keys to Secrets Manager"
    echo "Keys are saved locally in: /home/ec2-user/vault-init.json"
    echo "🔑 ROOT TOKEN:"
    jq -r '.root_token' /home/ec2-user/vault-init.json
    exit 1
fi

# Set secure permissions on local file
chmod 600 /home/ec2-user/vault-init.json

echo ""
echo "🎉 Vault initialization complete!"
echo "   Vault should automatically unseal using AWS KMS"
echo ""
SAVEINIT

chmod +x /home/ec2-user/save-vault-init.sh
chown ec2-user:ec2-user /home/ec2-user/save-vault-init.sh

# Optional: Auto-initialize if Vault is not initialized
echo "Auto-initializing Vault..."
/home/ec2-user/save-vault-init.sh
