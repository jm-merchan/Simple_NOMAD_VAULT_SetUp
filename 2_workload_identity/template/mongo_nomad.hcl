job "mongo" {
  namespace = "default"
  datacenters = ["remote-site1"]

  group "db" {
    network {
      port "db" {
        static = 27017
      }
    }

    # Constrain group to ubuntu remote clients (move constraint to group level)
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

    task "mongo" {
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
