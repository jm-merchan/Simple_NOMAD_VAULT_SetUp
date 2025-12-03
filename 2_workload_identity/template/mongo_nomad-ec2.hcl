job "mongo-ec2" {
  namespace = "default"
  datacenters = ["remote-site1", "dc1"]

  group "db-ec2" {
    network {
      port "db" {
        static = 27017
      }
    }

    # Constrain group to EC2 client for testing Vault integration
    constraint {
      attribute = "${node.class}"
      operator  = "="
      value     = "amazon-linux-client"
    }

    service {
      provider = "nomad"
      name     = "mongo"
      port     = "db"
    }

    task "mongo-ec2" {
      driver = "docker"

      config {
        image = "mongo:7"
        ports = ["db"]
      }

      vault {}

      template {
        data        = <<EOF
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD={{with secret "kv/data/default/mongo/config"}}{{.Data.data.root_password}}{{end}}
EOF
        destination = "secrets/env"
        env         = true
      }
    }
  }
}
