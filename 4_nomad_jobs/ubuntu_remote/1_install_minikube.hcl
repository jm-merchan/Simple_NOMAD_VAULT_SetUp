job "install-minikube" {
  datacenters = ["remote-site1"]
  type = "batch"

  group "minikube-installer" {
    task "install-minikube" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-c", <<'EOF'
          # Install Minikube on Ubuntu

          echo "Installing Minikube (apt)..."

          # Install required packages
          export DEBIAN_FRONTEND=noninteractive
          sudo apt-get update -y
          sudo apt-get install -y curl wget apt-transport-https ca-certificates

          # Download latest Minikube binary and install
          echo "Downloading Minikube..."
          curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
          sudo install minikube-linux-amd64 /usr/local/bin/minikube
          rm -f minikube-linux-amd64

          # Verify installation
          echo "Minikube version:"
          minikube version || true

          # Install kubectl
          echo "Installing kubectl..."
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          sudo install -m 0755 kubectl /usr/local/bin/kubectl
          rm -f kubectl

          # Verify kubectl installation
          echo "kubectl version:"
          kubectl version --client || true

          echo "Minikube and kubectl installation completed successfully!"
        EOF
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}