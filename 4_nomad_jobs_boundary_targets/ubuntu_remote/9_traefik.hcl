job "traefik" {
  datacenters = ["remote-site1"]
  namespace = "NS1"
  type = "system"

  group "traefik" {
    disconnect {
      lost_after  = "12h"
      reconcile   = "keep_original"
    }

    network {
      port "http" {
        static = 9999
      }
      port "admin" {
        static = 9998
      }
    }
    
    task "traefik" {
      driver = "docker"
      
      config {
        image = "traefik:v2.10"
        network_mode = "host"
        ports = ["http", "admin"]
        args = [
          "--api.dashboard=true",
          "--api.insecure=true",
          "--entrypoints.web.address=:9999",
          "--entrypoints.traefik.address=:9998",
          "--providers.nomad=true",
          "--providers.nomad.endpoint.address=https://${attr.unique.network.ip-address}:4646",
          "--providers.nomad.endpoint.tls.insecureSkipVerify=true",
          "--providers.nomad.endpoint.token=${NOMAD_TOKEN}",
          "--providers.nomad.namespaces=NS1",
          "--log.level=DEBUG"
        ]
      }
      
      # Use Nomad's task identity token for authentication
      identity {
        env = true
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
