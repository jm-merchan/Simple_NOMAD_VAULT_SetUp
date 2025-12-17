job "boundary-ubuntu-worker" {
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

      template {
        data = <<EOT
{{ with nomadVar "nomad/jobs/boundary-ubuntu-worker" }}
BOUNDARY_VERSION="{{ .boundary_version }}"
{{ end }}
EOT
        destination = "local/version.env"
        env         = true
      }

      config {
        command = "/bin/bash"
        args = ["-c", <<EOF
          echo "Required Boundary version: $BOUNDARY_VERSION"
          
          # Check if Boundary is already installed with the correct version
          if command -v boundary &> /dev/null; then
            CURRENT_VER=$(boundary version 2>&1 | head -n 1 | awk '{print $2}' | sed 's/^v//')
            echo "Found Boundary $CURRENT_VER"
            
            if [ "$CURRENT_VER" = "$BOUNDARY_VERSION" ]; then
              echo "Boundary $BOUNDARY_VERSION is already installed"
              exit 0
            else
              echo "Version mismatch: installed=$CURRENT_VER, required=$BOUNDARY_VERSION"
              echo "Removing old version..."
              sudo apt-get remove -y boundary-enterprise boundary || true
            fi
          fi

          echo "Installing Boundary $BOUNDARY_VERSION from releases.hashicorp.com..."

          # Ensure required tools exist
          sudo apt-get update
          sudo apt-get install -y ca-certificates curl unzip coreutils

          OS="linux"
          ARCH_RAW="$(uname -m)"
          case "$ARCH_RAW" in
            x86_64|amd64) ARCH="amd64";;
            aarch64|arm64) ARCH="arm64";;
            armv7l|armv6l) ARCH="arm";;
            *) echo "Unsupported architecture: $ARCH_RAW"; exit 1;;
          esac

          BASE_URL="https://releases.hashicorp.com/boundary/$BOUNDARY_VERSION"
          ZIP_NAME="boundary_$BOUNDARY_VERSION"_"$OS"_"$ARCH".zip
          SUMS_NAME="boundary_$BOUNDARY_VERSION"_SHA256SUMS
          
          WORKDIR="/tmp/boundary-install-$BOUNDARY_VERSION"
          rm -rf "$WORKDIR"
          mkdir -p "$WORKDIR"
          cd "$WORKDIR"

          echo "Downloading $ZIP_NAME"
          curl -fsSL -o "$ZIP_NAME" "$BASE_URL/$ZIP_NAME"
          curl -fsSL -o "$SUMS_NAME" "$BASE_URL/$SUMS_NAME"

          echo "Verifying SHA256SUMS"
          grep " $ZIP_NAME$" "$SUMS_NAME" > "$SUMS_NAME.filtered"
          if [ ! -s "$SUMS_NAME.filtered" ]; then
            echo "Could not find $ZIP_NAME in $SUMS_NAME"
            exit 1
          fi
          sha256sum -c "$SUMS_NAME.filtered"

          echo "Installing boundary binary"
          unzip -o "$ZIP_NAME"
          sudo install -m 0755 boundary /usr/local/bin/boundary

          # Verify installation
          FINAL_VERSION=$(boundary version | head -n 1 | awk '{print $2}' | sed 's/^v//')
          echo "Installed Boundary $FINAL_VERSION"
          
          echo "Boundary installation completed!"
EOF
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }

    task "boundary-worker" {
      driver = "raw_exec"

      # Read configuration from Nomad Variables
      template {
        data = <<EOT
{{ with nomadVar "nomad/jobs/boundary-ubuntu-worker" }}
VAULT_TOKEN="{{ .vault_token }}"
TRANSIT_MOUNT_PATH="{{ .transit_mount_path }}"
KMS_KEY_WORKER="{{ .kms_key_worker }}"
{{ end }}
VAULT_ADDR="${vault_addr}"
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
{{ with nomadVar "nomad/jobs/boundary-ubuntu-worker" }}
  address            = "${vault_addr}"
  token              = "{{ .vault_token }}"
  disable_renewal    = "true"
  
  # Key configuration
  mount_path         = "{{ .transit_mount_path }}"
  key_name           = "{{ .kms_key_worker }}"
{{ end }}
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

      # Health check using Nomad native service discovery
      service {
        provider = "nomad"
        name     = "boundary-egress-worker"
        port     = "proxy"
        
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
