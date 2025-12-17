#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/nomad-client-install.log)
exec 2>&1

echo "Starting Nomad client installation on Amazon Linux 2..."

# Update system packages
echo "Updating system packages..."
sudo yum update -y

# Install required packages
echo "Installing required packages..."
sudo yum install -y wget curl jq unzip

# Install AWS CLI v2 (if not already installed)
echo "Installing AWS CLI v2..."
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update

# Create symlink for system-wide access
sudo ln -sf /usr/local/bin/aws /usr/bin/aws

# Update PATH for current session
export PATH="/usr/local/bin:$PATH"

# Verify AWS CLI installation
echo "AWS CLI version:"
/usr/local/bin/aws --version

# Install Docker
echo "Installing Docker..."
sudo yum install -y docker

# Start and enable Docker service
sudo systemctl enable --now docker

# Add ec2-user to docker group
sudo usermod -aG docker ec2-user

# Download CNI plugins
echo "Downloading CNI plugins..."
export ARCH_CNI=$( [ $(uname -m) = aarch64 ] && echo arm64 || echo amd64)
curl -L -o cni-plugins.tgz "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-linux-$${ARCH_CNI}-${CNI_PLUGIN_VERSION}.tgz"
sudo mkdir -p /opt/cni/bin && \
sudo tar -C /opt/cni/bin -xzf cni-plugins.tgz

sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-arptables
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables

cat <<EOF | sudo tee /etc/sysctl.d/bridge.conf
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF



# Install QEMU for virtual machine support
echo "Installing QEMU for virtual machine workloads..."
sudo yum install -y qemu-kvm libvirt virt-manager

# Enable and start libvirtd service
sudo systemctl enable --now libvirtd

# Verify QEMU installation
echo "QEMU version:"
qemu-system-x86_64 --version

# Create directories for TLS certificates
sudo mkdir -p /opt/nomad/tls
sudo chown root:root /opt/nomad/tls
sudo chmod 755 /opt/nomad/tls

# Retrieve TLS certificates from AWS Secrets Manager
echo "Retrieving TLS certificates from AWS Secrets Manager..."
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Function to retrieve certificate from Secrets Manager
retrieve_cert() {
    local secret_name="$1"
    local output_file="$2"
    local description="$3"
    
    for i in {1..30}; do
        if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$REGION" >/dev/null 2>&1; then
            aws secretsmanager get-secret-value --secret-id "$secret_name" --region "$REGION" --query 'SecretString' --output text > "$output_file" 2>/dev/null
            if [ -s "$output_file" ]; then
                echo "✅ Retrieved $description"
                return 0
            fi
        fi
        echo "Waiting for $description... ($i/30)"
        sleep 5
    done
    echo "❌ Failed to retrieve $description"
    return 1
}

# Retrieve certificates
retrieve_cert "nomad-ca-${initSecret}" "/opt/nomad/tls/nomad-agent-ca.pem" "CA certificate"
retrieve_cert "nomad-client-cert-${initSecret}" "/opt/nomad/tls/${datacenter}-client-nomad.pem" "client certificate"  
retrieve_cert "nomad-client-key-${initSecret}" "/opt/nomad/tls/${datacenter}-client-nomad-key.pem" "client private key"

# Set proper permissions
sudo chmod 0644 /opt/nomad/tls/nomad-agent-ca.pem
sudo chmod 0644 /opt/nomad/tls/${datacenter}-client-nomad.pem
sudo chmod 0600 /opt/nomad/tls/${datacenter}-client-nomad-key.pem

# Copy certificates to ec2-user home for CLI access
sudo cp /opt/nomad/tls/nomad-agent-ca.pem /opt/nomad/tls/${datacenter}-client-nomad* /home/ec2-user/
sudo chown ec2-user:ec2-user /home/ec2-user/nomad-agent-ca.pem /home/ec2-user/${datacenter}-client-nomad*

echo "✅ TLS certificates configured"

# Create directories
sudo mkdir -p /opt/nomad
sudo mkdir -p /opt/nomad/data
sudo mkdir -p /opt/nomad/tls
sudo mkdir -p /etc/nomad.d

# Download and install Nomad
echo "Downloading Nomad ${nomad_version}..."
cd /tmp
wget -q https://releases.hashicorp.com/nomad/${nomad_version}/nomad_${nomad_version}_linux_amd64.zip
unzip -q nomad_${nomad_version}_linux_amd64.zip
sudo mv nomad /usr/local/bin/
sudo chmod +x /usr/local/bin/nomad

# Verify Nomad installation
echo "Nomad version:"
nomad version

# Create Nomad client configuration
echo "Creating Nomad client configuration..."
cat <<EOF | sudo tee /etc/nomad.d/client.hcl
# Data directory for Nomad client
data_dir = "/opt/nomad/data"

region     = "${datacenter}"
datacenter = "${datacenter}"

client {
  enabled = true

  # Server address (use RPC port 4647 for TLS)
  servers = ["${nomad_server_address}:4647"]

  # Node class for targeting
  node_class = "amazon-linux-client"

  # Node meta for placement constraints (ensures jobs requiring vault.version will match)
  meta {
    "vault.version" = "0.6.1"
  }

  options {
    "driver.raw_exec.enable" = "1"
    "driver.docker.enable"   = "1"
    "driver.qemu.enable"     = "1"
    "driver.podman.enable"   = "0"  # Disable Podman, use Docker
  }
}

plugin "docker" {
  config {
    allow_privileged = true
    volumes {
      enabled = true
    }
    gc {
      image = true
      container = true
    }
  }
}

plugin "qemu" {
  config {
    image_paths = ["/opt/nomad/qemu"]
    args_allowlist = [
      "-device",
      "-drive",
      "-netdev",
      "-cdrom",
      "-boot",
      "-m",
      "-smp",
      "-enable-kvm",
      "-cpu",
      "-machine",
      "-display",
      "-net"
    ]
  }
}

# TLS configuration for client
tls {
  http = true
  rpc  = true

  ca_file   = "/opt/nomad/tls/nomad-agent-ca.pem"
  cert_file = "/opt/nomad/tls/${datacenter}-client-nomad.pem"
  key_file  = "/opt/nomad/tls/${datacenter}-client-nomad-key.pem"

  verify_server_hostname = true
  verify_https_client    = false
}

# ACL configuration for client
acl {
  enabled    = true
}

vault {
  enabled          = true
  address          = "https://${vault_address}:8200"
  default_identity {
    aud = ["vault.io"]
    ttl = "1h"
  }
}

EOF

# Create systemd service for Nomad client
echo "Creating Nomad systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/nomad.service
[Unit]
Description=Nomad Client
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

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Nomad service
echo "Starting Nomad client service..."
sudo systemctl daemon-reload
sudo systemctl enable nomad
sudo systemctl start nomad

# Wait for service to start
sleep 10

# Check Nomad status
echo "Checking Nomad client status..."
nomad node status

# Set up Nomad environment variables for TLS
echo "Setting up Nomad environment for TLS..."
cat <<'PROFILE' | sudo tee /etc/profile.d/nomad.sh
export NOMAD_ADDR="https://${nomad_server_address}:4646"
export NOMAD_CACERT="/home/ec2-user/nomad-agent-ca.pem"
export NOMAD_CLIENT_CERT="/home/ec2-user/${datacenter}-client-nomad.pem"
export NOMAD_CLIENT_KEY="/home/ec2-user/${datacenter}-client-nomad-key.pem"
PROFILE

# Replace placeholders in profile
sudo sed -i "s/\${nomad_server_address}/${nomad_server_address}/g" /etc/profile.d/nomad.sh
sudo sed -i "s/\${datacenter}/${datacenter}/g" /etc/profile.d/nomad.sh

echo "Nomad client installation completed successfully!"
echo "Client is connecting to server at: https://${nomad_server_address}:4646"