job "create-nomadtest-user" {
  datacenters = ["remote-site1"]
  type = "batch"

  group "create-nomadtest" {
    count = 1

    # Constrain to the ubuntu remote client class (adjust if different)
    constraint {
      attribute = "${node.class}"
      operator  = "="
      value     = "ubuntu-linux-remote-site1-client"
    }

    task "create-user" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-c", <<'EOF'
          set -euxo pipefail

          if id -u nomadtest >/dev/null 2>&1; then
            echo "user 'nomadtest' already exists"
            exit 0
          fi

          # Create system user 'nomadtest' with home directory and bash shell
          sudo useradd -m -s /bin/bash nomadtest || true

          # Add to docker group if it exists
          if getent group docker >/dev/null 2>&1; then
            sudo usermod -aG docker nomadtest || true
          fi

          # Ensure home directory permissions
          sudo mkdir -p /home/nomadtest
          sudo chown -R nomadtest:nomadtest /home/nomadtest || true

          echo "Created user 'nomadtest' (or it already existed)"
        EOF
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
