
# Detect install user (ec2-user, ubuntu, or current)
if id -u ec2-user >/dev/null 2>&1; then
  INSTALL_USER=ec2-user
elif id -u ubuntu >/dev/null 2>&1; then
  INSTALL_USER=ubuntu
else
  INSTALL_USER=$(logname 2>/dev/null || echo "$USER")
fi

# Create a dedicated 'docker' user for running or installing Docker if it doesn't exist
if ! id -u docker >/dev/null 2>&1; then
  echo "Creating system user 'docker'..."
  sudo useradd -m -s /bin/bash docker || true
fi
# Ensure the docker group exists (groupadd -f is not portable on all distros, so check first)
if ! getent group docker >/dev/null 2>&1; then
  sudo groupadd docker || true
fi

# Install Docker (Ubuntu)
# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

export ARCH_CNI=$( [ $(uname -m) = aarch64 ] && echo arm64 || echo amd64)
export CNI_PLUGIN_VERSION=v1.7.1
curl -L -o cni-plugins.tgz "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-linux-${ARCH_CNI}-${CNI_PLUGIN_VERSION}.tgz"
sudo mkdir -p /opt/cni/bin && \
sudo tar -C /opt/cni/bin -xzf cni-plugins.tgz

# Install QEMU and libvirt on Ubuntu
echo "Installing QEMU and libvirt (apt)..."
sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager genisoimage

# Enable and start libvirtd
sudo systemctl enable --now libvirtd || sudo systemctl enable --now libvirtd.service || true

# Verify QEMU installation
echo "QEMU version:"
qemu-system-x86_64 --version

# Create directories for TLS certificates
sudo mkdir -p /opt/nomad/tls
sudo chown root:root /opt/nomad/tls
sudo chmod 755 /opt/nomad/tls

# Set proper permissions
sudo chmod 0644 /opt/nomad/tls/nomad-agent-ca.pem
sudo chmod 0644 /opt/nomad/tls/dc1-client-nomad.pem
sudo chmod 0600 /opt/nomad/tls/dc1-client-nomad-key.pem



# Create directories
sudo mkdir -p /opt/nomad
sudo mkdir -p /opt/nomad/data
sudo mkdir -p /opt/nomad/tls
sudo mkdir -p /etc/nomad.d

# Download and install Nomad
echo "Downloading Nomad ${nomad_version}..."
cd /tmp
wget -q https://releases.hashicorp.com/nomad/1.10.5+ent/nomad_1.10.5+ent_linux_amd64.zip
unzip -q  nomad_1.10.5+ent_linux_amd64.zip 
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

region     = "dc1"
datacenter = "remote-site1"

client {
  enabled = true

  # Server address (use RPC port 4647 for TLS)
  servers = ["13.134.74.29:4647"]

  # Node class for targeting
  node_class = "ubuntu-linux-remote-site1-client"

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
      "-machine"
    ]
  }
}

# TLS configuration for client
tls {
  http = true
  rpc  = true

  ca_file   = "/opt/nomad/tls/nomad-agent-ca.pem"
  cert_file = "/opt/nomad/tls/dc1-client-nomad.pem"
  key_file  = "/opt/nomad/tls/dc1-client-nomad-key.pem"

  verify_server_hostname = false
  verify_https_client    = false
}

# ACL configuration for client
acl {
  enabled    = true
}
EOF


# Create systemd service for Nomad client


sudo echo "49152 65535" > /proc/sys/net/ipv4/ip_local_port_range

echo "Creating Nomad systemd service..."

sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-arptables
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables
sudo echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables

cat <<EOF | sudo tee /etc/sysctl.d/bridge.conf
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
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
cat <<PROFILE | sudo tee /etc/profile.d/nomad.sh
export NOMAD_ADDR="https://${nomad_server_address}:4646"
export NOMAD_CACERT="${USER_HOME}/nomad-agent-ca.pem"
export NOMAD_CLIENT_CERT="${USER_HOME}/${datacenter}-client-nomad.pem"
export NOMAD_CLIENT_KEY="${USER_HOME}/${datacenter}-client-nomad-key.pem"
PROFILE

# Replace placeholders in profile (if any remain)
sudo sed -i "s/\${nomad_server_address}/${nomad_server_address}/g" /etc/profile.d/nomad.sh || true
sudo sed -i "s/\${datacenter}/${datacenter}/g" /etc/profile.d/nomad.sh || true

echo "Nomad client installation completed successfully!"
echo "Client is connecting to server at: https://${nomad_server_address}:4646"