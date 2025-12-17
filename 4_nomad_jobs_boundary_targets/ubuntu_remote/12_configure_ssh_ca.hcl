job "configure-ssh-ca-ubuntu" {
  type = "batch"
  
  datacenters = ["remote-site1"]

  group "ssh-config" {
    count = 1

    task "configure-ca" {
      driver = "raw_exec"

      template {
        data = <<-EOT
          VAULT_CA_KEY={{ with nomadVar "nomad/jobs/configure-ssh-ca-ubuntu" }}{{ .vault_ca_public_key }}{{ end }}
        EOT
        destination = "local/env.txt"
        env = true
      }

      config {
        command = "/bin/bash"
        args    = ["-c", local.file.configure_ssh_script]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}

locals {
  file = {
    configure_ssh_script = <<-EOT
      #!/bin/bash
      set -e
      
      echo "Creating temporary CA key file..."
      echo "$VAULT_CA_KEY" > /tmp/ca-key.pub
      
      echo "Configuring SSH on local host..."
      sudo mv /tmp/ca-key.pub /etc/ssh/ca-key.pub
      sudo chown 1000:1000 /etc/ssh/ca-key.pub
      sudo chmod 644 /etc/ssh/ca-key.pub
      
      # Check if TrustedUserCAKeys already exists in sshd_config
      if ! sudo grep -q "^TrustedUserCAKeys" /etc/ssh/sshd_config; then
        echo "TrustedUserCAKeys /etc/ssh/ca-key.pub" | sudo tee -a /etc/ssh/sshd_config
      fi
      
      # Check if PermitTTY already exists
      if ! sudo grep -q "^PermitTTY" /etc/ssh/sshd_config; then
        echo "PermitTTY yes" | sudo tee -a /etc/ssh/sshd_config
      fi
      
      # Update X11Forwarding
      sudo sed -i 's/X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config
      
      # Check if X11UseLocalhost already exists
      if ! sudo grep -q "^X11UseLocalhost" /etc/ssh/sshd_config; then
        echo "X11UseLocalhost no" | sudo tee -a /etc/ssh/sshd_config
      fi
      
      echo "Restarting SSH daemon..."
      sudo systemctl restart ssh
      
      echo "SSH CA configuration completed successfully!"
    EOT
  }
}
