job "home-assistant"{
    datacenters = ["remote-site1"]
    type = "service"
    priority = "100"
	group "hass-vm" {
        network {
            mode = "host"
            port "hasswebui" {
                static = 8223
            }
            port "vnc" {
                static = 5904
            }
        }
        
        # Service registration for Home Assistant web UI
        service {
            name     = "home-assistant-webui"
            port     = "hasswebui"
            provider = "nomad"
            tags     = ["home-assistant", "web-ui"]
        }
        
        # Service registration for VNC access
        service {
            name     = "home-assistant-vnc"
            port     = "vnc"
            provider = "nomad"
            tags     = ["vnc", "home-assistant", "remote-desktop"]
        }
        
        task "home-assistant" {
            driver = "qemu"
            
            config {
                image_path        = "hassos_ova-4.16.qcow2"
                accelerator       = "kvm"
                graceful_shutdown = true
                port_map {
                    vnc = 5904
                }
                args = [
                    "-vnc", "0.0.0.0:4",
                    "-net", "nic,model=e1000",
                    "-net", "user,hostfwd=tcp::${NOMAD_PORT_hasswebui}-:8123"
                ]
            }
            
            artifact {
                source = "https://github.com/home-assistant/operating-system/releases/download/4.16/hassos_ova-4.16.qcow2.gz"
                destination = "hassos_ova-4.16.qcow2"
                mode = "file"
            }
            
            resources {
                cpu = 100
                memory = 800
            }
        }
    }
}