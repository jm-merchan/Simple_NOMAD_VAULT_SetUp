#!/usr/bin/env bash
set -e

# Get instance metadata
export instance_id=$(ec2-metadata --instance-id | cut -d " " -f 2)
export local_ipv4=$(ec2-metadata --local-ipv4 | cut -d " " -f 2)
export public_ipv4=$(ec2-metadata --public-ipv4 | cut -d " " -f 2)

echo "Starting Boundary Worker installation..."
echo "Instance ID: $instance_id"
echo "Private IP: $local_ipv4"
echo "Public IP: $public_ipv4"

# Install dependencies
sudo yum update -y
sudo yum install -y jq wget unzip

# Install Boundary Enterprise
echo "Installing Boundary Enterprise version ${boundary_version}..."
wget -O- https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo | sudo tee /etc/yum.repos.d/hashicorp.repo
sudo yum install -y boundary-enterprise-${boundary_version}

# Configure system time
sudo timedatectl set-timezone UTC

# Create Boundary directories
sudo mkdir -p /opt/boundary
sudo mkdir -p /etc/boundary.d
sudo mkdir -p /var/log/boundary

# Set permissions
sudo chmod 0755 /opt/boundary
sudo chmod 0755 /var/log/boundary

# Create Boundary worker configuration with Vault Transit KMS
echo "Creating Boundary worker configuration..."
sudo cat > /etc/boundary.d/boundary.hcl <<EOF
disable_mlock = true

worker {
  name        = "boundary-worker-$instance_id"
  description = "Boundary Worker"
  
  # Initial upstream controllers for worker to connect
  initial_upstreams = [
    "${controller_address}"
  ]
  
  public_addr = "$public_ipv4"
  
  # Worker tags for filtering
  tags = {
    location = ["eu-west-2"]
    type     = ["worker"]
  }
}

# Listener for incoming connections from clients
listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

# Vault Transit KMS - Worker-Auth key
kms "transit" {
  purpose            = "worker-auth"
  address            = "${vault_addr}"
%{ if vault_namespace != "" ~}
  namespace          = "${vault_namespace}"
%{ endif ~}
  token              = "${vault_token}"
  disable_renewal    = "true"
  
  # Key configuration
  mount_path         = "${transit_mount_path}"
  key_name           = "${kms_key_worker}"
}

# Events configuration
events {
  observations_enabled = true
  sysevents_enabled    = true
  
  sink "stderr" {
    name        = "all-events"
    description = "All events sent to stderr"
    event_types = ["*"]
    format      = "cloudevents-json"
  }
}
EOF

# Set proper permissions for config
sudo chown root:boundary /etc/boundary.d/boundary.hcl
sudo chmod 0640 /etc/boundary.d/boundary.hcl

# Enable and start Boundary service
echo "Starting Boundary service..."
sudo systemctl enable boundary
sudo systemctl start boundary

# Setup Boundary profile for easy CLI access
cat <<PROFILE | sudo tee /etc/profile.d/boundary.sh
export BOUNDARY_ADDR="https://${controller_address}:9200"
PROFILE

echo "Boundary Worker installation complete!"
echo "Worker will connect to controller at: ${controller_address}:9201"
echo "Worker proxy listening on: $local_ipv4:9202"
echo "Worker public address: $public_ipv4:9202"
