job "install-minikube" {
  datacenters = ["dc1"]
  type = "batch"

  group "minikube-installer" {
    task "install-minikube" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-c", <<-EOF
          # Install Minikube on Amazon Linux 2

          echo "Installing Minikube..."

          # Install required packages
          sudo yum update -y
          sudo yum install -y curl wget

          # Download latest Minikube binary
          echo "Downloading Minikube..."
          curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

          # Install Minikube
          sudo install minikube-linux-amd64 /usr/local/bin/minikube

          # Clean up
          rm minikube-linux-amd64

          # Verify installation
          echo "Minikube version:"
          minikube version

          # Optional: Install kubectl
          echo "Installing kubectl..."
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          sudo install kubectl /usr/local/bin/kubectl
          rm kubectl

          # Verify kubectl installation
          echo "kubectl version:"
          kubectl version --client

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