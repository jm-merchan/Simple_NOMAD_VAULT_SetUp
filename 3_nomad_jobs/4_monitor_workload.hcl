job "nginx-check" {
  datacenters = ["dc1"]
  type = "service"

  group "nginx-check" {
    task "nginx-check" {
      driver = "raw_exec"
      user = "ec2-user"

      env {
        HOME = "/home/ec2-user"
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