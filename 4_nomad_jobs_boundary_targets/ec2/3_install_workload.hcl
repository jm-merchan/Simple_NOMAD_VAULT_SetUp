job "nginx-minikube" {
  datacenters = ["dc1"]
  type = "batch"

  group "nginx-deployment" {
    task "minikube-nginx" {
      driver = "raw_exec"
      user = "ec2-user"

      env {
        HOME = "/home/ec2-user"
      }

      config {
        command = "/bin/bash"
        args = ["-c", <<-EOF
          # Ensure kubeconfig is available and Minikube apiserver is reachable
          export KUBECONFIG="${HOME}/.kube/config"
          echo "Using KUBECONFIG=$KUBECONFIG"

          # Wait for Minikube apiserver to report as Running (timeout ~5 minutes)
          for i in {1..60}; do
            if minikube status -p nomad-test 2>/dev/null | grep -q "apiserver: Running"; then
              echo "Minikube apiserver is running"
              break
            fi
            echo "Waiting for Minikube apiserver... ($i/60)"
            sleep 1
          done


          # Create a namespace for our application
          kubectl create namespace nginx-app

          # Create a simple nginx deployment with custom index.html
          cat <<'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: nginx-app
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: nginx-html
        configMap:
          name: nginx-html-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-html-config
  namespace: nginx-app
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>Welcome to Nginx on Minikube</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                text-align: center;
                padding: 50px;
                background-color: #f0f0f0;
            }
            .container {
                max-width: 800px;
                margin: 0 auto;
                background: white;
                padding: 40px;
                border-radius: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            h1 {
                color: #2c3e50;
            }
            p {
                color: #7f8c8d;
                font-size: 18px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Welcome to Nginx on Minikube!</h1>
            <p>This nginx server is running inside a Kubernetes cluster managed by Minikube.</p>
            <p>Deployed via Nomad job scheduling.</p>
            <p><strong>Server:</strong> $(hostname)</p>
            <p><strong>Time:</strong> $(date)</p>
        </div>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: nginx-app
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
YAML

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