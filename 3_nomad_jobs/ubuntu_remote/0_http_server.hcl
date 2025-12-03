job "http-server" {
  datacenters = ["remote-site1"]
  type        = "service"
  priority    = "50"
  
  group "web-server" {
    
    network {
      mode = "host"
      port "http" {
        static = 8000
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
