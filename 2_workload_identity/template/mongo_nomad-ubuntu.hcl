job "mongo-ubuntu" {
  namespace = "default"
  datacenters = ["remote-site1", "dc1"]

  group "db-ubuntu" {
    network {
      port "db" {
        static = 27017
      }
    }

    # Constrain group to Ubuntu client
    constraint {
      attribute = "${node.class}"
      operator  = "="
      value     = "ubuntu-linux-remote-site1-client"
    }

    service {
      provider = "nomad"
      name     = "mongo"
      port     = "db"
    }

    task "mongo-ubuntu" {
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
