job "http-server" {
  datacenters = ["remote-site1"]
  type        = "service"
  priority    = "50"
  
  group "web-server" {
    max_client_disconnect = "1h"
    
    network {
      mode = "host"
      port "http" {
        static = 8000
      }
    }
    
    # Service registration for HTTP file server
    service {
      name     = "http-file-server"
      port     = "http"
      provider = "nomad"
      tags     = ["http", "file-server", "artifacts"]
      
      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }
    
    task "python-http" {
      driver = "raw_exec"
      
      config {
        command = "/usr/bin/python3"
        args    = ["-m", "http.server", "8000", "--directory", "/home/jose"]
      }
      
      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
