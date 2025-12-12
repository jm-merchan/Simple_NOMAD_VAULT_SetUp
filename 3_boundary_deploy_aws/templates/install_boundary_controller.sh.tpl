#!/usr/bin/env bash
set -e

# Get instance metadata
export instance_id=$(ec2-metadata --instance-id | cut -d " " -f 2)
export local_ipv4=$(ec2-metadata --local-ipv4 | cut -d " " -f 2)
export public_ipv4=$(ec2-metadata --public-ipv4 | cut -d " " -f 2)

echo "Starting Boundary Controller installation..."
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
sudo mkdir -p /opt/boundary/tls
sudo mkdir -p /etc/boundary.d
sudo mkdir -p /var/log/boundary

# Create audit log file
sudo touch /var/log/boundary/audit.log

# Set permissions
sudo chmod 0755 /opt/boundary
sudo chmod 0755 /opt/boundary/tls
sudo chown -R boundary:boundary /var/log/boundary
sudo chmod 0755 /var/log/boundary
sudo chmod 0644 /var/log/boundary/audit.log

# Retrieve TLS certificates from AWS Secrets Manager
echo "Retrieving TLS certificates from AWS Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id ${tls_secret_id} --region ${region} --query SecretString --output text)

echo "$SECRET_JSON" | jq -r '.boundary_cert' | base64 -d | sudo tee /opt/boundary/tls/boundary-cert.pem > /dev/null
echo "$SECRET_JSON" | jq -r '.boundary_key' | base64 -d | sudo tee /opt/boundary/tls/boundary-key.pem > /dev/null
echo "$SECRET_JSON" | jq -r '.boundary_ca' | base64 -d | sudo tee /opt/boundary/tls/boundary-ca.pem > /dev/null

# Set proper permissions for TLS files
sudo chown root:boundary /opt/boundary/tls/boundary-key.pem
sudo chmod 0640 /opt/boundary/tls/boundary-key.pem

# Save Boundary license
echo "${boundary_license}" | sudo tee /opt/boundary/boundary.hclic > /dev/null
sudo chown root:boundary /opt/boundary/boundary.hclic
sudo chmod 0640 /opt/boundary/boundary.hclic

# Create Boundary controller configuration with Vault Transit KMS
echo "Creating Boundary controller configuration..."
sudo cat > /etc/boundary.d/boundary.hcl <<EOF
disable_mlock = true

controller {
  name        = "boundary-controller-$instance_id"
  description = "Boundary Controller"
  
  database {
    url                  = "postgresql://${db_username}:${db_password}@${db_address}:5432/${db_name}?sslmode=require"
    max_open_connections = 5
  }
  
  public_cluster_addr = "${cluster_name}:9201"
  license             = "file:///opt/boundary/boundary.hclic"
}

# API listener
listener "tcp" {
  address       = "0.0.0.0:9200"
  purpose       = "api"
  tls_cert_file = "/opt/boundary/tls/boundary-cert.pem"
  tls_key_file  = "/opt/boundary/tls/boundary-key.pem"
}

# Cluster listener (for worker communication)
listener "tcp" {
  address = "0.0.0.0:9201"
  purpose = "cluster"
}

# Ops listener
listener "tcp" {
  address       = "0.0.0.0:9203"
  purpose       = "ops"
  tls_cert_file = "/opt/boundary/tls/boundary-cert.pem"
  tls_key_file  = "/opt/boundary/tls/boundary-key.pem"
}

# Vault Transit KMS - Root key
kms "transit" {
  purpose            = "root"
  address            = "${vault_addr}"
%{ if vault_namespace != "" ~}
  namespace          = "${vault_namespace}"
%{ endif ~}
  token              = "${vault_token}"
  disable_renewal    = "true"
  
  # Key configuration
  mount_path         = "${transit_mount_path}"
  key_name           = "${kms_key_root}"
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

# Vault Transit KMS - Recovery key
kms "transit" {
  purpose            = "recovery"
  address            = "${vault_addr}"
%{ if vault_namespace != "" ~}
  namespace          = "${vault_namespace}"
%{ endif ~}
  token              = "${vault_token}"
  disable_renewal    = "true"
  
  # Key configuration
  mount_path         = "${transit_mount_path}"
  key_name           = "${kms_key_recovery}"
}

# Vault Transit KMS - BSR (Session Recording) key
kms "transit" {
  purpose            = "bsr"
  address            = "${vault_addr}"
%{ if vault_namespace != "" ~}
  namespace          = "${vault_namespace}"
%{ endif ~}
  token              = "${vault_token}"
  disable_renewal    = "true"
  
  # Key configuration
  mount_path         = "${transit_mount_path}"
  key_name           = "${kms_key_bsr}"
}

# Events configuration
events {
  audit_enabled        = true
  observations_enabled = true
  sysevents_enabled    = true
  telemetry_enabled    = true
  
  sink "stderr" {
    name        = "all-events"
    description = "All events sent to stderr"
    event_types = ["*"]
    format      = "cloudevents-json"
  }
  
  sink {
    name        = "audit-sink"
    description = "Audit events to file"
    event_types = ["audit"]
    format      = "cloudevents-json"
    
    file {
      path      = "/var/log/boundary"
      file_name = "audit.log"
    }
    
    audit_config {
      audit_filter_overrides {
        secret    = "encrypt"
        sensitive = "hmac-sha256"
      }
    }
  }
}
EOF

# Set proper permissions for config
sudo chown root:boundary /etc/boundary.d/boundary.hcl
sudo chmod 0640 /etc/boundary.d/boundary.hcl

# Initialize Boundary database
echo "Initializing Boundary database..."
sudo -u boundary boundary database init -config /etc/boundary.d/boundary.hcl

# Enable and start Boundary service
echo "Starting Boundary service..."
sudo systemctl enable boundary
sudo systemctl start boundary

# Setup Boundary profile for easy CLI access
cat <<PROFILE | sudo tee /etc/profile.d/boundary.sh
export BOUNDARY_ADDR="https://127.0.0.1:9200"
export BOUNDARY_TLS_INSECURE="true"
PROFILE

# Create logrotate configuration
sudo cat > /etc/logrotate.d/boundary <<LOGROTATE
/var/log/boundary/audit.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGROTATE

echo "Boundary Controller installation complete!"
echo "API URL: https://${cluster_name}:9200"
echo "Cluster URL: ${cluster_name}:9201"
