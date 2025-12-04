job "demo-webapp" {
  datacenters = ["remote-site1"]
  namespace = "NS1"

  group "demo" {
    count = 3
    network {
      port "http" {
        to = -1
      }
    }

    service {
      provider = "nomad"  # Use Nomad's native service discovery instead of Consul
      name = "demo-webapp"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "2s"
        timeout  = "2s"
      }
    }

    task "server" {
      env {
        PORT    = "${NOMAD_PORT_http}"
        NODE_IP = "${NOMAD_IP_http}"
      }

      driver = "docker"

      config {
        image = "hashicorp/demo-webapp-lb-guide"
        ports = ["http"]
      }
    }
  }
}
