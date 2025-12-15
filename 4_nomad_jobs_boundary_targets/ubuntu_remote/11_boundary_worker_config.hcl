job "boundary-egress-worker" {
  datacenters = ["remote-site1"]
  type        = "service"

  group "boundary-worker" {
    count = 1

    # Restart policy for the worker
    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    task "install-boundary" {
      driver = "raw_exec"
      
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        command = "/bin/bash"
        args = ["-c", <<'EOF'
          # Check if Boundary is already installed
          if command -v boundary &> /dev/null; then
            INSTALLED_VERSION=$(boundary version | head -n 1 | awk '{print $2}' | sed 's/v//')
            echo "Boundary $INSTALLED_VERSION is already installed"
            exit 0
          fi

          echo "Installing Boundary Enterprise..."
          
          # Add HashiCorp GPG key and repository
          wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
          
          # Update and install Boundary
          sudo apt-get update
          sudo apt-get install -y boundary-enterprise=${boundary_version}-1
          
          # Verify installation
          boundary version
          
          echo "Boundary installation completed!"
        EOF
        ]
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }

    task "boundary-worker" {
      driver = "raw_exec"

      # Read configuration from Nomad Variables
      template {
        data = <<EOT
{{ with nomadVar "nomad/jobs/boundary-egress-worker" }}
VAULT_TOKEN="{{ .vault_token }}"
TRANSIT_MOUNT_PATH="{{ .transit_mount_path }}"
KMS_KEY_WORKER="{{ .kms_key_worker }}"
{{ end }}
VAULT_ADDR="${VAULT_ADDR}"
INGRESS_WORKER_ADDR="${INGRESS_WORKER_ADDR}"
EOT
        destination = "local/boundary.env"
        env         = true
      }

      # Create Boundary worker configuration
      template {
        data = <<EOT
disable_mlock = true

worker {
  name        = "egress-worker-{{ env "NOMAD_ALLOC_ID" }}"
  description = "Boundary Egress Worker on ubuntu_remote"
  
  # Connect to the ingress worker (EC2 cloud worker)
  initial_upstreams = [
    "${ingress_worker_addr}"
  ]
  
  # This worker will be used as an egress worker for multi-hop
  tags {
    type     = ["egress", "ubuntu-remote"]
    location = ["remote-site1"]
  }
}

# Listener for downstream workers (if needed in the future)
listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

# Vault Transit KMS for worker-auth
kms "transit" {
  purpose            = "worker-auth"
  address            = "{{ env "VAULT_ADDR" }}"
  token              = "{{ env "VAULT_TOKEN" }}"
  disable_renewal    = "true"
  
  # Key configuration
  mount_path         = "{{ env "TRANSIT_MOUNT_PATH" }}"
  key_name           = "{{ env "KMS_KEY_WORKER" }}"
}

# Events configuration
events {
  audit_enabled        = true
  observations_enabled = true
  sysevents_enabled    = true
  
  sink "stderr" {
    name        = "all-events"
    description = "All events sent to stderr"
    event_types = ["*"]
    format      = "cloudevents-json"
  }
}
EOT
        destination = "local/boundary.hcl"
      }

      config {
        command = "boundary"
        args = [
          "server",
          "-config", "local/boundary.hcl"
        ]
      }

      resources {
        cpu    = 1000
        memory = 512
        
        network {
          port "proxy" {
            static = 9202
          }
        }
      }

      # Health check
      service {
        name = "boundary-egress-worker"
        port = "proxy"
        
        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }

        tags = [
          "boundary",
          "worker",
          "egress"
        ]
      }
    }
  }
}
