#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/nomad-install.log)
exec 2>&1

echo "Starting Nomad single node installation..."

# Update the system
yum update -y
yum install -y htop curl wget git jq unzip

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

# Install Podman (Amazon Linux 2 requires extras repository)
echo "Installing Podman..."
# Enable Amazon Linux Extras repository for container tools
amazon-linux-extras install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user
echo "Docker installed successfully"

# Configure bridge networking for Nomad
echo "Configuring bridge networking and iptables..."

# Load bridge module (required for newer Linux versions like Ubuntu 24.04)
modprobe bridge

# Ensure bridge module loads on boot
echo "bridge" >> /etc/modules-load.d/bridge.conf

# Configure iptables to process bridge network traffic
# This is required for Nomad's task group networks and Consul service mesh integration
echo 1 > /proc/sys/net/bridge/bridge-nf-call-arptables
echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables

# Make bridge networking settings persistent across reboots
cat <<EOF > /etc/sysctl.d/bridge.conf
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/bridge.conf

echo "Bridge networking configured successfully"

# Set Nomad version
NOMAD_VERSION="${nomad_version}"

# Download Nomad Enterprise
cd /tmp
echo "Downloading Nomad Enterprise version $NOMAD_VERSION..."

# Extract version number if it contains +ent suffix
NOMAD_BASE_VERSION=$(echo "$NOMAD_VERSION" | sed 's/+ent//')

# Download Nomad Enterprise binary
curl --silent --remote-name https://releases.hashicorp.com/nomad/$${NOMAD_BASE_VERSION}+ent/nomad_$${NOMAD_BASE_VERSION}+ent_linux_amd64.zip || \
curl --silent --remote-name https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip

# Install Nomad Enterprise
echo "Installing Nomad Enterprise..."
unzip -o nomad_*_linux_amd64.zip
sudo chown root:root nomad
sudo mv nomad /usr/local/bin/
sudo chmod +x /usr/local/bin/nomad

# Create symlink for system-wide access
sudo ln -sf /usr/local/bin/nomad /usr/bin/nomad

# Verify installation
nomad version

# Enable command autocompletion
nomad -autocomplete-install
complete -C /usr/local/bin/nomad nomad

echo "Nomad Enterprise installation completed"

# Create Nomad user and directories
echo "Creating Nomad user and directories..."
if ! getent group nomad > /dev/null; then
    sudo groupadd nomad
fi

if ! getent passwd nomad > /dev/null; then
    sudo useradd --system --home /etc/nomad.d --shell /bin/false -g nomad nomad
fi

sudo mkdir -p /opt/nomad/data /opt/nomad/tls /etc/nomad.d
sudo chmod 700 /etc/nomad.d
sudo chown -R nomad:nomad /opt/nomad /etc/nomad.d

# Retrieve Nomad Enterprise license from AWS Secrets Manager
echo "Retrieving Nomad Enterprise license from AWS Secrets Manager..."
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Function to wait for and retrieve secret
wait_and_retrieve_secret() {
    local secret_id="$1"
    local jq_filter="$2"
    local output_file="$3"
    local description="$4"
    local max_attempts=30
    local attempt=1
    local wait_time=10

    echo "Waiting for $description to be available..."
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: Checking if $description exists..."
        
        if aws secretsmanager describe-secret --secret-id "$secret_id" --region "$REGION" >/dev/null 2>&1; then
            if aws secretsmanager get-secret-value --secret-id "$secret_id" --region "$REGION" --output json 2>/dev/null | jq -r ".SecretString | fromjson | $jq_filter" > "$output_file" 2>/dev/null; then
                if [ -s "$output_file" ]; then
                    echo "✅ Retrieved $description"
                    return 0
                fi
            fi
        fi
        echo "⏳ Waiting for $description..."
        
        if [ $attempt -eq $max_attempts ]; then
            echo "❌ Failed to retrieve $description"
            return 1
        fi
        sleep $wait_time
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Retrieve Nomad license
wait_and_retrieve_secret "${nomad_license_secret_arn}" ".license" "/opt/nomad/nomad.hclic" "Nomad Enterprise License"
if [ $? -ne 0 ]; then
    echo "FATAL: Could not retrieve Nomad Enterprise license"
    exit 1
fi

# Set proper permissions for license file
sudo chown root:nomad /opt/nomad/nomad.hclic
sudo chmod 0640 /opt/nomad/nomad.hclic

echo "Nomad Enterprise license retrieved successfully"

# Generate TLS certificates for Nomad
echo "Generating TLS certificates..."
cd /opt/nomad/tls

nomad tls ca create
nomad tls cert create -server -region ${datacenter}
nomad tls cert create -client -region ${datacenter}
nomad tls cert create -cli -region ${datacenter}

# Set permissions
sudo chown -R root:nomad /opt/nomad/tls
sudo chmod 0640 /opt/nomad/tls/*-key.pem
sudo chmod 0644 /opt/nomad/tls/*.pem

# Copy CLI certificates to ec2-user home
sudo cp /opt/nomad/tls/nomad-agent-ca.pem /opt/nomad/tls/${datacenter}-cli-nomad* /home/ec2-user/
sudo chown ec2-user:ec2-user /home/ec2-user/nomad-agent-ca.pem /home/ec2-user/${datacenter}-cli-nomad*
echo "✅ TLS certificates generated"

# Create Nomad systemd service
# Note: Running as root because client mode requires privileged operations
echo "Creating Nomad systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/nomad.service
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/docs/
Wants=network-online.target
After=network-online.target

[Service]

User=root
Group=root
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
KillMode=process
KillSignal=SIGINT
LimitNOFILE=65536
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
StartLimitBurst=5
StartLimitIntervalSec=10s
TasksMax=infinity
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF

# Create Nomad common configuration
echo "Creating Nomad configuration files..."
cat <<EOF | sudo tee /etc/nomad.d/nomad.hcl
region        = "${datacenter}"
datacenter    = "${datacenter}"
data_dir      = "/opt/nomad"
bind_addr     = "0.0.0.0"

# TLS configuration
tls {
  http = true
  rpc  = true

  ca_file   = "/opt/nomad/tls/nomad-agent-ca.pem"
  cert_file = "/opt/nomad/tls/${datacenter}-server-nomad.pem"
  key_file  = "/opt/nomad/tls/${datacenter}-server-nomad-key.pem"

  verify_server_hostname = true
  verify_https_client    = false
}

# ACL configuration
acl {
  enabled = true
}

vault {
  enabled          = true
  address          = "https://${vault_address}:8200"
  default_identity {
    aud = ["vault.io"]
    ttl = "1h"
  }
}

# Disable Consul integration
consul {
  auto_advertise = false
}
EOF

# Create Nomad server configuration for single node
cat <<EOF | sudo tee /etc/nomad.d/server.hcl
server {
  enabled = true
  bootstrap_expect = 1
  license_path = "/opt/nomad/nomad.hclic"
}
EOF

# Create Nomad client configuration
cat <<EOF | sudo tee /etc/nomad.d/client.hcl
client {
  enabled = true
  options {
    "driver.raw_exec.enable" = "1"
    "driver.docker.enable"   = "1"
  }
}

plugin "docker" {
  config {
    allow_privileged = true
    volumes { enabled = true }
    gc {
      image     = true
      container = true
    }
  }
}
EOF

# Set proper permissions
sudo chown -R nomad:nomad /etc/nomad.d

# Enable and start Nomad
echo "Starting Nomad service..."
sudo systemctl daemon-reload
sudo systemctl enable nomad
sudo systemctl start nomad

# Wait for Nomad to start
sleep 10

# Set up Nomad environment variables for TLS
echo "Setting up Nomad environment for TLS..."
cat <<'PROFILE' | sudo tee /etc/profile.d/nomad.sh
export NOMAD_ADDR="https://127.0.0.1:4646"
export NOMAD_CACERT="/home/ec2-user/nomad-agent-ca.pem"
export NOMAD_CLIENT_CERT="/home/ec2-user/${datacenter}-cli-nomad.pem"
export NOMAD_CLIENT_KEY="/home/ec2-user/${datacenter}-cli-nomad-key.pem"
PROFILE

# Replace datacenter placeholder in profile
sudo sed -i "s/\${datacenter}/${datacenter}/g" /etc/profile.d/nomad.sh

echo "✅ Nomad installation completed!"

# Create Nomad ACL bootstrap helper script
cat > /home/ec2-user/bootstrap-nomad-acl.sh <<NOMADACL
#!/bin/bash
# Nomad ACL Bootstrap Script

INSTANCE_ID="nomad-acl-${initSecret}"
REGION=\$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
export NOMAD_ADDR="https://127.0.0.1:4646"
export NOMAD_CACERT="/home/ec2-user/nomad-agent-ca.pem"
export NOMAD_CLIENT_CERT="/home/ec2-user/${datacenter}-cli-nomad.pem"
export NOMAD_CLIENT_KEY="/home/ec2-user/${datacenter}-cli-nomad-key.pem"

echo "=========================================="
echo "NOMAD ACL BOOTSTRAP"
echo "=========================================="
echo "Instance ID: \$INSTANCE_ID"
echo "Region: \$REGION"
echo ""

# Wait for Nomad to be ready
sleep 10
nomad acl bootstrap -json | jq -r .SecretID > /tmp/nomad-acl.token

BOOTSTRAP_TOKEN=\$(cat /tmp/nomad-acl.token)
chmod 600 /tmp/nomad-acl.token

# Save to AWS Secrets Manager
aws secretsmanager create-secret \
    --name "\$INSTANCE_ID" \
    --description "Nomad ACL bootstrap token" \
    --secret-string file:///tmp/nomad-acl.token \
    --region "\$REGION" \
    --tags Key=NomadInstance,Value=\$INSTANCE_ID Key=Environment,Value=${environment} >/dev/null

echo "✅ ACL bootstrap complete"
echo "Token: \$BOOTSTRAP_TOKEN"
NOMADACL

chmod +x /home/ec2-user/bootstrap-nomad-acl.sh
chown ec2-user:ec2-user /home/ec2-user/bootstrap-nomad-acl.sh

# Auto-bootstrap ACLs
echo "Auto-bootstrapping Nomad ACLs..."
/home/ec2-user/bootstrap-nomad-acl.sh

echo "Nomad setup complete!"

