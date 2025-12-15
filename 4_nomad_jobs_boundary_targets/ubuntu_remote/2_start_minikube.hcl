job "minikube-start" {
  datacenters = ["remote-site1"]
  type = "batch"

  group "minikube-start" {
    # Constrain to the ubuntu remote client class (adjust if different)
    constraint {
      attribute = "${node.class}"
      operator  = "="
      value     = "ubuntu-linux-remote-site1-client"
    }
    
    task "minikube-start" {
      driver = "raw_exec"
      user = "nomadtest"

      env {
        HOME = "/home/nomadtest"
      }

      config {
        command = "/bin/bash"
        args = ["-c", <<-EOF
          # Start Minikube with none driver (suitable for containers/VMs)

          echo "Starting Minikube..."
          # Run Minikube using the Docker driver, executed as non-root `nomadtest`
          minikube start -p nomad-test --driver=docker

          # Wait for Minikube to be ready
          echo "Waiting for Minikube to be ready..."
          kubectl wait --for=condition=Ready nodes --all --timeout=300s

          # Check Minikube status
          echo "Checking minikube status..."
          minikube status -p nomad-test

          echo "Minikube started successfully!"
        EOF
        ]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}