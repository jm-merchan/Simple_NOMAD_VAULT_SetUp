job "nginx-check-ubuntu" {
  datacenters = ["remote-site1"]
  type = "service"

  group "nginx-check-ubuntu" {
    # Constrain to the ubuntu remote client class (adjust if different)
    constraint {
      attribute = "${node.class}"
      operator  = "="
      value     = "ubuntu-linux-remote-site1-client"
    }
    task "nginx-check-ubuntu" {
      driver = "raw_exec"
      user = "nomadtest"

      env {
        HOME = "/home/nomadtest"
      }

      config {
        command = "/bin/bash"
        args = ["-c", <<-EOF
          export KUBECONFIG="${HOME}/.kube/config"

          # Wait for deployment to be ready
          echo "Waiting for nginx deployment to be ready..."
          kubectl wait --for=condition=available --timeout=300s deployment/nginx-deployment -n nginx-app


          # Keep the job running
          echo "Nginx deployment completed. Keeping container alive..."
          while true; do
            kubectl get pods -n nginx-app
            sleep 5
          done
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