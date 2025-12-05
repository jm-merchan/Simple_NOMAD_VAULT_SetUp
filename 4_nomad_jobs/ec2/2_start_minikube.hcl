job "minikube-start" {
  datacenters = ["dc1"]
  type = "batch"

  group "minikube-start" {
    task "minikube-start" {
      driver = "raw_exec"
      user = "ec2-user"

      env {
        HOME = "/home/ec2-user"
      }

      config {
        command = "/bin/bash"
        args = ["-c", <<-EOF
          # Start Minikube with none driver (suitable for containers/VMs)

          echo "Starting Minikube..."
          # Run Minikube using the Docker driver, executed as non-root `ec2-user`
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